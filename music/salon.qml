import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "effects" as Glass

PanelWindow {
    id: panel
    property string output: Quickshell.env("VOLUTA_MUSIC_MONITOR")
    property var palette: Quickshell.env("VOLUTA_MUSIC_COLORS").split(" ")
    property string assets: Quickshell.env("VOLUTA_MUSIC_ASSETS")
    readonly property url aperture: Qt.resolvedUrl(assets + "/music-aperture.png")
    readonly property int plateWidth: Number(Quickshell.env("VOLUTA_MUSIC_WIDTH") || "624")
    readonly property int plateHeight: Number(Quickshell.env("VOLUTA_MUSIC_HEIGHT") || "1040")
    property int gridLeft: Number(Quickshell.env("VOLUTA_GRID_LEFT") || "0")
    property int gridTop: Number(Quickshell.env("VOLUTA_GRID_TOP") || "0")
    property int gridRight: Number(Quickshell.env("VOLUTA_GRID_RIGHT") || "0")
    property int gridBottom: Number(Quickshell.env("VOLUTA_GRID_BOTTOM") || "0")
    readonly property int framePadRight: Number(Quickshell.env("VOLUTA_MUSIC_PAD_RIGHT") || "0")
    readonly property int contentLeft: Number(Quickshell.env("VOLUTA_MUSIC_INSET_LEFT") || Math.round(plateWidth * 0.26))
    readonly property int contentTop: Number(Quickshell.env("VOLUTA_MUSIC_INSET_TOP") || Math.round(plateHeight * 0.27))
    readonly property int contentWidth: Number(Quickshell.env("VOLUTA_MUSIC_INSET_WIDTH") || Math.round(plateWidth * 0.58))
    readonly property int contentHeight: Number(Quickshell.env("VOLUTA_MUSIC_INSET_HEIGHT") || Math.round(plateHeight * 0.58))
    readonly property string playerFormat: "{{status}}|{{mpris:artUrl}}|{{artist}}|{{title}}|{{album}}|{{position}}|{{mpris:length}}|{{volume}}|{{loop}}|{{shuffle}}|{{playerName}}"
    property string artworkVersion: Quickshell.env("VOLUTA_MUSIC_VERSION")
    property string request: ""
    property url poster: ""
    property url shownPoster: ""
    property string trackTitle: ""
    property string trackArtist: ""
    property string trackAlbum: ""
    property string playerName: ""
    property bool playing: false
    property bool shuffled: false
    property string loopMode: "None"
    property real position: 0
    property real duration: 0
    property real volume: 1
    readonly property var targetScreen: Quickshell.screens.find(candidate => candidate.name === output) ?? null
    readonly property int plateX: Math.max(0, (targetScreen?.width ?? plateWidth) - plateWidth - gridRight + framePadRight)
    readonly property int plateY: {
        const height = targetScreen?.height ?? plateHeight;
        const room = height - gridTop - gridBottom - plateHeight;
        const centered = gridTop + Math.max(0, Math.floor(room / 2));
        return Math.max(0, Math.min(centered, Math.max(0, height - plateHeight)));
    }
    readonly property color ink: panel.palette[2] || "#fdeed5"
    readonly property color accent: panel.palette[0] || "#a46b54"

    screen: targetScreen
    visible: targetScreen !== null && targetScreen.width >= plateWidth + gridRight - framePadRight &&
             targetScreen.height >= plateHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: glass.showing ? panel.contentItem : null }
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: glass.showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "voluta-music-glass"
    anchors { top: true; bottom: true; left: true; right: true }

    readonly property bool entranceStarted: glass.entranceStarted
    function startWhenReady(): void { glass.startWhenReady(); }

    function seconds(value): real {
        const amount = Number(value);
        if (!isFinite(amount) || amount < 0)
            return 0;
        return amount > 10000 ? amount / 1000000 : amount;
    }

    function clock(value): string {
        const total = Math.max(0, Math.floor(seconds(value)));
        const minutes = Math.floor(total / 60);
        const rest = total % 60;
        return minutes + ":" + (rest < 10 ? "0" : "") + rest;
    }

    function followFocus(): void {
        const monitor = Hyprland.focusedMonitor;
        if (monitor === null || monitor.name === "")
            return;
        const candidate = Quickshell.screens.find(item => item.name === monitor.name) ?? null;
        if (candidate === null)
            return;
        if (candidate.width < panel.plateWidth + panel.gridRight - panel.framePadRight || candidate.height < panel.plateHeight)
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

    function clearPlayback(): void {
        panel.poster = "";
        panel.shownPoster = "";
        panel.trackTitle = "";
        panel.trackArtist = "";
        panel.trackAlbum = "";
        panel.playerName = "";
        panel.playing = false;
        panel.shuffled = false;
        panel.loopMode = "None";
        panel.position = 0;
        panel.duration = 0;
    }

    function applyPlayback(data): void {
        if (!data || (data.status !== "Playing" && data.status !== "Paused" && data.title === "" && data.artist === "")) {
            panel.clearPlayback();
            return;
        }
        const raw = data.art || "";
        const art = raw === "" ? "" : (raw.indexOf("://") >= 0 ? raw : "file://" + raw);
        const sameTrack = (data.title || "") === panel.trackTitle && (data.artist || "") === panel.trackArtist;
        const cached = String(panel.shownPoster).indexOf("/voluta-music/") >= 0;
        const unstable = art.indexOf("/tmp/") >= 0;
        if (!(sameTrack && cached && unstable) && art !== String(panel.poster))
            panel.poster = art;
        if (!sameTrack && art === "")
            panel.shownPoster = "";
        panel.trackTitle = data.title || "";
        panel.trackArtist = data.artist || "";
        panel.trackAlbum = data.album || "";
        panel.playerName = data.player || "";
        panel.playing = data.status === "Playing";
        panel.shuffled = data.shuffle === "On" || data.shuffle === "true";
        panel.loopMode = data.loop || "None";
        panel.position = seconds(data.position);
        panel.duration = seconds(data.length);
        const volume = Number(data.volume);
        panel.volume = isFinite(volume) ? Math.max(0, Math.min(1, volume)) : panel.volume;
    }

    function applyLine(text): void {
        const parts = (text || "").trim().split("|");
        while (parts.length < 11)
            parts.push("");
        panel.applyPlayback({
            status: parts[0], art: parts[1], artist: parts[2], title: parts[3], album: parts[4],
            position: parts[5], length: parts[6], volume: parts[7], loop: parts[8],
            shuffle: parts[9], player: parts[10]
        });
    }

    function refreshPlayer(): void {
        snapshot.running = false;
        snapshot.running = true;
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
            frameArtwork.source = Qt.resolvedUrl(panel.assets + "/music-frame.png");
            glass.prepare(version);
        }
    }

    function issue(args): void {
        Quickshell.execDetached(["playerctl"].concat(args));
        followUp.restart();
    }

    Shortcut { enabled: glass.showing; sequence: "Escape"; onActivated: glass.close() }
    Shortcut { enabled: glass.showing; sequence: "Space"; onActivated: panel.issue(["play-pause"]) }
    Shortcut { enabled: glass.showing; sequence: "Left"; onActivated: panel.issue(["previous"]) }
    Shortcut { enabled: glass.showing; sequence: "Right"; onActivated: panel.issue(["next"]) }
    Shortcut { enabled: glass.showing; sequence: "Up"; onActivated: panel.issue(["volume", "0.05+"]) }
    Shortcut { enabled: glass.showing; sequence: "Down"; onActivated: panel.issue(["volume", "0.05-"]) }

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
        id: snapshot
        command: ["playerctl", "metadata", "--format", panel.playerFormat]
        stdout: StdioCollector {
            id: snapOut
            waitForEnd: true
            onStreamFinished: {
                const text = this.text.trim();
                if (text === "")
                    panel.clearPlayback();
                else
                    panel.applyLine(text);
            }
        }
        onExited: (code) => {
            if (code !== 0 && snapOut.text.trim() === "")
                panel.clearPlayback();
        }
    }

    Timer {
        id: followUp
        interval: 180
        onTriggered: panel.refreshPlayer()
    }

    Timer {
        interval: 1000
        repeat: true
        running: glass.showing
        onTriggered: panel.refreshPlayer()
    }

    Connections {
        target: glass
        function onEntranceStarting(): void {
            panel.followFocus();
            panel.refreshPlayer();
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
                onStatusChanged: panel.startWhenReady()
                x: panel.plateX
                y: panel.plateY
                width: panel.plateWidth
                height: panel.plateHeight
                source: Qt.resolvedUrl(panel.assets + "/music-frame.png")
            }
        }
    }

    IpcHandler {
        target: "music"
        function status(): string { return glass.status(); }
        function toggle(colors: string, assets: string, version: string): void {
            if (glass.active) {
                glass.close();
                return;
            }
            panel.applyPublication(colors, assets, version);
            panel.followFocus();
            panel.refreshPlayer();
            glass.prepare(panel.artworkVersion);
            glass.open();
        }
        function recolor(colors: string, assets: string, version: string): void {
            panel.applyPublication(colors, assets, version);
        }
        function openSalon(output: string, colors: string, assets: string, request: string, version: string): void {
            panel.output = output;
            panel.applyPublication(colors, assets, version);
            panel.request = request;
            panel.followFocus();
            panel.refreshPlayer();
            glass.prepare(version);
            glass.open();
        }
        function dismiss(request: string): void {
            if (request !== "" && request !== panel.request)
                return;
            glass.close();
        }
        function playback(payload: string): void {
            try {
                panel.applyPlayback(JSON.parse(payload));
            } catch (error) {
            }
        }
        function nowPlaying(art: string, title: string, artist: string, album: string, status: string): void {
            panel.applyPlayback({
                art: art, title: title, artist: artist, album: album, status: status,
                position: panel.position, length: panel.duration, volume: panel.volume,
                loop: panel.loopMode, shuffle: panel.shuffled ? "On" : "Off", player: panel.playerName
            });
        }
        function bars(values: string): void {
            const next = [];
            for (const part of values.split(" ")) {
                if (part !== "")
                    next.push(Number(part));
            }
            spectrum.levels = next;
        }
    }

    Glass.MenuGlass {
        id: glass
        anchors.fill: parent
        surfaceWindow: panel
        targetScreen: panel.targetScreen
        aperture: panel.aperture
        vignetteSource: Qt.resolvedUrl(panel.assets + "/launcher-vignette.svg")
        plateGlass: Qt.resolvedUrl(panel.assets + "/music-glass.png")
        palette: panel.palette
        projectionParent: retable
        projectionWidth: panel.plateWidth
        projectionHeight: panel.plateHeight
        projectionX: panel.plateX
        projectionY: panel.plateY
        projectionOpacity: 0.30
        itemAxis: "x"
        itemEnterFrom: panel.plateWidth + panel.gridRight
        externalReady: frameArtwork.status === Image.Ready
        initialVersion: panel.artworkVersion
    }

    Item {
        id: retable
        width: panel.width
        height: panel.height
        x: panel.plateWidth + panel.gridRight
        y: 0
        opacity: 0

        MouseArea {
            x: panel.plateX
            y: panel.plateY
            width: panel.plateWidth
            height: panel.plateHeight
            enabled: glass.showing
            onClicked: {}
        }

        Item {
            id: content
            x: panel.plateX + panel.contentLeft
            y: panel.plateY + panel.contentTop
            width: Math.max(64, panel.contentWidth)
            height: Math.max(64, panel.contentHeight)
            z: 2

            readonly property int cover: Math.min(width, Math.round(height * 0.36))
            readonly property int bars: Math.max(52, Math.round(height * 0.13))

            Rectangle {
                id: coverWell
                anchors.horizontalCenter: parent.horizontalCenter
                width: content.cover
                height: content.cover
                radius: 8
                color: Qt.rgba(0, 0, 0, 0.42)
                border.width: 1
                border.color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.55)

                Image {
                    id: coverLoader
                    anchors.fill: parent
                    anchors.margins: 4
                    visible: false
                    cache: true
                    asynchronous: false
                    smooth: true
                    mipmap: false
                    fillMode: Image.PreserveAspectFit
                    source: panel.poster
                    onStatusChanged: {
                        if (status === Image.Ready)
                            panel.shownPoster = source;
                    }
                }

                Image {
                    id: coverArt
                    anchors.fill: parent
                    anchors.margins: 4
                    cache: true
                    asynchronous: false
                    smooth: true
                    mipmap: false
                    fillMode: Image.PreserveAspectFit
                    source: panel.shownPoster
                    visible: status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: !coverArt.visible && coverLoader.status === Image.Error
                    width: parent.width * 0.8
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: panel.ink
                    opacity: 0.55
                    font.family: "JetBrains Mono"
                    font.pixelSize: 13
                    text: "No artwork"
                }
            }

            Text {
                id: artistLabel
                anchors.top: coverWell.bottom
                anchors.topMargin: 10
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
                color: panel.ink
                opacity: 0.78
                font.family: "JetBrains Mono"
                font.pixelSize: 12
                text: panel.trackArtist
            }

            Text {
                id: titleLabel
                anchors.top: artistLabel.bottom
                anchors.topMargin: 3
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
                color: panel.ink
                font.family: "JetBrains Mono"
                font.pixelSize: 16
                font.bold: true
                text: panel.trackTitle === "" ? "Nothing playing" : panel.trackTitle
            }

            Text {
                id: statusLabel
                anchors.top: titleLabel.bottom
                anchors.topMargin: 4
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: panel.ink
                opacity: 0.7
                font.family: "JetBrains Mono"
                font.pixelSize: 11
                text: {
                    if (panel.trackTitle === "")
                        return "";
                    const state = panel.playing ? "Playing" : "Paused";
                    const album = panel.trackAlbum === "" ? "" : " · " + panel.trackAlbum;
                    const name = panel.playerName === "" ? "" : " · " + panel.playerName;
                    return state + album + name;
                }
            }

            Item {
                id: seek
                anchors.top: statusLabel.bottom
                anchors.topMargin: 10
                width: parent.width
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    color: panel.ink
                    opacity: 0.7
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    text: panel.clock(panel.position)
                }
                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    color: panel.ink
                    opacity: 0.7
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    text: panel.clock(panel.duration)
                }
                MouseArea {
                    id: seekHit
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 16
                    enabled: panel.duration > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (event) => {
                        panel.issue(["position", String((event.x / width) * panel.duration)]);
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
                        width: parent.width * (panel.duration > 0 ? Math.min(1, panel.position / panel.duration) : 0)
                        height: 3
                        radius: 1
                        color: panel.accent
                    }
                }
            }

            Row {
                id: transport
                anchors.top: seek.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18

                component Glyph: MouseArea {
                    property string mark
                    width: 42
                    height: 34
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    Text {
                        anchors.centerIn: parent
                        text: mark
                        color: parent.containsMouse ? panel.accent : panel.ink
                        font.family: "JetBrains Mono"
                        font.pixelSize: 18
                    }
                }

                Glyph { mark: "⟨⟨"; onClicked: panel.issue(["previous"]) }
                Glyph { mark: panel.playing ? "⏸" : "▶"; onClicked: panel.issue(["play-pause"]) }
                Glyph { mark: "⟩⟩"; onClicked: panel.issue(["next"]) }
            }

            Item {
                id: mixer
                anchors.top: transport.bottom
                anchors.topMargin: 8
                width: parent.width
                height: 36

                Text {
                    id: volLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: panel.ink
                    opacity: 0.75
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    text: "VOL"
                }
                MouseArea {
                    id: volHit
                    anchors.left: volLabel.right
                    anchors.leftMargin: 8
                    anchors.right: loopBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 16
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (event) => panel.issue(["volume", String(Math.max(0, Math.min(1, event.x / width)))])
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 3
                        radius: 1
                        color: Qt.rgba(panel.ink.r, panel.ink.g, panel.ink.b, 0.22)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * panel.volume
                        height: 3
                        radius: 1
                        color: panel.accent
                    }
                }
                MouseArea {
                    id: loopBtn
                    anchors.right: shuffleBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: loopText.implicitWidth
                    height: 20
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const next = panel.loopMode === "None" ? "Track"
                                   : panel.loopMode === "Track" ? "Playlist" : "None";
                        panel.issue(["loop", next]);
                    }
                    Text {
                        id: loopText
                        anchors.centerIn: parent
                        text: panel.loopMode === "Track" ? "ONE" : panel.loopMode === "Playlist" ? "ALL" : "LOOP"
                        color: panel.loopMode === "None" ? panel.ink : panel.accent
                        opacity: panel.loopMode === "None" ? 0.7 : 1
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: shuffleBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: shuffleText.implicitWidth
                    height: 20
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.issue(["shuffle", "Toggle"])
                    Text {
                        id: shuffleText
                        anchors.centerIn: parent
                        text: "SHUF"
                        color: panel.shuffled ? panel.accent : panel.ink
                        opacity: panel.shuffled ? 1 : 0.7
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                    }
                }
            }

            Glass.CavaBars {
                id: spectrum
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: content.bars
                palette: panel.palette
                running: glass.showing && panel.playing
            }
        }
    }
}
