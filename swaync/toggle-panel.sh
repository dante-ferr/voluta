#!/bin/sh
# Toggle the native panel directly; opening must not wait on client-side setup.
if command -v gdbus >/dev/null 2>&1; then
    exec gdbus call --session --timeout 5 \
        --dest org.erikreider.swaync.cc \
        --object-path /org/erikreider/swaync/cc \
        --method org.erikreider.swaync.cc.ToggleVisibility >/dev/null
fi
exec swaync-client -t -sw
