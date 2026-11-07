import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: panel
    readonly property string output: Quickshell.env("VOLUTA_SELECTOR_MONITOR")
    readonly property var palette: Quickshell.env("VOLUTA_SELECTOR_COLORS").split(" ")
    readonly property var targetScreen: Quickshell.screens.find(candidate => candidate.name === output) ?? null

    screen: targetScreen
    visible: targetScreen !== null && targetScreen.width >= 1152 && targetScreen.height >= 1024
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "voluta-selector-astrolabe"

    // Keep the surface inside the transparent opening of the shared 1152×1024 frame.
    implicitWidth: 704
    implicitHeight: 436
    anchors { top: true; left: true }
    margins.left: targetScreen ? Math.floor((targetScreen.width - 1152) / 2) + 272 : 0
    margins.top: targetScreen ? Math.floor((targetScreen.height - 1024) / 2) + 347 : 0

    Canvas {
        id: dial
        anchors.fill: parent
        readonly property double started: Date.now()
        readonly property real turn: 2 * Math.PI

        function arc(ctx, radius, from, to, color, opacity, width) {
            ctx.strokeStyle = color;
            ctx.globalAlpha = opacity;
            ctx.lineWidth = width;
            ctx.beginPath();
            ctx.arc(0, 0, radius, from, to);
            ctx.stroke();
        }

        function engraving(ctx, radius, angle, divisions, accent, light) {
            arc(ctx, radius - 9, 0, turn, light, 0.29, 1);
            arc(ctx, radius + 4, 0, turn, accent, 0.64, 2);
            for (let i = 0; i < divisions; ++i) {
                const major = i % 6 === 0;
                ctx.save();
                ctx.rotate(angle + i * turn / divisions);
                ctx.strokeStyle = light;
                ctx.globalAlpha = major ? 0.68 : 0.38;
                ctx.lineWidth = major ? 2 : 1;
                ctx.beginPath();
                ctx.moveTo(0, -radius);
                ctx.lineTo(0, -radius + (major ? 10 : 5));
                ctx.stroke();
                if (major) {
                    ctx.beginPath();
                    ctx.moveTo(0, -radius + 11);
                    ctx.lineTo(3, -radius + 15);
                    ctx.lineTo(0, -radius + 19);
                    ctx.lineTo(-3, -radius + 15);
                    ctx.closePath();
                    ctx.stroke();
                }
                ctx.restore();
            }
        }

        function sweep(ctx, radius, angle, direction, accent, light) {
            for (let index = 0; index < 3; ++index) {
                const head = angle + index * turn / 3;
                // The broad color band survives the blur around the sharper marks.
                for (const [length, color, opacity, width] of
                    [[0.54, accent, 0.58, 9], [0.31, light, 0.72, 3], [0.06, light, 0.94, 4]]) {
                    const tail = head - length * direction;
                    arc(ctx, radius, Math.min(head, tail), Math.max(head, tail), color, opacity, width);
                }
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            const seconds = (Date.now() - started) / 1000;
            const [outer, inner, light] = panel.palette;
            ctx.clearRect(0, 0, width, height);
            ctx.save();
            ctx.translate(width / 2, height / 2);
            ctx.scale(1.62, 1);
            const outerAngle = (seconds / 24 + 0.08) % 1 * turn;
            const innerAngle = -(seconds / 33 + 0.18) % 1 * turn;
            engraving(ctx, 200, outerAngle, 72, outer, light);
            engraving(ctx, 182, innerAngle, 48, inner, light);
            sweep(ctx, 200, outerAngle, 1, outer, light);
            sweep(ctx, 182, innerAngle, -1, inner, light);
            ctx.restore();
        }

        Timer {
            interval: 40
            repeat: true
            running: panel.visible
            onTriggered: dial.requestPaint()
        }
    }
}
