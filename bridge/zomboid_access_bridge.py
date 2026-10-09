# Zomboid Access speech bridge.
# The Zomboid Access game mod writes one line per thing to say into
# %USERPROFILE%\Zomboid\Lua\ZomboidAccess_speech.txt. This program watches that file and speaks each new line
# through Prism (https://github.com/ethindp/prism), which talks to whichever screen reader is running
# (NVDA, JAWS, ZDSR, ...) or, with none, to the Windows voices (OneCore, SAPI).
# A line is "S<tab>text" (say now, interrupting), "Q<tab>text" (say after), "P<tab>text" (say now, and don't let
# the next lines cut it off), "G<tab>text" (the tutorial guide on the radio, see Speaker.say) or "U<tab>text"
# (urgent: always interrupts). Lines starting with "#" mark a fresh file.
# Voices: everything is said in the "speech" voice except the radio, which has its own "radio" voice. Each is the
# screen reader or a SAPI or OneCore voice, set in the game's Options, Accessibility: the mod sends
# "V<tab>channel<tab>engine<tab>voice<tab>speed<tab>volume" to change one and "T<tab>channel<tab>text" for a sample,
# and the bridge lists the voices and current settings in Zomboid\Lua\ZomboidAccess_voices.txt for it.
#
# While the game starts, while a world loads, and on the "press to start" screen after it, the game runs no mod
# code at all. The game's own log (Zomboid\console.txt) says when each of those begins and ends, so the bridge
# announces them itself.
#
# Usage:
#   ZomboidAccessBridge.exe %command%   as the Steam launch option: starts the game, speaks while it runs,
#                                        and closes when the game closes. (The installer sets this up.)
#   ZomboidAccessBridge.exe             waits for the game to start, speaks while it runs, closes with it.
#   ZomboidAccessBridge.exe --test      says one line through the screen reader and exits.
# Files: it reads the speech file and the game log, writes the voice list for the mod (Zomboid\Lua), and keeps its
# voice settings (voices.json) and log next to itself. When the game closes it deletes the speech file and the
# voice list (the mod starts the speech file again each time and keeps it small). No network.

import ctypes
import json
import logging
import os
import re
import subprocess
import sys
import threading
import time

VERSION = "0.9.3"
ZOMBOID = os.path.join(os.path.expandvars("%USERPROFILE%"), "Zomboid")
SPEECH_FILE = os.path.join(ZOMBOID, "Lua", "ZomboidAccess_speech.txt")
STATE_FILE = os.path.join(ZOMBOID, "Lua", "ZomboidAccess_voices.txt")
CONSOLE_FILE = os.path.join(ZOMBOID, "console.txt")
GAME_EXE = "ProjectZomboid64.exe"
POLL_S = 0.04

# What the game's log says, and what to say then. Every way into a world goes
# LoadingQueueState -> GameLoadingState ("game loading took N seconds" when it is done) -> the
# "press to start" screen -> exit GameLoadingState when the player presses -> IngameState.
STATE_EXIT = b"STATE: exit zombie.gameStates."
LOADED_MARK = b"game loading took"
STARTING_TEXT = "Starting Project Zomboid. This takes about a minute."
STILL_STARTING_TEXT = "Still starting."
STILL_LOADING_TEXT = "Still loading the world."
LOADED_TEXT = "The world has loaded. Press {Cross} to begin, or click the left mouse button."
STILL_WAITING_TEXT = "The world is ready. Press {Cross} to begin, or click the left mouse button."
LEAVING_TEXT = "Leaving the world and saving. Please wait."
STILL_LEAVING_TEXT = "Still saving."
REMIND_S = 20.0  # how long a silent loading screen waits before saying it's still there

log = logging.getLogger("zomboidAccess")

# Button names as the game's Controller option "Button style" labels them, like the mod: 1 Xbox, 2 PlayStation,
# 3 Steam Deck. Our own lines write {Cross}.
OPTIONS_FILE = os.path.join(ZOMBOID, "options.ini")
BUTTON_NAMES = {"1": {"Cross": "A"}, "3": {"Cross": "A"}}


