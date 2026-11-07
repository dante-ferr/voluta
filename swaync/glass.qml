import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "effects" as Glass

PanelWindow {
    id: panel
    property string output: Quickshell.env("VOLUTA_NOTIFICATION_MONITOR")
    property var palette: Quickshell.env("VOLUTA_NOTIFICATION_COLORS").split(" ")
    property string assets: Quickshell.env("VOLUTA_NOTIFICATION_ASSETS")
    property int reservedTop: Number(Quickshell.env("VOLUTA_NOTIFICATION_RESERVED_TOP"))
    property int panelMargin: Number(Quickshell.env("VOLUTA_NOTIFICATION_MARGIN_TOP"))
    property int plateWidth: Number(Quickshell.env("VOLUTA_NOTIFICATION_WIDTH"))
    property int plateHeight: Number(Quickshell.env("VOLUTA_NOTIFICATION_HEIGHT"))
    property string artworkVersion: ""
    property double request: -1
    property bool active: false
    readonly property var targetScreen: Quickshell.screens.find(candidate => candidate.name === output) ?? null
    readonly property url aperture: Qt.resolvedUrl(assets + "/notification-aperture.png")
    screen: targetScreen
    visible: active && targetScreen !== null
    // Match SwayNC's full available-output layer geometry. Hyprland animates
    // both native surfaces together; only the aperture below paints pixels.
    anchors { top: true; bottom: true; left: true; right: true }
    margins.top: reservedTop
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "voluta-notification-glass"

    // Reuse the selector's full-output veil. It fades independently while
    // the bounded projection and native menu retain their shared slide.
    PanelWindow {
        screen: panel.targetScreen
        visible: panel.active && panel.targetScreen !== null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "voluta-notification-backdrop"

        Image {
            id: backdrop
            anchors.fill: parent
            cache: false
            source: Qt.resolvedUrl(panel.assets + "/launcher-vignette.svg")
            sourceSize.width: Math.ceil(width / 4)
            sourceSize.height: Math.ceil(height / 4)
        }
    }

    function apply(output: string, colors: string, assets: string, reserved: string,
                   margin: string, width: string, height: string, version: string, token: string): bool {
        const next = Number(token);
        if (next < panel.request) return false;
        panel.request = next;
        const refresh = panel.artworkVersion !== version || panel.assets !== assets;
        const previousAperture = panel.aperture;
        panel.output = output;
        panel.palette = colors.split(" ");
        panel.assets = assets;
        panel.reservedTop = Number(reserved);
        panel.panelMargin = Number(margin);
        panel.plateWidth = Number(width);
        panel.plateHeight = Number(height);
        panel.artworkVersion = version;
        if (refresh) {
            backdrop.source = "";
            backdrop.source = Qt.resolvedUrl(panel.assets + "/launcher-vignette.svg");
            projection.unloadImage(previousAperture);
            projection.ready = false;
            projection.loadImage(panel.aperture);
        }
        projection.requestPaint();
        return true;
    }

    Glass.StainedGlass {
        id: projection
        anchors.horizontalCenter: parent.horizontalCenter
        y: panel.panelMargin
        width: panel.plateWidth
        height: panel.plateHeight
        aperture: panel.aperture
        palette: panel.palette
        // GTK's persistent 50% dark backing attenuates this to selector's .34.
        opacity: 0.68
        animationRunning: panel.active && panel.visible
    }

    IpcHandler {
        target: "notification"
        function prepare(output: string, colors: string, assets: string, reserved: string,
                         margin: string, width: string, height: string, version: string, token: string): void {
            panel.apply(output, colors, assets, reserved, margin, width, height, version, token);
        }
        function showPanel(output: string, colors: string, assets: string, reserved: string,
                           margin: string, width: string, height: string, version: string, token: string): void {
            if (panel.apply(output, colors, assets, reserved, margin, width, height, version, token))
                panel.active = true;
        }
        function dismiss(token: string): void {
            const next = Number(token);
            if (next < panel.request) return;
            panel.request = next;
            panel.active = false;
        }
    }
}
