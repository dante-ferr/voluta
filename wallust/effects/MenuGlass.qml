import QtQuick
import Quickshell
import Quickshell.Io
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
    // Aperture-shaped dark glass, the same 50% palette plate on every framed
    // menu. Empty uses the sibling *-glass.png, so a menu does not paint its own.
    property url plateGlass: ""
    readonly property url resolvedPlate: {
        if (plateGlass.toString() !== "")
            return plateGlass;
        const text = aperture.toString();
        return text.indexOf("-aperture.") >= 0 ? text.replace("-aperture.", "-glass.") : "";
    }
    required property var palette
    required property Item projectionParent
    required property real projectionWidth
    required property real projectionHeight
    property real projectionX: (projectionParent.width - projectionWidth) / 2
    property real projectionY: (projectionParent.height - projectionHeight) / 2
    property real projectionOpacity: 0.34
    property string motion: "item"
    // Shell toggles read this file instead of asking Quickshell whether the
    // menu is open. A missing or empty file means closed.
    property string openState: ""
    property string itemAxis: "y"
    property real itemEnterFrom: 130
    property real itemLeaveTo: -1
    property Item motionTarget: projectionParent
    // -1 means "leave through the far edge". A smaller value leaves to the left.
    readonly property real itemExitTo: itemLeaveTo < -1 ? itemLeaveTo
        : (itemLeaveTo >= 0 ? itemLeaveTo : (itemAxis === "x" ? width : height))
    property bool separateBackdrop: motion === "compositor"
    property string backdropNamespace: ""
    property bool externalReady: true
    property int entranceDelay: motion === "item" ? 20 : 0
    // Item exits match the short entrance. The notification layer is unmapped
    // while this stays false so the compositor snapshots the glass in place.
    property bool surfaceMapped: false
    property bool parked: true
    property int entranceTravel: 170
    property int entranceFade: 110
    property int exitTravel: 230
    property int exitFade: 200

    FileView {
        id: openMarker
        path: glass.openState
        blockWrites: true
        atomicWrites: true
        printErrors: false
        watchChanges: false
    }

    function publishOpenState(): void {
        if (glass.openState === "")
            return;
        openMarker.setText(glass.active ? "1\n" : "");
    }

    onActiveChanged: publishOpenState()
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
        publishOpenState();
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
        // The frost stays on the full output. Fading its opacity is what shows
        // and hides the blur. Parenting it to the sliding notification surface
        // makes that blur travel with the panel and miss the top of the screen.
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

    NumberAnimation {
        id: veilFade
        target: veil
        property: "opacity"
        easing.type: Easing.OutQuad
    }

    // Moves with the frame. The PNG's own alpha keeps the frost inside the opening.
    Image {
        id: plate
        parent: glass.projectionParent
        x: glass.projectionX
        y: glass.projectionY
        width: glass.projectionWidth
        height: glass.projectionHeight
        z: -1
        visible: glass.resolvedPlate.toString() !== ""
        cache: false
        asynchronous: false
        source: glass.resolvedPlate
    }

    StainedGlass {
        id: projection
        // Prepaint the notification mask on the mapped resident surface while
        // idle. The same Canvas/texture joins its native sliding layer on open.
        // Stay on the sliding surface through unmap. Parking on the backdrop
        // in the same frame drops the glass out of Hyprland's exit snapshot,
        // so it no longer travels with the frame.
        parent: glass.separateBackdrop && glass.parked
            ? residentBackdrop.contentItem : glass.projectionParent
        x: glass.projectionX
        y: glass.projectionY
        width: glass.projectionWidth
        height: glass.projectionHeight
        opacity: glass.separateBackdrop && glass.parked ? 0 : glass.projectionOpacity
        aperture: glass.aperture
        palette: glass.palette
        animationRunning: glass.showing && glass.surfaceWindow.visible
        onReadyChanged: glass.startWhenReady()
    }

    RimIgnition {
        id: ignition
        parent: projection.parent
        x: projection.x
        y: projection.y
        width: projection.width
        height: projection.height
        z: 1
        aperture: glass.aperture
        palette: glass.palette
        active: glass.showing
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
        if (resolvedPlate.toString() !== "") {
            plate.source = "";
            plate.source = resolvedPlate;
        }
        projection.ready = false;
        projection.loadImage(aperture);
        projection.requestPaint();
        ignition.reset();
    }

    function fadeVeil(targetOpacity: real, duration: int): void {
        if (motion !== "compositor") {
            veil.opacity = targetOpacity;
            return;
        }
        veilFade.stop();
        veilFade.duration = duration;
        veilFade.to = targetOpacity;
        veilFade.restart();
    }

    function startWhenReady(): void {
        // As with the selector, the veil and artwork gate the entrance; the
        // projection can complete its first paint during the native animation.
        if (!active || startDelay.running || entranceStarted || !externalReady ||
            veil.status !== Image.Ready)
            return;
        entranceStarted = true;
        fadeVeil(1, glass.entranceTravel);
        lastEntranceAt = Date.now();
        projection.requestPaint();
        ignition.arm();
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
        parkTimer.stop();
        active = false;
        departure.stop();
        entrance.stop();
        startDelay.stop();
        entranceStarted = false;
        veilFade.stop();
        veil.opacity = 0;
        if (motion === "item") {
            motionTarget.x = itemAxis === "x" ? itemEnterFrom : 0;
            motionTarget.y = itemAxis === "y" ? itemEnterFrom : 0;
            motionTarget.opacity = 0;
        } else {
            parked = false;
            surfaceMapped = true;
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
        ignition.disarm();
        closing();
        if (motion === "compositor") {
            // The aperture stays on the sliding surface until the snapshot
            // finishes. The veil fades where it is, across the whole output.
            active = false;
            entranceStarted = false;
            fadeVeil(0, exitFade);
            surfaceMapped = false;
            parkTimer.restart();
        } else {
            departure.start();
        }
    }

    Timer {
        id: parkTimer
        interval: 720
        onTriggered: {
            if (glass.surfaceMapped)
                return;
            glass.parked = true;
        }
    }

    Timer {
        id: startDelay
        interval: glass.entranceDelay
        onTriggered: glass.startWhenReady()
    }

    ParallelAnimation {
        id: entrance
        NumberAnimation { target: glass.motionTarget; property: glass.itemAxis; to: 0; duration: glass.entranceTravel; easing.type: Easing.OutCubic }
        NumberAnimation { target: glass.motionTarget; property: "opacity"; to: 1; duration: glass.entranceFade; easing.type: Easing.OutQuad }
    }

    SequentialAnimation {
        id: departure
        ParallelAnimation {
            NumberAnimation { target: veil; property: "opacity"; to: 0; duration: glass.exitFade; easing.type: Easing.OutQuad }
            NumberAnimation {
                target: glass.motionTarget
                property: glass.itemAxis
                to: glass.itemExitTo
                duration: glass.exitTravel
                easing.type: Easing.InQuad
            }
            NumberAnimation { target: glass.motionTarget; property: "opacity"; to: 0; duration: glass.exitTravel; easing.type: Easing.InQuad }
        }
        ScriptAction { script: glass.active = false }
    }
}
