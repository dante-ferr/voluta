#!/usr/bin/env python3
"""Drive the waybar angels from Hyprland's event socket.

Emits a waybar JSON line carrying the "flare" class whenever the focused
workspace changes, then clears it again so the CSS animation can retrigger on
the next switch. The label itself is always a single space: the figure is a
background image, and waybar hides a custom module whose text is empty.
"""
import json
import os
import socket
import sys
import threading
import time

LABEL = " "
HOLD_SECONDS = 0.5
# GTK restarts a CSS animation only when the class is seen to leave and return,
# and waybar coalesces lines written in the same idle pass into a single style
# update, which would swallow the removal. This beat lets the removal land so a
# fresh switch retriggers the animation even mid-flare.
REARM_SECONDS = 0.05

# Both of these move the highlight to a different numeral. Hyprland also emits
# v2 variants of each, which are deliberately ignored so one switch flares once.
TRIGGERS = ("workspace>>", "focusedmon>>")

_lock = threading.Lock()
_timer = None
_gen = 0


def _write(css_class):
    sys.stdout.write(json.dumps({"text": LABEL, "class": css_class}) + "\n")
    sys.stdout.flush()


def emit(css_class):
    with _lock:
        _write(css_class)


def clear(gen):
    with _lock:
        # A flare newer than this timer is already showing and its own timer
        # will clear it; without the check an expiring timer could snuff out a
        # flare that had just started.
        if gen == _gen:
            _write("")


def flare():
    global _timer, _gen
    with _lock:
        if _timer is not None:
            _timer.cancel()
        _gen += 1
        gen = _gen
    _write("")
    time.sleep(REARM_SECONDS)
    _write("flare")
    _timer = threading.Timer(HOLD_SECONDS, clear, args=(gen,))
    _timer.daemon = True
    _timer.start()


def event_socket():
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not signature:
        return None
    runtime = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    path = os.path.join(runtime, "hypr", signature, ".socket2.sock")
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(path)
    except OSError:
        return None
    return sock


def main():
    emit("")
    sock = event_socket()
    if sock is None:
        # No Hyprland to listen to; hold the idle figure rather than exiting,
        # which would make waybar drop the module altogether.
        threading.Event().wait()
        return
    with sock.makefile("r", errors="replace") as stream:
        for line in stream:
            if line.startswith(TRIGGERS):
                flare()


main()
