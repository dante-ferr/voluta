import QtQuick

// CAVA-like bars, masked to the same aperture as stained glass. 25fps matches
// StainedGlass so NVIDIA sessions do not gain a second high-rate painter.
Canvas {
    id: spectrum
    property url aperture: ""
    required property var palette
    property var levels: []
    property bool running: false
    onLevelsChanged: requestPaint()
    onApertureChanged: {
        if (aperture.toString() !== "")
            loadImage(aperture);
        requestPaint();
    }
    Component.onCompleted: {
        if (aperture.toString() !== "")
            loadImage(aperture);
    }
    onImageLoaded: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        const bars = levels.length ? levels : [];
        if (!bars.length)
            return;
        if (aperture.toString() !== "" && !isImageLoaded(aperture))
            return;
        const count = bars.length;
        const gutter = Math.max(2, width * 0.012);
        const slot = (width - gutter * (count + 1)) / count;
        const floor = height * 0.96;
        const rise = height * 0.90;
        const first = Qt.color(palette[0]);
        const second = Qt.color(palette[1]);
        const highlight = Qt.rgba(first.r, first.g, first.b, 0.88);
        const body = Qt.rgba(second.r, second.g, second.b, 0.70);
        ctx.save();
        for (let index = 0; index < count; ++index) {
            const amount = Math.max(0, Math.min(1, Number(bars[index]) / 100));
            const barHeight = Math.max(4, amount * rise);
            const x = gutter + index * (slot + gutter);
            const gradient = ctx.createLinearGradient(x, floor - barHeight, x, floor);
            gradient.addColorStop(0, highlight);
            gradient.addColorStop(1, body);
            ctx.fillStyle = gradient;
            ctx.fillRect(x, floor - barHeight, Math.max(2, slot), barHeight);
        }
        if (aperture.toString() !== "" && isImageLoaded(aperture)) {
            ctx.globalCompositeOperation = "destination-in";
            ctx.drawImage(aperture, 0, 0);
        }
        ctx.restore();
    }

    Timer {
        interval: 40
        repeat: true
        running: spectrum.running
        onTriggered: spectrum.requestPaint()
    }
}
