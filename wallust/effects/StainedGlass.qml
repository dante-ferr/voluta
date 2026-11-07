import QtQuick

Canvas {
    id: projection
    // Shared by the selector and notification salon; callers set geometry and opacity.
    required property url aperture
    required property var palette
    property bool animationRunning: visible
    property bool ready: false
    readonly property double started: Date.now()
    readonly property int repeatWidth: 660
    Component.onCompleted: loadImage(aperture)
    onApertureChanged: { ready = false; loadImage(aperture); }
    onImageLoaded: requestPaint()

    function tint(color, alpha, brightness) {
        const tone = Qt.lighter(color, brightness);
        return Qt.rgba(tone.r, tone.g, tone.b, alpha);
    }

    function beam(ctx, x, span, color, light) {
        const gradient = ctx.createLinearGradient(x, 0, x + span, 0);
        gradient.addColorStop(0, "transparent");
        gradient.addColorStop(0.22, tint(color, 0.24, 1.55));
        gradient.addColorStop(0.43, tint(color, 0.56, 1.7));
        gradient.addColorStop(0.58, tint(light, 0.36, 1.12));
        gradient.addColorStop(0.76, tint(color, 0.40, 1.55));
        gradient.addColorStop(1, "transparent");
        ctx.fillStyle = gradient;
        ctx.fillRect(x, -520, span, 1040);
    }

    // Broad facets suggest projected panes without outlining a second frame.
    function facet(ctx, x, y, span, color) {
        const gradient = ctx.createLinearGradient(x, y, x + span, y + 150);
        gradient.addColorStop(0, "transparent");
        gradient.addColorStop(0.42, tint(color, 0.22, 1.28));
        gradient.addColorStop(1, "transparent");
        ctx.fillStyle = gradient;
        ctx.beginPath();
        ctx.moveTo(x + span * 0.38, y);
        ctx.lineTo(x + span, y + 86);
        ctx.lineTo(x + span * 0.67, y + 218);
        ctx.lineTo(x, y + 132);
        ctx.closePath();
        ctx.fill();
    }

    onPaint: {
        if (!isImageLoaded(aperture))
            return;
        const ctx = getContext("2d");
        const [first, second, light] = palette;
        const seconds = (Date.now() - started) / 1000;
        const offset = (seconds * 34 + 103) % repeatWidth;
        ctx.clearRect(0, 0, width, height);
        ctx.save();
        ctx.translate(width / 2, height / 2);
        ctx.rotate(-0.48);
        for (let period = -2; period <= 1; ++period) {
            const x = period * repeatWidth + offset;
            beam(ctx, x - 54, 274, first, light);
            beam(ctx, x + 186, 265, second, light);
            beam(ctx, x + 438, 160, light, first);
            for (let row = -2; row <= 1; ++row) {
                facet(ctx, x + 20, row * 226 - 48, 153, light);
                facet(ctx, x + 250, row * 226 + 18, 157, first);
            }
        }
        ctx.restore();
        ctx.save();
        ctx.globalCompositeOperation = "destination-in";
        ctx.drawImage(aperture, 0, 0);
        ctx.restore();
        if (!ready) {
            ready = true;
        }
    }

    Timer {
        interval: 40
        repeat: true
        running: projection.animationRunning
        onTriggered: projection.requestPaint()
    }
}
