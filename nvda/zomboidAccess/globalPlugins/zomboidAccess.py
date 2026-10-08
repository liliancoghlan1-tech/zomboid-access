# Zomboid Access for NVDA.
# The Zomboid Access game mod writes one line per thing to say into
# %USERPROFILE%\Zomboid\Lua\ZomboidAccess_speech.txt. This plugin watches that file and speaks
# each new line. A line is "S<tab>text" (say now, interrupting), "Q<tab>text" (say after),
# "G<tab>text" (the tutorial guide: protected, see _speak) or "U<tab>text" (urgent: always interrupts).
# It only reads that one file: no network, no other programs.

import os
import time

import braille
import globalPluginHandler
import speech
import ui
import wx
from logHandler import log
from speech.commands import CallbackCommand

SPEECH_FILE = os.path.join(os.path.expandvars("%USERPROFILE%"), "Zomboid", "Lua", "ZomboidAccess_speech.txt")
# While the world loads, and on the screen after it, the game runs no mod code. Its own log says
# when loading is done, so the add-on announces that moment itself.
CONSOLE_FILE = os.path.join(os.path.expandvars("%USERPROFILE%"), "Zomboid", "console.txt")
LOADED_MARK = b"game loading took"
LOADED_TEXT = "The world has loaded. Press Cross to begin, or click the left mouse button."
POLL_MS = 40


class GlobalPlugin(globalPluginHandler.GlobalPlugin):
    def __init__(self):
        super().__init__()
        self._offset = self._size()  # start at the end: never replay old lines
        self._partial = b""
        self._consoleOffset = self._size(CONSOLE_FILE)
        self._consoleTail = b""
        self._guidePending = 0
        self._guardUntil = 0.0
        self._timer = wx.Timer()
        self._timer.Bind(wx.EVT_TIMER, self._poll)
        self._timer.Start(POLL_MS)

    def terminate(self):
        try:
            self._timer.Stop()
        except Exception:
            pass
        super().terminate()

    @staticmethod
    def _size(path=SPEECH_FILE):
        try:
            return os.path.getsize(path)
        except OSError:
            return 0

    def _pollConsole(self):
        size = self._size(CONSOLE_FILE)
        if size < self._consoleOffset:
            self._consoleOffset = 0  # a new game session rewrote the log
        if size == self._consoleOffset:
            return
        try:
            with open(CONSOLE_FILE, "rb") as f:
                f.seek(self._consoleOffset)
                data = f.read(min(size - self._consoleOffset, 4 * 1024 * 1024))
        except OSError:
            return
        self._consoleOffset += len(data)
        if LOADED_MARK in self._consoleTail + data:
            self._speak("S\t" + LOADED_TEXT)
            self._consoleTail = b""  # so the same line is never matched twice
        else:
            self._consoleTail = data[-64:]

    def _poll(self, evt=None):
        try:
            self._pollConsole()
        except Exception:
            log.error("zomboidAccess: console watch failed", exc_info=True)
        size = self._size()
        if size < self._offset:
            # The game started a new session and emptied the file.
            self._offset = 0
            self._partial = b""
        if size == self._offset:
            return
        try:
            with open(SPEECH_FILE, "rb") as f:
                f.seek(self._offset)
                data = f.read(size - self._offset)
        except OSError:
            return
        self._offset += len(data)
        data = self._partial + data
        lines = data.split(b"\n")
        self._partial = lines.pop()  # an unfinished last line waits for the next poll
        for raw in lines:
            self._speak(raw.decode("utf-8", "replace").rstrip("\r"))

    # The tutorial guide ("G") waits for what is being said, and while the guide talks, ordinary "S" lines
    # wait too instead of cutting it off. Only "U" (danger, combat) interrupts everything.
    # The guard ends when the guide's words have been spoken (a callback at the end of the line), or after a
    # generous time limit (if the player silences NVDA with Control, the callback never comes).
    def _guideDone(self):
        self._guidePending = max(0, self._guidePending - 1)

    def _guarded(self):
        if self._guidePending and time.monotonic() < self._guardUntil:
            return True
        self._guidePending = 0
        return False

    def _speak(self, line):
        if not line:
            return
        kind, _, text = line.partition("\t")
        if not text:
            kind, text = "S", line
        try:
            if kind == "G":
                now = time.monotonic()
                self._guardUntil = max(self._guardUntil, now) + 2.0 + 0.35 * len(text.split())
                self._guidePending += 1
                speech.speak([text, CallbackCommand(self._guideDone)])
                try:
                    braille.handler.message(text)
                except Exception:
                    pass
                return
            if kind == "U" or (kind == "S" and not self._guarded()):
                speech.cancelSpeech()
                self._guidePending = 0
            ui.message(text)
        except Exception:
            log.error("zomboidAccess: could not speak %r" % line, exc_info=True)
