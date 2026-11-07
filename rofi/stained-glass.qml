import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: panel
    readonly property string output: Quickshell.env("VOLUTA_SELECTOR_MONITOR")
    readonly property var palette: Quickshell.env("VOLUTA_SELECTOR_COLORS").split(" ")
    readonly property var targetScreen: Quickshell.screens.find(candidate => candidate.name === output) ?? null
    readonly property string assets: Quickshell.env("VOLUTA_SELECTOR_ASSETS")
    readonly property url aperture: Qt.resolvedUrl(assets + "/selector-aperture.png")
    readonly property int plateWidth: 1152
    readonly property int plateHeight: 1024

    screen: targetScreen
    visible: targetScreen !== null && targetScreen.width >= plateWidth && targetScreen.height >= plateHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "voluta-selector-glass"

    // Rofi owns the overlay input surface. A separate, input-transparent
    // overlay puts the ornament above its buttons while the glass stays on Top.
    PanelWindow {
        screen: panel.screen
        visible: panel.visible
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "voluta-selector-frame"

        Item {
            width: parent.width
            height: parent.height
            y: retable.y
            opacity: retable.opacity
            Image {
                anchors.centerIn: parent
                width: panel.plateWidth
                height: panel.plateHeight
                source: Qt.resolvedUrl(panel.assets + "/big-angel-box.png")
            }
        }
    }

    // Keep the blur veil fixed while the frame and its effects move.
    anchors { top: true; bottom: true; left: true; right: true }

    IpcHandler {
        target: "selector"
        function dismiss(): void {
            if (departure.running)
                return;
            entrance.stop();
            departure.start();
        }
    }

    ParallelAnimation {
        id: entrance
        NumberAnimation { target: retable; property: "y"; to: 0; duration: 190; easing.type: Easing.OutCubic }
        NumberAnimation { target: retable; property: "opacity"; to: 1; duration: 130; easing.type: Easing.OutQuad }
        NumberAnimation { target: vignette; property: "opacity"; to: 1; duration: 190; easing.type: Easing.OutQuad }
    }

    SequentialAnimation {
        id: departure
        ParallelAnimation {
            NumberAnimation {
                target: vignette
                property: "opacity"
                to: 0
                duration: 390
                easing.type: Easing.InOutQuad
            }
            SequentialAnimation {
                PauseAnimation { duration: 90 }
                ParallelAnimation {
                    NumberAnimation {
                        target: retable
                        property: "y"
                        to: panel.height
                        duration: 350
                        easing.type: Easing.InCubic
                    }
                    NumberAnimation {
                        target: retable
                        property: "opacity"
                        to: 0
                        duration: 350
                        easing.type: Easing.InQuad
                    }
                }
            }
        }
        ScriptAction { script: Qt.quit() }
    }

    Image {
        id: vignette
        anchors.fill: parent
        z: -2
        opacity: 0
        asynchronous: true
        source: Qt.resolvedUrl(panel.assets + "/launcher-vignette.svg")
        // The vignette is soft already; rasterize it at quarter size for a faster entrance.
        sourceSize.width: Math.ceil(width / 4)
        sourceSize.height: Math.ceil(height / 4)
    }

    Item {
        id: retable
        width: panel.width
        height: panel.height
        y: 130
        opacity: 0
        Component.onCompleted: entrance.start()

        Canvas {
            id: ignition
            anchors.centerIn: parent
            width: panel.plateWidth
            height: panel.plateHeight
            z: 1
            property var routes: []
            property double started: 0
            property bool finished: false
            Component.onCompleted: loadImage(panel.aperture)
            onImageLoaded: requestPaint()

            function edgePoint(pixels, cx, cy, angle) {
                const radians = angle * Math.PI / 180;
                const dx = Math.cos(radians), dy = Math.sin(radians);
                let distance = 0;
                for (; distance < Math.max(width, height); ++distance) {
                    const x = Math.round(cx + dx * distance);
                    const y = Math.round(cy + dy * distance);
                    if (x < 0 || x >= width || y < 0 || y >= height || pixels[(y * width + x) * 4 + 3] < 128)
                        break;
                }
                return [cx + dx * Math.max(0, distance - 5), cy + dy * Math.max(0, distance - 5), distance];
            }

            function route(pixels, cx, cy, first, top, direction) {
                const points = [];
                let corner = 0;
                for (let angle = first; angle !== top + direction; angle += direction) {
                    const point = edgePoint(pixels, cx, cy, angle);
                    if (points.length < 45 && (!points.length || point[2] > points[corner][2]))
                        corner = points.length;
                    points.push(point);
                }
                return points.slice(corner);
            }

            function trail(ctx, points, head, length, color, width, opacity) {
                const first = Math.max(0, head - length);
                const last = Math.min(points.length - 1, head);
                if (last <= first)
                    return;
                ctx.strokeStyle = color;
                ctx.lineWidth = width;
                ctx.globalAlpha = opacity;
                ctx.beginPath();
                ctx.moveTo(points[first][0], points[first][1]);
                for (let index = first + 1; index <= last; ++index)
                    ctx.lineTo(points[index][0], points[index][1]);
                ctx.stroke();
            }

            onPaint: {
                if (finished || !isImageLoaded(panel.aperture))
                    return;
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (!started) {
                    ctx.drawImage(panel.aperture, 0, 0);
                    const pixels = ctx.getImageData(0, 0, width, height).data;
                    const cx = Math.floor(width / 2), cy = Math.floor(height / 2);
                    routes = pixels[(cy * width + cx) * 4 + 3] >= 128
                        ? [route(pixels, cx, cy, 110, 270, 1), route(pixels, cx, cy, 70, -90, -1)] : [];
                    ctx.clearRect(0, 0, width, height);
                    // Strike the inner rim when the panel settles into place.
                    started = Date.now() + 180;
                }
                const elapsed = Date.now() - started;
                if (elapsed >= 450 || routes.length === 0) {
                    finished = true;
                    return;
                }
                const progress = Math.max(0, Math.min(1, elapsed / 390));
                const fade = Math.max(0, Math.min(1, elapsed / 45, (450 - elapsed) / 75));
                ctx.save();
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                for (const points of routes) {
                    const head = Math.round(progress * (points.length - 1));
                    trail(ctx, points, head, 22, Qt.lighter(panel.palette[1], 1.7), 14, fade * 0.65);
                    trail(ctx, points, head, 13, Qt.lighter(panel.palette[2], 1.55), 4, fade);
                }
                ctx.globalAlpha = 1;
                ctx.globalCompositeOperation = "destination-in";
                ctx.drawImage(panel.aperture, 0, 0);
                ctx.restore();
            }

            Timer {
                interval: 16
                repeat: true
                running: panel.visible && !ignition.finished
                onTriggered: ignition.requestPaint()
            }
        }

        Canvas {
            id: projection
            anchors.centerIn: parent
            width: panel.plateWidth
            height: panel.plateHeight
            opacity: 0.34
            readonly property double started: Date.now()
            readonly property int repeatWidth: 660
            Component.onCompleted: loadImage(panel.aperture)
            onImageLoaded: requestPaint()

            function tint(color, alpha, brightness) {
                const tone = Qt.lighter(color, brightness);
                return Qt.rgba(tone.r, tone.g, tone.b, alpha);
            }

            function beam(ctx, x, span, color, light) {
                const gradient = ctx.createLinearGradient(x, 0, x + span, 0);
                gradient.addColorStop(0, "transparent");
                gradient.addColorStop(0.22, tint(color, 0.24, 1.55));
                gradient.addColorStop(0.43, tint(color, 0.56, 1.7));
                gradient.addColorStop(0.58, tint(light, 0.36, 1.12));
                gradient.addColorStop(0.76, tint(color, 0.40, 1.55));
                gradient.addColorStop(1, "transparent");
                ctx.fillStyle = gradient;
                ctx.fillRect(x, -520, span, 1040);
            }

            // Broad facets suggest projected panes without outlining a second frame.
            function facet(ctx, x, y, span, color) {
                const gradient = ctx.createLinearGradient(x, y, x + span, y + 150);
                gradient.addColorStop(0, "transparent");
                gradient.addColorStop(0.42, tint(color, 0.22, 1.28));
                gradient.addColorStop(1, "transparent");
                ctx.fillStyle = gradient;
                ctx.beginPath();
                ctx.moveTo(x + span * 0.38, y);
                ctx.lineTo(x + span, y + 86);
                ctx.lineTo(x + span * 0.67, y + 218);
                ctx.lineTo(x, y + 132);
                ctx.closePath();
                ctx.fill();
            }

            onPaint: {
                if (!isImageLoaded(panel.aperture))
                    return;
                const ctx = getContext("2d");
                const [first, second, light] = panel.palette;
                const seconds = (Date.now() - started) / 1000;
                const offset = (seconds * 34 + 103) % repeatWidth;
                ctx.clearRect(0, 0, width, height);
                ctx.save();
                ctx.translate(width / 2, height / 2);
                ctx.rotate(-0.48);
                for (let period = -2; period <= 1; ++period) {
                    const x = period * repeatWidth + offset;
                    beam(ctx, x - 54, 274, first, light);
                    beam(ctx, x + 186, 265, second, light);
                    beam(ctx, x + 438, 160, light, first);
                    for (let row = -2; row <= 1; ++row) {
                        facet(ctx, x + 20, row * 226 - 48, 153, light);
                        facet(ctx, x + 250, row * 226 + 18, 157, first);
                    }
                }
                ctx.restore();
                ctx.save();
                ctx.globalCompositeOperation = "destination-in";
                ctx.drawImage(panel.aperture, 0, 0);
                ctx.restore();
            }

            Timer {
                interval: 40
                repeat: true
                running: panel.visible
                onTriggered: projection.requestPaint()
            }
        }
    }
}
