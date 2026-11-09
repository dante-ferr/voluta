import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland

// Light from tall chapel windows falls from the top edge of every display and
// fades well below the bar. The beams are painted once per palette; animation
// only slides and breathes that finished texture, which the GPU composites.
// Settings and colors come from wallust/glow-state.json, written by
// scripts/render-decorations.py on every refresh.
ShellRoot {
    id: root

    property real opacityPeak: 0.55
    property int glowHeight: 220
    property int fps: 10
    property real drift: 14
    property bool animate: true
    property bool pauseOnBattery: true
    property var outputs: ({})
    property var colors: ["#aba3a7", "#c8858d", "#a17490"]
    readonly property bool moving: animate && !(pauseOnBattery && UPower.onBattery)

    readonly property int period: 640
    property real phase: 0
    property real breath: 1

    function apply(text: string): void {
        let data;
        try { data = JSON.parse(text); } catch (error) { return; }
        opacityPeak = data.opacity ?? opacityPeak;
        glowHeight = data.height ?? glowHeight;
        fps = Math.max(1, data.fps ?? fps);
        drift = data.drift ?? drift;
        animate = data.animate ?? animate;
        pauseOnBattery = data.pause_on_battery ?? pauseOnBattery;
        outputs = data.outputs ?? {};
        if (Array.isArray(data.colors) && data.colors.length >= 3)
            colors = data.colors;
    }

    FileView {
        path: Qt.resolvedUrl("wallust/glow-state.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }

    Timer {
        interval: Math.round(1000 / root.fps)
        repeat: true
        running: root.moving
        property double started: Date.now()
        onTriggered: {
            const seconds = (Date.now() - started) / 1000;
            root.phase = (root.phase + root.drift / root.fps) % root.period;
            // A slow breath reads as light shifting through clouds.
            root.breath = 0.82 + 0.18 * Math.sin(seconds * 2 * Math.PI / 11)
                + 0.06 * Math.sin(seconds * 2 * Math.PI / 4.3);
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            // Light wallpapers need no extra light; fade out by their top-band luminance.
            readonly property real strength: root.outputs[modelData.name] ?? 1
            visible: strength > 0
            anchors { top: true; left: true; right: true }
            implicitHeight: root.glowHeight
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "voluta-top-glow"

            Item {
                anchors.fill: parent
                clip: true
                opacity: root.opacityPeak * root.breath * panel.strength

                Canvas {
                    id: light
                    x: -root.phase
                    width: panel.width + root.period
                    height: panel.height
                    property var palette: root.colors
                    onPaletteChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    function tone(color, alpha) {
                        return Qt.rgba(color.r, color.g, color.b, alpha);
                    }

                    // A soft pane of light: transparent edges, brighter core.
                    function beam(ctx, x, span, color, strength) {
                        const gradient = ctx.createLinearGradient(x, 0, x + span, 0);
                        gradient.addColorStop(0, tone(color, 0));
                        gradient.addColorStop(0.35, tone(color, 0.55 * strength));
                        gradient.addColorStop(0.55, tone(color, 0.85 * strength));
                        gradient.addColorStop(1, tone(color, 0));
                        ctx.fillStyle = gradient;
                        ctx.fillRect(x, 0, span, height);
                    }

                    onPaint: {
                        const ctx = getContext("2d");
                        const [warm, first, second] = palette.map(c => Qt.color(c));
                        ctx.reset();
                        ctx.clearRect(0, 0, width, height);
                        // Ambient wash that spreads the light across the whole top edge.
                        const wash = ctx.createLinearGradient(0, 0, 0, height);
                        wash.addColorStop(0, tone(warm, 0.55));
                        wash.addColorStop(1, tone(warm, 0));
                        ctx.fillStyle = wash;
                        ctx.fillRect(0, 0, width, height);
                        // Beams lean like light through windows; the shear keeps
                        // the pattern periodic along x so the slide loops seamlessly.
                        ctx.setTransform(1, 0, 0.42, 1, 0, 0);
                        for (let base = -root.period; base < width + root.period; base += root.period) {
                            beam(ctx, base + 30, 120, first, 1.0);
                            beam(ctx, base + 215, 70, warm, 0.8);
                            beam(ctx, base + 330, 150, second, 0.9);
                            beam(ctx, base + 545, 55, first, 0.6);
                        }
                        ctx.setTransform(1, 0, 0, 1, 0, 0);
                        // Ease the whole texture out toward the bottom.
                        ctx.globalCompositeOperation = "destination-in";
                        const fade = ctx.createLinearGradient(0, 0, 0, height);
                        fade.addColorStop(0, "rgba(0,0,0,1)");
                        fade.addColorStop(0.2, "rgba(0,0,0,0.7)");
                        fade.addColorStop(0.5, "rgba(0,0,0,0.28)");
                        fade.addColorStop(0.8, "rgba(0,0,0,0.07)");
                        fade.addColorStop(1, "rgba(0,0,0,0)");
                        ctx.fillStyle = fade;
                        ctx.fillRect(0, 0, width, height);
                        ctx.globalCompositeOperation = "source-over";
                    }
                }
            }
        }
    }
}
