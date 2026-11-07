import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "effects" as Glass

PanelWindow {
    id: panel
    property string output: Quickshell.env("VOLUTA_SELECTOR_MONITOR")
    property var palette: Quickshell.env("VOLUTA_SELECTOR_COLORS").split(" ")
    readonly property var targetScreen: Quickshell.screens.find(candidate => candidate.name === output) ?? null
    property string assets: Quickshell.env("VOLUTA_SELECTOR_ASSETS")
    readonly property url aperture: Qt.resolvedUrl(assets + "/selector-aperture.png")
    readonly property int plateWidth: 1152
    readonly property int plateHeight: 1024

    property string artworkVersion: Quickshell.env("VOLUTA_SELECTOR_VERSION")
    property bool active: false
    property string request: ""

    screen: targetScreen
    visible: targetScreen !== null && targetScreen.width >= plateWidth && targetScreen.height >= plateHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "voluta-selector-glass"

    property bool entranceStarted: false
    function startWhenReady(): void {
        // The blur veil must be ready; the animated projection can paint while
        // the frame enters instead of holding up the whole entrance.
        if (!active || startDelay.running || entranceStarted || frameArtwork.status !== Image.Ready ||
            vignette.status !== Image.Ready)
            return;
        entranceStarted = true;
        // Establish the blur veil before moving the ornament into view.
        vignette.opacity = 1;
        // Replay the cached inner-rim routes with the entrance, without a late flash.
        ignition.started = Date.now();
        ignition.finished = false;
        ignition.requestPaint();
        entrance.start();
    }

    // Hyprland draws closing layer snapshots after live Overlay surfaces.
    // A non-grabbing popup keeps the ornament above Rofi throughout its exit,
    // while its parent glass surface stays below the buttons on Top.
    PopupWindow {
        anchor.window: panel
        anchor.rect.x: 0
        anchor.rect.y: 0
        implicitWidth: panel.targetScreen?.width ?? 1
        implicitHeight: panel.targetScreen?.height ?? 1
        visible: panel.visible && panel.width > 0 && panel.height > 0
        color: "transparent"
        grabFocus: false
        mask: Region {}

        Item {
            width: parent.width
            height: parent.height
            y: retable.y
            opacity: retable.opacity
            Image {
                id: frameArtwork
                cache: false
                onStatusChanged: panel.startWhenReady()
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
        function openSelector(output: string, colors: string, assets: string, request: string, version: string): void {
            panel.active = false;
            departure.stop();
            entrance.stop();
            const refresh = panel.artworkVersion !== version || panel.assets !== assets;
            panel.output = output;
            panel.palette = colors.split(" ");
            panel.assets = assets;
            panel.artworkVersion = version;
            if (refresh) {
                // Wallpaper/frame publication can replace files at the same URL.
                frameArtwork.source = "";
                frameArtwork.source = Qt.resolvedUrl(assets + "/big-angel-box.png");
                vignette.source = "";
                vignette.source = Qt.resolvedUrl(assets + "/launcher-vignette.svg");
                projection.unloadImage(panel.aperture);
                projection.loadImage(panel.aperture);
                ignition.prepared = false;
                ignition.unloadImage(panel.aperture);
                ignition.loadImage(panel.aperture);
            }
            panel.request = request;
            panel.entranceStarted = false;
            retable.y = 130;
            retable.opacity = 0;
            vignette.opacity = 0;
            // Let the native menu lead by a small, consistent stagger.
            startDelay.restart();
            panel.active = true;
        }
        function dismiss(request: string): void {
            if (request !== panel.request || departure.running)
                return;
            startDelay.stop();
            ignition.finished = true;
            ignition.requestPaint();
            entrance.stop();
            departure.start();
        }
    }

    Timer {
        id: startDelay
        interval: 20
        onTriggered: panel.startWhenReady()
    }

    ParallelAnimation {
        id: entrance
        NumberAnimation { target: retable; property: "y"; to: 0; duration: 135; easing.type: Easing.OutCubic }
        NumberAnimation { target: retable; property: "opacity"; to: 1; duration: 85; easing.type: Easing.OutQuad }
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
        ScriptAction { script: panel.active = false }
    }

    Image {
        id: vignette
        cache: false
        anchors.fill: parent
        z: -2
        opacity: 0
        asynchronous: false
        onStatusChanged: panel.startWhenReady()
        source: Qt.resolvedUrl(panel.assets + "/launcher-vignette.svg")
        // The vignette is soft already; rasterize it at quarter size for a faster entrance.
        sourceSize.width: Math.ceil((panel.targetScreen?.width ?? 1) / 4)
        sourceSize.height: Math.ceil((panel.targetScreen?.height ?? 1) / 4)
    }

    Item {
        id: retable
        width: panel.width
        height: panel.height
        y: 130
        opacity: 0


        Canvas {
            id: ignition
            anchors.centerIn: parent
            width: panel.plateWidth
            height: panel.plateHeight
            z: 1
            property var routes: []
            property double started: 0
            property bool finished: true
            property bool prepared: false
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
                if (!isImageLoaded(panel.aperture))
                    return;
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (!prepared) {
                    ctx.drawImage(panel.aperture, 0, 0);
                    const pixels = ctx.getImageData(0, 0, width, height).data;
                    const cx = Math.floor(width / 2), cy = Math.floor(height / 2);
                    routes = pixels[(cy * width + cx) * 4 + 3] >= 128
                        ? [route(pixels, cx, cy, 110, 270, 1), route(pixels, cx, cy, 70, -90, -1)] : [];
                    ctx.clearRect(0, 0, width, height);
                    prepared = true;
                }
                if (finished || !panel.active || !panel.entranceStarted)
                    return;
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
                running: panel.active && panel.entranceStarted && !ignition.finished
                onTriggered: ignition.requestPaint()
            }
        }

        Glass.StainedGlass {
            id: projection
            anchors.centerIn: parent
            width: panel.plateWidth
            height: panel.plateHeight
            opacity: 0.34
            aperture: panel.aperture
            palette: panel.palette
            animationRunning: panel.active && panel.entranceStarted && panel.visible
            onReadyChanged: panel.startWhenReady()
        }
    }
}
