import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "effects" as Glass

PanelWindow {
    id: panel
    readonly property string output: Quickshell.env("VOLUTA_NOTIFICATION_MONITOR")
    readonly property var targetScreen: Quickshell.screens.find(candidate => candidate.name === output) ?? null
    screen: targetScreen
    visible: targetScreen !== null
    implicitWidth: 1056
    implicitHeight: 640
    anchors.top: true
    margins.top: Number(Quickshell.env("VOLUTA_NOTIFICATION_TOP"))
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "voluta-notification-glass"

    Glass.StainedGlass {
        id: projection
        anchors.fill: parent
        aperture: Qt.resolvedUrl(Quickshell.env("VOLUTA_NOTIFICATION_ASSETS") + "/notification-aperture.png")
        palette: Quickshell.env("VOLUTA_NOTIFICATION_COLORS").split(" ")
        // The permanent GTK backing above this layer is 50% dark palette glass.
        // Compensate for that attenuation to match the selector's 0.34 projection.
        opacity: 0
        animationRunning: panel.visible
        onReadyChanged: if (ready && !departure.running) entrance.start()
    }

    IpcHandler {
        target: "notification"
        function dismiss(): void {
            entrance.stop();
            if (!departure.running) departure.start();
        }
    }
    NumberAnimation {
        id: entrance
        target: projection
        property: "opacity"
        to: 0.68
        duration: 150
        easing.type: Easing.OutCubic
    }
    SequentialAnimation {
        id: departure
        NumberAnimation {
            target: projection
            property: "opacity"
            to: 0
            duration: 350
            easing.type: Easing.InOutQuad
        }
        ScriptAction { script: Qt.quit() }
    }
}
