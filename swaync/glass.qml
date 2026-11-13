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
    readonly property bool active: glass.active
    readonly property var targetScreen: Quickshell.screens.find(candidate => candidate.name === output) ?? null
    readonly property url aperture: Qt.resolvedUrl(assets + "/notification-aperture.png")
    screen: targetScreen
    visible: glass.surfaceMapped && targetScreen !== null
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

    function apply(output: string, colors: string, assets: string, reserved: string,
                   margin: string, width: string, height: string, version: string, token: string): bool {
        const next = Number(token);
        if (next < panel.request) return false;
        panel.request = next;
        const refresh = panel.artworkVersion !== version || panel.assets !== assets;
        panel.output = output;
        panel.palette = colors.split(" ");
        panel.assets = assets;
        panel.reservedTop = Number(reserved);
        panel.panelMargin = Number(margin);
        panel.plateWidth = Number(width);
        panel.plateHeight = Number(height);
        panel.artworkVersion = version;
        if (refresh) {
            // Same URL can hold a newly filtered frame. Clearing the source
            // is what makes Qt load the Wallust colors, as on the other menus.
            frameArtwork.source = "";
            frameArtwork.source = Qt.resolvedUrl(panel.assets + "/notification-angels-frame.png");
            glass.prepare(version);
        }
        return true;
    }

    Glass.MenuGlass {
        id: glass
        anchors.fill: parent
        motion: "compositor"
        surfaceWindow: panel
        targetScreen: panel.targetScreen
        backdropNamespace: "voluta-notification-backdrop"
        aperture: panel.aperture
        vignetteSource: Qt.resolvedUrl(panel.assets + "/launcher-vignette.svg")
        palette: panel.palette
        projectionParent: panel.contentItem
        projectionWidth: panel.plateWidth
        projectionHeight: panel.plateHeight
        projectionY: panel.panelMargin
        openState: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/voluta-notification.open"
    }

    // Same rectangle and same surface as the aperture, so the glass cannot drift
    // from the frame while Hyprland slides this layer.
    Image {
        id: frameArtwork
        x: (parent.width - panel.plateWidth) / 2
        y: panel.panelMargin
        width: panel.plateWidth
        height: panel.plateHeight
        z: 3
        cache: false
        asynchronous: false
        source: Qt.resolvedUrl(panel.assets + "/notification-angels-frame.png")
    }

    IpcHandler {
        target: "notification"
        function status(): string { return glass.status(); }
        function prepare(output: string, colors: string, assets: string, reserved: string,
                         margin: string, width: string, height: string, version: string, token: string): void {
            panel.apply(output, colors, assets, reserved, margin, width, height, version, token);
        }
        function showPanel(output: string, colors: string, assets: string, reserved: string,
                           margin: string, width: string, height: string, version: string, token: string): void {
            if (panel.apply(output, colors, assets, reserved, margin, width, height, version, token))
                glass.open();
        }
        function recolor(output: string, colors: string, assets: string, reserved: string,
                         margin: string, width: string, height: string, version: string, token: string): void {
            panel.apply(output, colors, assets, reserved, margin, width, height, version, token);
        }
        function dismiss(token: string): void {
            const next = Number(token);
            if (next < panel.request) return;
            panel.request = next;
            glass.close();
        }
    }
}
