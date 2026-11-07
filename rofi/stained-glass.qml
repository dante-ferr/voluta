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
