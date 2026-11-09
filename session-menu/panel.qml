import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "effects" as Glass

PanelWindow {
    id: panel
    property string output: Quickshell.env("VOLUTA_SESSION_MONITOR")
    property var palette: Quickshell.env("VOLUTA_SESSION_COLORS").split(" ")
    property string assets: Quickshell.env("VOLUTA_SESSION_ASSETS")
    readonly property url aperture: Qt.resolvedUrl(assets + "/session-aperture.png")
    readonly property int plateWidth: Number(Quickshell.env("VOLUTA_SESSION_WIDTH") || "624")
    readonly property int plateHeight: Number(Quickshell.env("VOLUTA_SESSION_HEIGHT") || "1040")
    property int gridLeft: Number(Quickshell.env("VOLUTA_GRID_LEFT") || "0")
    property int gridTop: Number(Quickshell.env("VOLUTA_GRID_TOP") || "0")
    property int gridRight: Number(Quickshell.env("VOLUTA_GRID_RIGHT") || "0")
    property int gridBottom: Number(Quickshell.env("VOLUTA_GRID_BOTTOM") || "0")
    readonly property int framePadLeft: Number(Quickshell.env("VOLUTA_SESSION_PAD_LEFT") || "0")
    readonly property int contentLeft: Number(Quickshell.env("VOLUTA_SESSION_INSET_LEFT") || Math.round(plateWidth * 0.2))
    readonly property int contentTop: Number(Quickshell.env("VOLUTA_SESSION_INSET_TOP") || Math.round(plateHeight * 0.28))
    readonly property int contentWidth: Number(Quickshell.env("VOLUTA_SESSION_INSET_WIDTH") || Math.round(plateWidth * 0.55))
    readonly property int contentHeight: Number(Quickshell.env("VOLUTA_SESSION_INSET_HEIGHT") || Math.round(plateHeight * 0.55))
    property string artworkVersion: Quickshell.env("VOLUTA_SESSION_VERSION")
    property string pending: ""
    property bool night: false
    property real volume: 0
    property bool muted: false
    property string sink: ""
    property string uptime: ""
    property var battery: null
    property var monitors: []
    property date now: new Date()
    readonly property var targetScreen: Quickshell.screens.find(candidate => candidate.name === output) ?? null
    readonly property int plateX: panel.gridLeft - panel.framePadLeft
    readonly property int plateY: {
        const height = targetScreen?.height ?? plateHeight;
        const room = height - gridTop - gridBottom - plateHeight;
        const centered = gridTop + Math.max(0, Math.floor(room / 2));
        return Math.max(0, Math.min(centered, Math.max(0, height - plateHeight)));
    }
    readonly property color ink: panel.palette[2] || "#fdeed5"
    readonly property color accent: panel.palette[0] || "#a46b54"
    readonly property string home: Quickshell.env("HOME")

    component Action: MouseArea {
        id: action
        property string icon
        property bool armed: false
        property bool active: false
        width: 44
        height: 44
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        Rectangle {
            anchors.fill: parent
            radius: 2
            color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, (action.armed || action.active) ? 0.55 : (action.containsMouse ? 0.28 : 0.12))
        }
        Text {
            anchors.centerIn: parent
            color: panel.ink
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 20
            text: action.armed ? "\u{F012C}" : action.icon
        }
    }

    screen: targetScreen
    visible: targetScreen !== null && targetScreen.width >= plateWidth && targetScreen.height >= plateHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: glass.showing ? panel.contentItem : null }
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: glass.showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "voluta-session-glass"
    anchors { top: true; bottom: true; left: true; right: true }

    function followFocus(): void {
        const monitor = Hyprland.focusedMonitor;
        if (monitor === null || monitor.name === "")
            return;
        const candidate = Quickshell.screens.find(item => item.name === monitor.name) ?? null;
        if (candidate === null || candidate.width < panel.plateWidth || candidate.height < panel.plateHeight)
            return;
        panel.output = monitor.name;
        panel.refreshGrid(monitor.name);
    }

    function refreshGrid(name: string): void {
        const bin = Quickshell.env("VOLUTA_WINDOW_GRID");
        if (bin === "" || name === "")
            return;
        const python = Quickshell.env("VOLUTA_PYTHON") || "python3";
        gridQuery.command = [python, bin, name];
        gridQuery.running = false;
        gridQuery.running = true;
    }

    function applyGrid(text: string): void {
        try {
            const edge = JSON.parse(text).insets;
            panel.gridLeft = Number(edge.left);
            panel.gridTop = Number(edge.top);
            panel.gridRight = Number(edge.right);
            panel.gridBottom = Number(edge.bottom);
        } catch (error) {
        }
    }

    function applyStatus(text: string): void {
        try {
            const data = JSON.parse(text);
            panel.night = !!data.night;
            panel.volume = Number(data.volume) || 0;
            panel.muted = !!data.muted;
            panel.sink = data.sink || "";
            panel.uptime = data.uptime || "";
            panel.battery = data.battery || null;
            panel.monitors = data.monitors || [];
        } catch (error) {
        }
    }

    // Same publication the selector applies in openSelector: accents plus the
    // recolored frame and glass plate. An unchanged stamp leaves the images.
    function applyPublication(colors: string, assets: string, version: string): void {
        const refresh = version !== "" && (panel.artworkVersion !== version || panel.assets !== assets);
        if (colors !== "")
            panel.palette = colors.split(" ");
        if (assets !== "")
            panel.assets = assets;
        if (version !== "")
            panel.artworkVersion = version;
        if (refresh) {
            frameArtwork.source = "";
            frameArtwork.source = Qt.resolvedUrl(panel.assets + "/session-frame.png");
            glass.prepare(version);
        }
    }

    function refreshStatus(): void {
        const python = Quickshell.env("VOLUTA_PYTHON") || "python3";
        const status = Quickshell.env("VOLUTA_SESSION_STATUS");
        if (status === "")
            return;
        statusQuery.command = [python, status];
        statusQuery.running = false;
        statusQuery.running = true;
    }

    function run(command: string): void {
        panel.pending = "";
        Quickshell.execDetached(["/bin/sh", "-c", command]);
        glass.close();
    }

    function confirm(name: string, command: string): void {
        if (panel.pending === name)
            panel.run(command);
        else
            panel.pending = name;
    }

    function shellQuote(value: string): string {
        return "'" + value.replace(/'/g, "'\\''") + "'";
    }

    Shortcut { enabled: glass.showing; sequence: "Escape"; onActivated: glass.close() }

    MouseArea {
        anchors.fill: parent
        enabled: glass.showing
        focus: glass.showing
        Keys.onEscapePressed: (event) => { glass.close(); event.accepted = true; }
        onClicked: glass.close()
    }

    Process {
        id: gridQuery
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: panel.applyGrid(this.text)
        }
    }

    Process {
        id: statusQuery
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: panel.applyStatus(this.text)
        }
    }

    Timer {
        interval: 1000
        running: glass.showing
        repeat: true
        onTriggered: {
            panel.now = new Date();
            panel.refreshStatus();
        }
    }

    Connections {
        target: glass
        function onEntranceStarting(): void {
            panel.now = new Date();
            panel.followFocus();
            panel.refreshStatus();
        }
    }

    Connections {
        target: Hyprland
        function onFocusedMonitorChanged(): void {
            if (glass.showing)
                panel.followFocus();
        }
    }

    Component.onCompleted: panel.followFocus()

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
                x: panel.plateX
                y: panel.plateY
                width: panel.plateWidth
                height: panel.plateHeight
                source: Qt.resolvedUrl(panel.assets + "/session-frame.png")
            }
        }
    }

    IpcHandler {
        target: "session"
        function status(): string { return glass.status(); }
        function toggle(colors: string, assets: string, version: string): void {
            if (glass.active) {
                glass.close();
                return;
            }
            panel.applyPublication(colors, assets, version);
            panel.pending = "";
            panel.followFocus();
            panel.refreshStatus();
            glass.prepare(panel.artworkVersion);
            glass.open();
        }
        function recolor(colors: string, assets: string, version: string): void {
            panel.applyPublication(colors, assets, version);
        }
        function dismiss(token: string): void {
            panel.pending = "";
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
        palette: panel.palette
        projectionParent: retable
        projectionWidth: panel.plateWidth
        projectionHeight: panel.plateHeight
        projectionX: panel.plateX
        projectionY: panel.plateY
        projectionOpacity: 0.30
        itemAxis: "x"
        itemEnterFrom: -(panel.plateWidth + panel.gridLeft)
        itemLeaveTo: -(panel.plateWidth + panel.gridLeft)
        externalReady: frameArtwork.status === Image.Ready
        initialVersion: panel.artworkVersion
    }

    Item {
        id: retable
        width: panel.width
        height: panel.height
        x: -(panel.plateWidth + panel.gridLeft)
        y: 0
        opacity: 0

        MouseArea {
            x: panel.plateX
            y: panel.plateY
            width: panel.plateWidth
            height: panel.plateHeight
            onClicked: {}
        }

        Item {
            x: panel.plateX + panel.contentLeft
            y: panel.plateY + panel.contentTop
            width: panel.contentWidth
            height: panel.contentHeight
            z: 2

            Column {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 4

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    color: panel.ink
                    font.family: "JetBrains Mono"
                    font.pixelSize: 42
                    text: Qt.formatDateTime(panel.now, "HH:mm")
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    color: panel.ink
                    opacity: 0.72
                    font.family: "JetBrains Mono"
                    font.pixelSize: 13
                    text: Qt.formatDate(panel.now, "dddd, d MMMM")
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    color: panel.ink
                    opacity: 0.5
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    text: {
                        const parts = [];
                        if (panel.uptime !== "")
                            parts.push(panel.uptime);
                        if (panel.battery)
                            parts.push(panel.battery.percent + "%");
                        return parts.join("  ·  ");
                    }
                }
            }

            Column {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 8

                Text {
                    width: parent.width
                    color: panel.ink
                    opacity: 0.7
                    elide: Text.ElideRight
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    text: panel.muted ? "Muted" : (panel.sink || "No sink")
                }

                MouseArea {
                    width: parent.width
                    height: 18
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (event) => {
                        const level = Math.max(0, Math.min(1.5, (event.x / width) * 1.5)).toFixed(2);
                        Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", level]);
                        panel.refreshStatus();
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 3
                        radius: 1
                        color: Qt.rgba(panel.ink.r, panel.ink.g, panel.ink.b, 0.22)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * Math.min(1, panel.volume / 1.5)
                        height: 3
                        radius: 1
                        color: panel.accent
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: panel.monitors
                        delegate: MouseArea {
                            required property var modelData
                            width: label.implicitWidth + 16
                            height: 26
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "focusmonitor", modelData.name])
                            Rectangle {
                                anchors.fill: parent
                                radius: 2
                                color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, modelData.focused ? 0.45 : 0.16)
                            }
                            Text {
                                id: label
                                anchors.centerIn: parent
                                color: panel.ink
                                font.family: "JetBrains Mono"
                                font.pixelSize: 11
                                text: modelData.name
                            }
                        }
                    }
                }

                Item { width: 1; height: 18 }

                MouseArea {
                    id: nightLight
                    width: parent.width
                    height: 44
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["/bin/sh", "-c",
                            "if pgrep -x hyprsunset >/dev/null 2>&1; then pkill -x hyprsunset; else hyprsunset -t 3000 >/dev/null 2>&1 & fi"]);
                        panel.refreshStatus();
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, panel.night ? 0.55 : (nightLight.containsMouse ? 0.28 : 0.12))
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: panel.ink
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 20
                        text: "\u{F0594}"
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 48
                        anchors.verticalCenter: parent.verticalCenter
                        color: panel.ink
                        font.family: "JetBrains Mono"
                        font.pixelSize: 13
                        text: "Night light"
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: panel.ink
                        opacity: panel.night ? 1 : 0.55
                        font.family: "JetBrains Mono"
                        font.pixelSize: 12
                        text: panel.night ? "On" : "Off"
                    }
                }

                Item { width: 1; height: 18 }

                Row {
                    width: parent.width
                    spacing: Math.max(8, (width - 220) / 4)

                    Action {
                        icon: "\u{F033E}"
                        onClicked: panel.run("/bin/sh " + panel.shellQuote(panel.home + "/.config/hypr/scripts/LockScreen.sh"))
                    }
                    Action {
                        icon: "\u{F0904}"
                        armed: panel.pending === "sleep"
                        onClicked: panel.confirm("sleep", "systemctl suspend")
                    }
                    Action {
                        icon: "\u{F0343}"
                        armed: panel.pending === "logout"
                        onClicked: panel.confirm("logout",
                            "python3 " + panel.shellQuote(panel.home + "/.config/hypr/scripts/session_manager.py") +
                            " prepare-shutdown; hyprctl dispatch 'hl.dsp.exit()' || uwsm stop || loginctl terminate-session self")
                    }
                    Action {
                        icon: "\u{F0709}"
                        armed: panel.pending === "reboot"
                        onClicked: panel.confirm("reboot",
                            "python3 " + panel.shellQuote(panel.home + "/.config/hypr/scripts/session_manager.py") +
                            " prepare-shutdown; systemctl reboot")
                    }
                    Action {
                        icon: "\u{F0425}"
                        armed: panel.pending === "power"
                        onClicked: panel.confirm("power",
                            "python3 " + panel.shellQuote(panel.home + "/.config/hypr/scripts/session_manager.py") +
                            " prepare-shutdown; systemctl poweroff")
                    }
                }
            }
        }
    }
}
