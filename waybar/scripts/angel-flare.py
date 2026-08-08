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

LABEL = " "
HOLD_SECONDS = 0.5

# Both of these move the highlight to a different numeral. Hyprland also emits
# v2 variants of each, which are deliberately ignored so one switch flares once.
TRIGGERS = ("workspace>>", "focusedmon>>")

_lock = threading.Lock()
_timer = None


def emit(css_class):
    with _lock:
        sys.stdout.write(json.dumps({"text": LABEL, "class": css_class}) + "\n")
        sys.stdout.flush()


def flare():
    global _timer
    if _timer is not None:
        _timer.cancel()
    emit("flare")
    _timer = threading.Timer(HOLD_SECONDS, emit, args=("",))
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
