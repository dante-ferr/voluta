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

    property bool entranceStarted: false
    function startWhenReady(): void {
        if (entranceStarted || frameArtwork.status !== Image.Ready ||
            vignette.status !== Image.Ready || !projection.ready)
            return;
        entranceStarted = true;
        // Establish the blur veil before moving the ornament into view.
        vignette.opacity = 1;
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
        function dismiss(): void {
            if (departure.running)
                return;
            entrance.stop();
            departure.start();
        }
    }

    ParallelAnimation {
        id: entrance
        NumberAnimation { target: retable; property: "y"; to: 0; duration: 150; easing.type: Easing.OutCubic }
        NumberAnimation { target: retable; property: "opacity"; to: 1; duration: 100; easing.type: Easing.OutQuad }
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
        asynchronous: false
        onStatusChanged: panel.startWhenReady()
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


        Canvas {
            id: projection
            anchors.centerIn: parent
            width: panel.plateWidth
            height: panel.plateHeight
            opacity: 0.34
            property bool ready: false
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
                if (!ready) {
                    ready = true;
                    panel.startWhenReady();
                }
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
