#!/usr/bin/env python3
"""Check wallpaper crop/scale and glow isolation without touching desktop state."""
import importlib.util
from pathlib import Path
import tempfile
import os
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("decorations", ROOT / "waybar/scripts/render-decorations.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory(prefix="waybar-contrast-") as temporary:
    base = Path(temporary)
    source = base / "wallpaper.png"
    image = Image.new("RGB", (400, 200), "black")
    image.paste("white", (100, 0, 300, 200))
    image.save(source)
    cropped = module.wallpaper_image(source, (200, 200))
    assert cropped.size == (200, 200)
    assert cropped.getpixel((50, 0)) == (255, 255, 255)
    scaled = module.wallpaper_image(source, (200, 100))
    assert scaled.size == (200, 100)
    assert scaled.getpixel((10, 0)) == (0, 0, 0)
    assert scaled.getpixel((100, 0)) == (255, 255, 255)
    fitted = module.wallpaper_image(source, (200, 200), "fit", "#123456")
    assert fitted.getpixel((0, 0)) == (18, 52, 86)
    # A tall image loses its upper portion under centered fill. Cropping the
    # original image's top would therefore sample a different scene.
    tall = Image.new("RGB", (100, 300), "black")
    tall.paste("white", (0, 0, 100, 100))
    tall.save(source)
    assert module.wallpaper_image(source, (100, 100)).getpixel((50, 30)) == (0, 0, 0)
    assert module.wallpaper_image(source, (100, 100), gravity="top").getpixel((50, 30)) == (255, 255, 255)
    # Read the actual backend anchor, reject stale images and other namespaces.
    cache = base / "awww/0.12.1"
    cache.mkdir(parents=True)
    (cache / "eDP-1").write_bytes(b"other\0crop:center\0Lanczos3\0/tmp/other\0\0crop:top\0Lanczos3\0" + str(source).encode())
    previous_cache = os.environ.get("XDG_CACHE_HOME")
    os.environ["XDG_CACHE_HOME"] = str(base)
    assert module.cached_placement("awww", "eDP-1", str(source)) == ("crop", "top", "Lanczos3")
    assert module.cached_placement("awww", "eDP-1", "/tmp/stale") is None
    if previous_cache is None:
        os.environ.pop("XDG_CACHE_HOME")
    else:
        os.environ["XDG_CACHE_HOME"] = previous_cache

    svg = base / "patera.svg"
    svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14">'
                   '<path fill="#161616" d="M4 4H10V10H4Z"/></svg>')
    settings = {"expansion_px": .15, "blur_px": .5, "opacity": .07}
    light, dark = base / "light.png", base / "dark.png"
    module.glowing(svg, light, None, settings, "#ccbbdd")
    module.glowing(svg, dark, "#ccbbdd", settings, "#080808")
    with Image.open(light) as light_image, Image.open(dark) as dark_image:
        light_alpha = light_image.getchannel("A")
        dark_alpha = dark_image.getchannel("A")
        # The light asset has no halo pixels; dark adds only a faint one.
        halo = [d for l, d in zip(light_alpha.tobytes(), dark_alpha.tobytes()) if l == 0 and d > 0]
        assert halo and max(halo) <= 18
        assert light_image.getpixel((45, 45))[:3] == (204, 187, 221)
        assert dark_image.getpixel((45, 45))[:3] == (8, 8, 8)
print("PASS: full-output crop/scale, vertical crop, backend anchoring/cache, palette ink and dark-only faint glow")
