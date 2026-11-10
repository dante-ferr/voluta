import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland

// Light from tall chapel windows falls from the top edge of every display and
// fades well below the bar. The beams are painted once per palette; animation
// only slides and breathes that finished texture, which the GPU composites.
// A mask follows Waybar's measured left/center/right module clusters so empty
// gaps stay quieter. Cluster geometry is written by the Waybar GTK helper.
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
    property var bars: []
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

    function applyClusters(text: string): void {
        let data;
        try { data = JSON.parse(text); } catch (error) { return; }
        bars = Array.isArray(data.bars) ? data.bars : [];
    }

    function clustersFor(screen): var {
        let byWidth = null;
        for (let i = 0; i < bars.length; i++) {
            const bar = bars[i];
            const clusters = Array.isArray(bar.clusters) ? bar.clusters : [];
            if (bar.width === screen.width && bar.x === screen.x && bar.y === screen.y)
                return clusters;
            if (bar.width === screen.width)
                byWidth = clusters;
        }
        return byWidth || [];
    }

    FileView {
        path: Qt.resolvedUrl("wallust/glow-state.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
    }

    FileView {
        path: Qt.resolvedUrl("wallust/glow-clusters.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyClusters(text())
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
            readonly property var liveClusters: root.clustersFor(modelData)
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

                // Sliding light texture; kept invisible so OpacityMask is the only draw.
                Item {
                    id: lit
                    anchors.fill: parent
                    visible: false
                    clip: true

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
                            // Soft ambient wash; beams carry most of the animated light.
                            const wash = ctx.createLinearGradient(0, 0, 0, height);
                            wash.addColorStop(0, tone(warm, 0.65));
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

                // Soft lobes under the measured Waybar module clusters.
                // Drawn sizes ease toward live geometry so title/MPRIS changes do not snap.
                Item {
                    id: clusters
                    anchors.fill: parent
                    visible: false

                    Canvas {
                        id: clusterMask
                        anchors.fill: parent
                        property var targetLobes: panel.liveClusters
                        property var drawnLobes: []
                        property bool settling: false
                        // Tight full-strength core on the measured boxes; soft fade stays wide.
                        readonly property real pad: 20
                        // Long fade; a short linear ramp reads as a vertical cut.
                        readonly property real feather: 340
                        readonly property real floor: 0.12

                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onTargetLobesChanged: {
                            const next = Array.isArray(targetLobes) ? targetLobes : [];
                            if (!drawnLobes.length && next.length) {
                                drawnLobes = next.map(l => ({
                                    x: l.x ?? 0,
                                    width: l.width ?? 0
                                }));
                                settling = false;
                                requestPaint();
                                return;
                            }
                            if (!next.length) {
                                drawnLobes = [];
                                settling = false;
                                requestPaint();
                                return;
                            }
                            settling = true;
                        }

                        function easeToward(dt): bool {
                            const next = Array.isArray(targetLobes) ? targetLobes : [];
                            if (!next.length) {
                                drawnLobes = [];
                                return false;
                            }
                            // ~450 ms time constant: slow glide when a plate resizes.
                            const amount = 1 - Math.exp(-dt / 0.45);
                            const current = drawnLobes.slice();
                            while (current.length < next.length)
                                current.push({
                                    x: next[current.length].x ?? 0,
                                    width: next[current.length].width ?? 0
                                });
                            let moving = false;
                            const eased = [];
                            for (let i = 0; i < next.length; i++) {
                                const toX = next[i].x ?? 0;
                                const toW = next[i].width ?? 0;
                                const from = current[i] || { x: toX, width: toW };
                                const x = from.x + (toX - from.x) * amount;
                                const width = from.width + (toW - from.width) * amount;
                                if (Math.abs(toX - x) > 0.4 || Math.abs(toW - width) > 0.4)
                                    moving = true;
                                eased.push({
                                    x: moving ? x : toX,
                                    width: moving ? width : toW
                                });
                            }
                            drawnLobes = eased;
                            return moving;
                        }

                        Timer {
                            interval: 32
                            repeat: true
                            running: clusterMask.settling
                            property double last: Date.now()
                            onRunningChanged: last = Date.now()
                            onTriggered: {
                                const now = Date.now();
                                const dt = Math.min(0.1, (now - last) / 1000);
                                last = now;
                                clusterMask.settling = clusterMask.easeToward(dt);
                                clusterMask.requestPaint();
                            }
                        }

                        onPaint: {
                            const ctx = getContext("2d");
                            const w = width;
                            const h = height;
                            const floor = clusterMask.floor;
                            const pad = clusterMask.pad;
                            const feather = clusterMask.feather;
                            const lobes = drawnLobes;
                            ctx.reset();
                            ctx.clearRect(0, 0, w, h);

                            // No bar on this output: leave the glow unshaped.
                            if (!lobes || lobes.length === 0) {
                                ctx.fillStyle = Qt.rgba(1, 1, 1, 1);
                                ctx.fillRect(0, 0, w, h);
                                return;
                            }

                            // Per-column max of smooth lobes. Stacked gradients overwrite each
                            // other and leave a hard edge where one rect ends.
                            function lobeAlpha(x, lobe) {
                                const core0 = (lobe.x ?? 0) - pad;
                                const core1 = (lobe.x ?? 0) + (lobe.width ?? 0) + pad;
                                let t = 1;
                                if (x < core0)
                                    t = (x - (core0 - feather)) / feather;
                                else if (x > core1)
                                    t = ((core1 + feather) - x) / feather;
                                t = Math.max(0, Math.min(1, t));
                                t = t * t * t * (t * (t * 6 - 15) + 10);
                                return floor + (1 - floor) * t;
                            }

                            const step = 4;
                            for (let x = 0; x < w; x += step) {
                                const sample = x + step * 0.5;
                                let alpha = floor;
                                for (let i = 0; i < lobes.length; i++)
                                    alpha = Math.max(alpha, lobeAlpha(sample, lobes[i]));
                                ctx.fillStyle = Qt.rgba(1, 1, 1, alpha);
                                ctx.fillRect(x, 0, Math.min(step, w - x), h);
                            }
                        }
                    }
                }

                OpacityMask {
                    anchors.fill: parent
                    source: lit
                    maskSource: clusters
                    opacity: root.opacityPeak * root.breath * panel.strength
                }
            }
        }
    }
}