def buttons(text):
    style = "2"
    try:
        with open(OPTIONS_FILE, encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.startswith("controllerButtonStyle="):
                    style = line.split("=", 1)[1].strip()
    except OSError:
        pass
    names = BUTTON_NAMES.get(style, {})
    return re.sub(r"{(\w+)}", lambda m: names.get(m.group(1), m.group(1)), text)


def _here():
    return os.path.dirname(sys.executable if getattr(sys, "frozen", False) else os.path.abspath(__file__))


class Tail:
    """New complete lines of a file that the game may empty or recreate at any time.
    A new session is noticed by the file shrinking, being recreated (its file ID; not the creation time, which
    Windows reuses for a file recreated within seconds), or by its first bytes changing: both files begin with a
    timestamp line (the mod's "#<ms>", the game log's date), and a restarted file can already be as long as what
    was read before."""

    HEAD = 64

    def __init__(self, path, fromStart=False):
        self.path = path
        st = self._stat()
        self.offset = 0 if fromStart or not st else st.st_size
        self.fileId = st.st_ino if st else None
        self.head = self._readHead() if self.offset else b""
        self.partial = b""

    def _readHead(self):
        try:
            with open(self.path, "rb") as f:
                return f.read(self.HEAD)
        except OSError:
            return b""

    def _stat(self):
        try:
            return os.stat(self.path)
        except OSError:
            return None

    def read(self, limit=4 * 1024 * 1024):
        st = self._stat()
        if not st:
            return []
        if st.st_size < self.offset or st.st_ino != self.fileId:
            self._restart(st)
        if st.st_size == self.offset:
            return []
        try:
            with open(self.path, "rb") as f:
                if self.head and f.read(len(self.head)) != self.head:
                    self._restart(st)
                f.seek(self.offset)
                data = f.read(min(st.st_size - self.offset, limit))
                self.offset += len(data)
                if len(self.head) < self.HEAD:
                    f.seek(0)
                    self.head = f.read(min(self.HEAD, self.offset))
        except OSError:
            return []
        lines = (self.partial + data).split(b"\n")
        self.partial = lines.pop()  # an unfinished last line waits for the next read
        return [l for l in lines if not l.startswith(b"#")]

    def _restart(self, st):
        # The game started a new session, or the mod started its file again.
        self.offset = 0
        self.partial = b""
        self.head = b""
        self.fileId = st.st_ino


SCREEN_READER = "screen reader"
ENGINES = {"SAPI": "SAPI", "OneCore": "ONE_CORE"}  # what players can choose besides the screen reader
CHANNELS = ("speech", "radio")
DEFAULT_VOICE = {"engine": SCREEN_READER, "voice": "", "rate": 50, "volume": 100}


class Channel:
    """One voice: the screen reader, or a SAPI or OneCore voice of its own (with its own speed and volume)."""

    def __init__(self, name, settings):
        self.name = name
        self.settings = dict(DEFAULT_VOICE, **settings)
        self.own = None  # this channel's own backend, when it isn't the screen reader
        self.guardUntil = 0.0
        self.guardFrom = 0.0

    @property
    def engine(self):
        return self.settings["engine"]

    def configure(self, ctx, prism):
        self.own = None
        if self.engine == SCREEN_READER:
            return
        try:
            b = ctx.create(getattr(prism.BackendId, ENGINES[self.engine]))
            want = self.settings["voice"]
            for i in range(b.voices_count):
                if b.get_voice_name(i) == want:
                    b.voice = i
                    break
            b.rate = max(0, min(100, int(self.settings["rate"]))) / 100.0
            b.volume = max(0, min(100, int(self.settings["volume"]))) / 100.0
            self.own = b
            log.info("%s voice: %s %s, speed %s, volume %s", self.name, self.engine, want,
                     self.settings["rate"], self.settings["volume"])
        except Exception:
            log.error("%s voice %r could not be set up; using the screen reader", self.name, self.settings,
                      exc_info=True)


class Speaker:
    """Prism, with one voice per channel, and the tutorial guide's protection the NVDA add-on had."""

    def __init__(self):
        import prism  # here, not at the top: if it can't load, the game must still start

        self.prism = prism
        self.ctx = prism.Context()
        self.reader = None
        self.nextCheck = 0.0
        self._pick()
        saved = self._load()
        self.channels = {c: Channel(c, saved.get(c, {})) for c in CHANNELS}
        for ch in self.channels.values():
            ch.configure(self.ctx, prism)
        self.voices = self._listVoices()

    # ---------- settings ----------
    # Kept next to the bridge, so they also apply to what is said before the mod runs (starting, loading).

    @staticmethod
    def _settingsFile():
        return os.path.join(_here(), "voices.json")

    def _load(self):
        try:
            with open(self._settingsFile(), encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return {}

    def _save(self):
        try:
            with open(self._settingsFile(), "w", encoding="utf-8") as f:
                json.dump({c: ch.settings for c, ch in self.channels.items()}, f, indent=1)
        except OSError:
            log.error("could not save the voices", exc_info=True)

    def _listVoices(self):
        voices = []
        for engine, bid in ENGINES.items():
            try:
                b = self.ctx.create(getattr(self.prism.BackendId, bid))
                voices += [(engine, b.get_voice_name(i)) for i in range(b.voices_count)]
            except Exception:
                log.info("no %s voices", engine)
        return voices

    # The mod reads this to fill the voice settings in Options, Accessibility. Removed when the game closes.
    def writeState(self):
        lines = ["#" + str(int(time.time() * 1000)), "reader\t" + (self.reader.name if self.reader else "none")]
        lines += ["voice\t%s\t%s" % v for v in self.voices]
        for c, ch in self.channels.items():
            st = ch.settings
            lines.append("set\t%s\t%s\t%s\t%d\t%d" % (c, st["engine"], st["voice"], st["rate"], st["volume"]))
        try:
            with open(STATE_FILE, "w", encoding="utf-8", newline="\n") as f:
                f.write("\n".join(lines) + "\n")
        except OSError:
            log.error("could not write the voice list", exc_info=True)

    def setVoice(self, fields):
        # "V<tab>channel<tab>engine<tab>voice<tab>speed<tab>volume", from Options, Accessibility.
        if len(fields) < 5 or fields[0] not in self.channels:
            return
        name, engine, voice, rate, volume = fields[:5]
        if engine != SCREEN_READER and engine not in ENGINES:
            return
        try:
            settings = {"engine": engine, "voice": voice, "rate": int(rate), "volume": int(volume)}
        except ValueError:
            return
        ch = self.channels[name]
        ch.settings = settings
        ch.configure(self.ctx, self.prism)
        self._save()
        self.writeState()

    # ---------- the screen reader ----------

    def _pick(self):
        try:
            best = self.ctx.acquire_best()
        except Exception:
            log.error("no speech backend", exc_info=True)
            return
        if self.reader is None or best.name != self.reader.name:
            self.reader = best
            log.info("screen reader: %s", best.name)

    def refresh(self):
        # A screen reader started or closed after us: move to the best one there is now.
        now = time.monotonic()
        if now >= self.nextCheck:
            self.nextCheck = now + 5.0
            self._pick()

    # ---------- speaking ----------

    def _backend(self, ch):
        return ch.own or self.reader

    def _out(self, ch, text, interrupt):
        b = self._backend(ch)
        if b is None:
            return
        if b.features.supports_output:
            b.output(text, interrupt)
        else:
            b.speak(text, interrupt)

    # A protected line (the tutorial guide "G" when it shares the everyday voice, or "P") isn't cut off: while it
    # is said, ordinary "S" lines wait instead. Only "U" (danger, combat) interrupts everything.
    # The guard lasts until the voice says it has stopped, when it can tell us (NVDA can't, through Prism),
    # or else about as long as the words take at a brisk screen reader speed.
    def _guard(self, ch, text):
        now = time.monotonic()
        ch.guardUntil = max(ch.guardUntil, now) + 1.0 + 0.25 * len(text.split())
        ch.guardFrom = now

    def _guarded(self, ch):
        now = time.monotonic()
        if now >= ch.guardUntil:
            return False
        b = self._backend(ch)
        if b is not None and b.features.supports_is_speaking and now - ch.guardFrom > 0.5:
            try:
                if not b.speaking:
                    ch.guardUntil = 0.0
                    return False
            except Exception:
                pass
        return True

    def say(self, line):
        if not line:
            return
        kind, _, text = line.partition("\t")
        if not text:
            kind, text = "S", line
        if kind == "V":
            self.setVoice(text.split("\t"))
            return
        speech, radio = self.channels["speech"], self.channels["radio"]
        try:
            if kind == "T":
                # A sample of a voice, as it is changed in Options: "T<tab>channel<tab>text".
                name, _, sample = text.partition("\t")
                if name in self.channels and sample.strip():
                    self._out(self.channels[name], sample.strip(), True)
                return
            text = text.strip()
            if not text:
                return
            if kind == "G":
                # The radio queues behind itself. In the everyday voice it is protected; in a voice of its own
                # it talks alongside, and nothing has to wait for it.
                if self._backend(radio) is self._backend(speech):
                    self._guard(speech, text)
                    self._out(speech, text, False)
                else:
                    self._out(radio, text, False)
            elif kind == "U":
                speech.guardUntil = 0.0
                self._out(speech, text, True)
            elif kind == "P":
                self._out(speech, text, not self._guarded(speech))
                self._guard(speech, text)
            elif kind == "S" and not self._guarded(speech):
                self._out(speech, text, True)
            else:
                self._out(speech, text, False)
        except Exception:
            log.error("could not speak %r", line, exc_info=True)


class Loading:
    """Says what the game is doing while no mod code runs, from the game's log."""

    def __init__(self, speaker, launching):
        self.speaker = speaker
        self.phase = "starting" if launching else None
        self.lastSaid = time.monotonic()

    def _say(self, text):
        self.speaker.say("S\t" + buttons(text))
        self.lastSaid = time.monotonic()

    def heard(self):
        # The mod spoke: Lua is running, so whatever we were waiting on is over.
        self.lastSaid = time.monotonic()
        if self.phase in ("starting", "leaving"):
            self.phase = None

    def line(self, raw):
        if LOADED_MARK in raw:
            self.phase = "ready"
            self._say(LOADED_TEXT)
            return
        i = raw.find(STATE_EXIT)
        if i < 0:
            return
        state = raw[i + len(STATE_EXIT):].strip().rstrip(b".")
        if state == b"LoadingQueueState":
            # The mod has just said "Loading the world..."; from here on Lua is silent.
            self.phase = "loading"
            self.lastSaid = time.monotonic()
        elif state == b"GameLoadingState":
            self.phase = None  # the player pressed to begin; the mod speaks again
        elif state == b"IngameState":
            self.phase = "leaving"
            self._say(LEAVING_TEXT)
        elif state in (b"TISLogoState", b"TermsOfServiceState"):
            if self.phase == "starting":
                self.phase = None

    def tick(self):
        if self.phase is None or time.monotonic() - self.lastSaid < REMIND_S:
            return
        self._say({
            "starting": STILL_STARTING_TEXT,
            "loading": STILL_LOADING_TEXT,
            "ready": STILL_WAITING_TEXT,
            "leaving": STILL_LEAVING_TEXT,
        }[self.phase])


def _gameRunning():
    try:
        out = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq " + GAME_EXE, "/NH"],
            capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW, timeout=10,
        ).stdout
        return GAME_EXE.lower().encode() in out.lower()
    except Exception:
        return True


def _alreadyRunning():
    # One bridge at a time, or every line is said twice.
    kernel32 = ctypes.windll.kernel32
    _alreadyRunning.mutex = kernel32.CreateMutexW(None, False, "Local\\ZomboidAccessBridge")
    return kernel32.GetLastError() == 183  # ERROR_ALREADY_EXISTS


def main(argv):
    try:
        logging.basicConfig(
            filename=os.path.join(_here(), "bridge.log"), filemode="w", level=logging.INFO,
            format="%(asctime)s %(levelname)s %(message)s",
        )
    except OSError:
        pass
    log.info("Zomboid Access bridge %s, arguments %r", VERSION, argv)

    if argv[:1] == ["--test"]:
        sp = Speaker()
        sp.say("S\tZomboid Access is speaking through " + (sp.reader.name if sp.reader else "nothing") + ".")
        time.sleep(3)
        return 0

    # Steam waits on us: start the game first, so a problem with speech never keeps it from starting.
    # The packaged bridge points Windows' DLL search at its own folder, and a program it starts inherits that: the game
    # then loaded the bridge's VCRUNTIME140.dll and kept it open. Give the game the normal search.
    # (Then put ours back: the bridge itself still loads Prism from there.)
    kernel32, ours = ctypes.windll.kernel32, ctypes.create_unicode_buffer(1024)
    hadOurs = kernel32.GetDllDirectoryW(1024, ours) > 0
    kernel32.SetDllDirectoryW(None)
    try:
        game = subprocess.Popen(argv) if argv else None
    finally:
        if hadOurs:
            kernel32.SetDllDirectoryW(ours.value)
    if game:
        log.info("started the game, pid %d", game.pid)
    try:
        return speak(game)
    except Exception:
        log.error("the bridge stopped", exc_info=True)
        return game.wait() if game else 1


def speak(game):
    if _alreadyRunning():
        log.info("another bridge is already speaking")
        return game.wait() if game else 0

    sp = Speaker()
    sp.writeState()
    speech = Tail(SPEECH_FILE)
    console = Tail(CONSOLE_FILE)
    loading = Loading(sp, launching=game is not None)
    if game:
        sp.say("S\t" + STARTING_TEXT)

    gameGone = threading.Event()

    def watch():
        if game:
            game.wait()
        else:
            # Started on its own: wait for the game to start, then for it to close.
            while not _gameRunning():
                time.sleep(2)
        # The process Steam started may hand over to another one: wait until no game is left.
        while _gameRunning():
            time.sleep(2)
        gameGone.set()
    threading.Thread(target=watch, daemon=True).start()

    while not gameGone.is_set():
        try:
            sp.refresh()
            for raw in console.read():
                loading.line(raw)
            for raw in speech.read():
                loading.heard()
                sp.say(raw.decode("utf-8", "replace").rstrip("\r"))
            loading.tick()
        except Exception:
            log.error("poll failed", exc_info=True)
        time.sleep(POLL_S)
    log.info("the game has closed")
    # Nothing in these files is needed once the game is gone.
    for path in (SPEECH_FILE, STATE_FILE):
        try:
            os.remove(path)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
