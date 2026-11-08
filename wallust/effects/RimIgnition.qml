import QtQuick

// Palette trails travel the inner rim of an aperture mask. Cached routes are
// shared by every framed menu; only the 450ms entrance replay is per-open.
Canvas {
    id: ignition
    required property url aperture
    required property var palette
    property bool active: false
    property var routes: []
    property double started: 0
    property bool finished: true
    property bool prepared: false
    // Hide immediately on close. requestPaint is async; Hyprland snapshots the
    // notification layer as it unmaps, and compositor motion has no Qt fade.
    opacity: 0
    Component.onCompleted: loadImage(aperture)
    onApertureChanged: reset()
    onImageLoaded: requestPaint()

    function arm(): void {
        started = Date.now();
        finished = false;
        opacity = 1;
        requestPaint();
    }

    function disarm(): void {
        finished = true;
        opacity = 0;
        requestPaint();
    }

    function reset(): void {
        prepared = false;
        routes = [];
        if (aperture.toString() !== "")
            unloadImage(aperture);
        loadImage(aperture);
        requestPaint();
    }

    function edgePoint(pixels, cx, cy, angle) {
        const radians = angle * Math.PI / 180;
        const dx = Math.cos(radians), dy = Math.sin(radians);
        let distance = 0;
        for (; distance < Math.max(width, height); ++distance) {
            const x = Math.round(cx + dx * distance);
            const y = Math.round(cy + dy * distance);
            if (x < 0 || x >= width || y < 0 || y >= height || pixels[(y * width + x) * 4 + 3] < 128)
                break;
        }
        return [cx + dx * Math.max(0, distance - 5), cy + dy * Math.max(0, distance - 5), distance];
    }

    function route(pixels, cx, cy, first, top, direction) {
        const points = [];
        let corner = 0;
        for (let angle = first; angle !== top + direction; angle += direction) {
            const point = edgePoint(pixels, cx, cy, angle);
            if (points.length < 45 && (!points.length || point[2] > points[corner][2]))
                corner = points.length;
            points.push(point);
        }
        return points.slice(corner);
    }

    function trail(ctx, points, head, length, color, width, opacity) {
        const first = Math.max(0, head - length);
        const last = Math.min(points.length - 1, head);
        if (last <= first)
            return;
        ctx.strokeStyle = color;
        ctx.lineWidth = width;
        ctx.globalAlpha = opacity;
        ctx.beginPath();
        ctx.moveTo(points[first][0], points[first][1]);
        for (let index = first + 1; index <= last; ++index)
            ctx.lineTo(points[index][0], points[index][1]);
        ctx.stroke();
    }

    onPaint: {
        if (!isImageLoaded(aperture))
            return;
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        if (!prepared) {
            ctx.drawImage(aperture, 0, 0);
            const pixels = ctx.getImageData(0, 0, width, height).data;
            const cx = Math.floor(width / 2), cy = Math.floor(height / 2);
            routes = pixels[(cy * width + cx) * 4 + 3] >= 128
                ? [route(pixels, cx, cy, 110, 270, 1), route(pixels, cx, cy, 70, -90, -1)] : [];
            ctx.clearRect(0, 0, width, height);
            prepared = true;
        }
        if (finished || !active)
            return;
        const elapsed = Date.now() - started;
        if (elapsed >= 450 || routes.length === 0) {
            finished = true;
            return;
        }
        const progress = Math.max(0, Math.min(1, elapsed / 390));
        const fade = Math.max(0, Math.min(1, elapsed / 45, (450 - elapsed) / 75));
        const colors = palette;
        ctx.save();
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        for (const points of routes) {
            const head = Math.round(progress * (points.length - 1));
            trail(ctx, points, head, 22, Qt.lighter(colors[1], 1.7), 14, fade * 0.65);
            trail(ctx, points, head, 13, Qt.lighter(colors[2], 1.55), 4, fade);
        }
        ctx.globalAlpha = 1;
        ctx.globalCompositeOperation = "destination-in";
        ctx.drawImage(aperture, 0, 0);
        ctx.restore();
    }

    Timer {
        interval: 16
        repeat: true
        running: ignition.active && !ignition.finished
        onTriggered: ignition.requestPaint()
    }
}
