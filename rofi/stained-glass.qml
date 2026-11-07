import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "effects" as Glass

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


        Glass.StainedGlass {
            id: projection
            anchors.centerIn: parent
            width: panel.plateWidth
            height: panel.plateHeight
            opacity: 0.34
            aperture: panel.aperture
            palette: panel.palette
            animationRunning: panel.visible
            onReadyChanged: panel.startWhenReady()
        }
    }
}
