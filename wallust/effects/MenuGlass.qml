import QtQuick
import Quickshell
import Quickshell.Wayland

// One lifecycle for the menu veil, aperture projection and entrance/exit.
// "item" moves a caller's ornament; "compositor" leaves movement entirely to
// the native layer animation and keeps only its full-output veil resident.
Item {
    id: glass
    required property var surfaceWindow
    required property var targetScreen
    required property url aperture
    required property url vignetteSource
    required property var palette
    required property Item projectionParent
    required property real projectionWidth
    required property real projectionHeight
    property real projectionX: (projectionParent.width - projectionWidth) / 2
    property real projectionY: (projectionParent.height - projectionHeight) / 2
    property real projectionOpacity: 0.34
    property string motion: "item"
    property Item motionTarget: projectionParent
    property bool separateBackdrop: motion === "compositor"
    property string backdropNamespace: ""
    property bool externalReady: true
    property int entranceDelay: motion === "item" ? 20 : 0
    property bool active: false
    property bool entranceStarted: false
    readonly property bool showing: active && entranceStarted
    readonly property bool ready: veil.status === Image.Ready && projection.ready
    property double lastOpenedAt: 0
    property double lastEntranceAt: 0
    property string initialVersion: ""
    property string preparedVersion: ""
    property url preparedAperture: ""
    signal entranceStarting()
    signal closing()

    Component.onCompleted: {
        preparedVersion = initialVersion;
        preparedAperture = aperture;
    }
    onExternalReadyChanged: startWhenReady()
    onPaletteChanged: projection.requestPaint()
    onVignetteSourceChanged: veil.source = vignetteSource

    // The notification veil is never remapped on an ordinary open. Its empty
    // input region and transparent idle pixels leave the native desktop usable.
    PanelWindow {
        id: residentBackdrop
        screen: glass.targetScreen
        visible: glass.separateBackdrop && glass.targetScreen !== null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: glass.backdropNamespace
    }

    Image {
        id: veil
        parent: glass.separateBackdrop ? residentBackdrop.contentItem : glass
        anchors.fill: parent
        z: -2
        cache: false
        opacity: 0
        asynchronous: false
        source: glass.vignetteSource
        sourceSize.width: Math.ceil((glass.targetScreen?.width ?? 1) / 4)
        sourceSize.height: Math.ceil((glass.targetScreen?.height ?? 1) / 4)
        onStatusChanged: glass.startWhenReady()
    }

    StainedGlass {
        id: projection
        // Prepaint the notification mask on the mapped resident surface while
        // idle. The same Canvas/texture joins its native sliding layer on open.
        parent: glass.separateBackdrop && !glass.showing
            ? residentBackdrop.contentItem : glass.projectionParent
        x: glass.projectionX
        y: glass.projectionY
        width: glass.projectionWidth
        height: glass.projectionHeight
        opacity: glass.separateBackdrop && !glass.showing ? 0 : glass.projectionOpacity
        aperture: glass.aperture
        palette: glass.palette
        animationRunning: glass.showing && glass.surfaceWindow.visible
        onReadyChanged: glass.startWhenReady()
    }

    // Publishers can replace bytes at an unchanged URL. This is also the common
    // prewarm entrypoint, used before either native menu receives an open event.
    function prepare(version: string): void {
        if (preparedVersion === version && preparedAperture === aperture)
            return;
        preparedVersion = version;
        if (preparedAperture.toString() !== "")
            projection.unloadImage(preparedAperture);
        preparedAperture = aperture;
        veil.source = "";
        veil.source = vignetteSource;
        projection.ready = false;
        projection.loadImage(aperture);
        projection.requestPaint();
    }

    function startWhenReady(): void {
        // As with the selector, the veil and artwork gate the entrance; the
        // projection can complete its first paint during the native animation.
        if (!active || startDelay.running || entranceStarted || !externalReady ||
            veil.status !== Image.Ready)
            return;
        entranceStarted = true;
        veil.opacity = 1;
        lastEntranceAt = Date.now();
        projection.requestPaint();
        entranceStarting();
        if (motion === "item")
            entrance.start();
    }

    function status(): string {
        return JSON.stringify({active: active, showing: showing, ready: ready,
            veilReady: veil.status === Image.Ready, projectionReady: projection.ready,
            lastOpenedAt: lastOpenedAt, lastEntranceAt: lastEntranceAt,
            lastPaintedAt: projection.lastPaintedAt, motion: motion});
    }

    function open(): void {
        lastOpenedAt = Date.now();
        // Palette publication while SwayNC is open must not remap its layer.
        if (motion === "compositor" && active) {
            startWhenReady();
            return;
        }
        active = false;
        departure.stop();
        entrance.stop();
        startDelay.stop();
        entranceStarted = false;
        veil.opacity = 0;
        if (motion === "item") {
            motionTarget.y = 130;
            motionTarget.opacity = 0;
        }
        active = true;
        if (entranceDelay > 0)
            startDelay.restart();
        else
            startWhenReady();
    }

    function close(): void {
        if (!active || departure.running)
            return;
        startDelay.stop();
        entrance.stop();
        closing();
        if (motion === "compositor") {
            // Unmapping captures the projection for the compositor's native
            // slide. There is no independent Qt fade to race that snapshot.
            active = false;
            entranceStarted = false;
            veil.opacity = 0;
        } else {
            departure.start();
        }
    }

    Timer {
        id: startDelay
        interval: glass.entranceDelay
        onTriggered: glass.startWhenReady()
    }

    ParallelAnimation {
        id: entrance
        NumberAnimation { target: glass.motionTarget; property: "y"; to: 0; duration: 135; easing.type: Easing.OutCubic }
        NumberAnimation { target: glass.motionTarget; property: "opacity"; to: 1; duration: 85; easing.type: Easing.OutQuad }
    }

    SequentialAnimation {
        id: departure
        ParallelAnimation {
            NumberAnimation { target: veil; property: "opacity"; to: 0; duration: 390; easing.type: Easing.InOutQuad }
            SequentialAnimation {
                PauseAnimation { duration: 90 }
                ParallelAnimation {
                    NumberAnimation {
                        target: glass.motionTarget
                        property: "y"
                        to: glass.height
                        duration: 350
                        easing.type: Easing.InCubic
                    }
                    NumberAnimation { target: glass.motionTarget; property: "opacity"; to: 0; duration: 350; easing.type: Easing.InQuad }
                }
            }
        }
        ScriptAction { script: glass.active = false }
    }
}
