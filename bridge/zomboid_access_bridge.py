# Zomboid Access speech bridge.
# The Zomboid Access game mod writes one line per thing to say into
# %USERPROFILE%\Zomboid\Lua\ZomboidAccess_speech.txt. This program watches that file and speaks each new line
# through Prism (https://github.com/ethindp/prism), which talks to whichever screen reader is running
# (NVDA, JAWS, ZDSR, ...) or, with none, to the Windows voices (OneCore, SAPI).
# A line is "S<tab>text" (say now, interrupting), "Q<tab>text" (say after), "G<tab>text" (the tutorial guide:
# protected, see _speak) or "U<tab>text" (urgent: always interrupts).
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
# It only reads those two files, deletes the speech file when the game closes (the mod starts it again each time
# and keeps it small), and writes its own log next to itself: no network.

import ctypes
import logging
import os
import subprocess
import sys
import threading
import time

VERSION = "0.9.2"
ZOMBOID = os.path.join(os.path.expandvars("%USERPROFILE%"), "Zomboid")
SPEECH_FILE = os.path.join(ZOMBOID, "Lua", "ZomboidAccess_speech.txt")
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
LOADED_TEXT = "The world has loaded. Press Cross to begin, or click the left mouse button."
STILL_WAITING_TEXT = "The world is ready. Press Cross to begin, or click the left mouse button."
LEAVING_TEXT = "Leaving the world and saving. Please wait."
STILL_LEAVING_TEXT = "Still saving."
REMIND_S = 20.0  # how long a silent loading screen waits before saying it's still there

log = logging.getLogger("zomboidAccess")


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


class Speaker:
    """Prism, with the tutorial guide's protection the NVDA add-on had."""

    def __init__(self):
        import prism  # here, not at the top: if it can't load, the game must still start

        self.ctx = prism.Context()
        self.backend = None
        self.nextCheck = 0.0
        self.guardUntil = 0.0
        self._pick()

    def _pick(self):
        try:
            best = self.ctx.acquire_best()
        except Exception:
            log.error("no speech backend", exc_info=True)
            return
        if self.backend is None or best.name != self.backend.name:
            self.backend = best
            self.features = best.features
            log.info("speaking through %s", best.name)

    def refresh(self):
        # A screen reader started or closed after us: move to the best one there is now.
        now = time.monotonic()
        if now >= self.nextCheck:
            self.nextCheck = now + 5.0
            self._pick()

    # The tutorial guide ("G") waits for what is being said, and while the guide talks, ordinary "S" lines
    # wait too instead of cutting it off. Only "U" (danger, combat) interrupts everything.
    # The guard lasts as long as the guide's words take to say, or until the screen reader says it has
    # stopped talking, when it can tell us (NVDA can't, through Prism).
    def _guarded(self):
        now = time.monotonic()
        if now >= self.guardUntil:
            return False
        if self.features.supports_is_speaking:
            try:
                if not self.backend.speaking:
                    self.guardUntil = 0.0
                    return False
            except Exception:
                pass
        return True

    def _out(self, text, interrupt):
        b = self.backend
        if b is None:
            return
        if self.features.supports_output:
            b.output(text, interrupt)
        else:
            b.speak(text, interrupt)

    def say(self, line):
        if not line:
            return
        kind, _, text = line.partition("\t")
        if not text:
            kind, text = "S", line
        text = text.strip()
        if not text:
            return
        try:
            if kind == "G":
                now = time.monotonic()
                self.guardUntil = max(self.guardUntil, now) + 2.0 + 0.35 * len(text.split())
                self._out(text, False)
                return
            if kind == "U":
                self.guardUntil = 0.0
                self._out(text, True)
            elif kind == "S" and not self._guarded():
                self._out(text, True)
            else:
                self._out(text, False)
        except Exception:
            log.error("could not speak %r", line, exc_info=True)


class Loading:
    """Says what the game is doing while no mod code runs, from the game's log."""

    def __init__(self, speaker, launching):
        self.speaker = speaker
        self.phase = "starting" if launching else None
        self.lastSaid = time.monotonic()

    def _say(self, text):
        self.speaker.say("S\t" + text)
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
        sp.say("S\tZomboid Access is speaking through " + (sp.backend.name if sp.backend else "nothing") + ".")
        time.sleep(3)
        return 0

    # Steam waits on us: start the game first, so a problem with speech never keeps it from starting.
    game = subprocess.Popen(argv) if argv else None
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
    # Nothing in the speech file is needed once the game is gone.
    try:
        os.remove(SPEECH_FILE)
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
