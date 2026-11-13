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
    readonly property bool active: glass.active
    property string request: ""

    screen: targetScreen
    visible: targetScreen !== null && targetScreen.width >= plateWidth && targetScreen.height >= plateHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "voluta-selector-glass"

    readonly property bool entranceStarted: glass.entranceStarted
    function startWhenReady(): void { glass.startWhenReady(); }

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
            x: retable.x
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
        function status(): string { return glass.status(); }
        function openSelector(output: string, colors: string, assets: string, request: string, version: string): void {
            const refresh = panel.artworkVersion !== version || panel.assets !== assets;
            panel.output = output;
            panel.palette = colors.split(" ");
            panel.assets = assets;
            panel.artworkVersion = version;
            if (refresh) {
                // Wallpaper/frame publication can replace files at the same URL.
                frameArtwork.source = "";
                frameArtwork.source = Qt.resolvedUrl(assets + "/big-angel-box.png");
            }
            panel.request = request;
            glass.prepare(version);
            glass.open();
        }
        function dismiss(request: string): void {
            if (request !== panel.request)
                return;
            glass.close();
        }
    }

    Glass.MenuGlass {
        id: glass
        anchors.fill: parent
        surfaceWindow: panel
        targetScreen: panel.targetScreen
        aperture: panel.aperture
        vignetteSource: Qt.resolvedUrl(panel.assets + "/launcher-vignette.svg")
        plateGlass: Qt.resolvedUrl(panel.assets + "/selector-glass.png")
        palette: panel.palette
        projectionParent: retable
        projectionWidth: panel.plateWidth
        projectionHeight: panel.plateHeight
        externalReady: frameArtwork.status === Image.Ready
        openState: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/voluta-selector.open"
        initialVersion: panel.artworkVersion
    }

    Item {
        id: retable
        width: panel.width
        height: panel.height
        y: 130
        opacity: 0
    }
}
