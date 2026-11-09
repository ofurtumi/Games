"""
Stylize photo-realistic PNGs into a hand-painted, cartoony look.

Usage:
    python3 tools/stylize_textures.py \
        --in assets/textures/baked \
        --out assets/textures/stylized \
        [--levels 5] [--smooth 4] [--saturation 1.15]

The pipeline (per image):

  1. Edge-preserving smoothing (median filter) — kills photo-grain detail
     while keeping color regions intact. This is the single biggest
     contributor to a "painted" feel.
  2. Posterize to N levels per channel — collapses subtle gradients into
     flat color bands, the hallmark of a stylized texture.
  3. Mild Gaussian blur on top of posterize — softens the hard step edges
     so they read as brush strokes instead of bit-crushed JPGs.
  4. Saturation + warmth bump — paintings tend to push color further than
     photos. Subtle by default.

No external deps beyond Pillow + numpy. Runs anywhere Python does.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter, ImageOps

# numpy is optional — we only use it for cleaner posterize/warmth math.
# When it's missing we fall back to Pillow-only LUT-based equivalents.
try:
    import numpy as np
    HAVE_NUMPY = True
except ImportError:
    np = None
    HAVE_NUMPY = False


def stylize(img: Image.Image, levels: int, smooth: int, saturation: float,
            warmth: float, soften: float) -> Image.Image:
    img = img.convert("RGB")

    # 1. Edge-preserving smoothing. Median is cheap and effective; the radius
    #    controls how many small details get fused into a single color region.
    if smooth > 0:
        img = img.filter(ImageFilter.MedianFilter(size=smooth * 2 + 1))

    # 2. Posterize each channel to `levels` discrete steps. We build a
    #    256-entry lookup table that maps every input byte to one of
    #    `levels` evenly spaced output values, then apply it per channel
    #    via Pillow's point() — works without numpy.
    img = _posterize(img, levels)

    # 3. Soften the posterize edges. A small Gaussian blur turns crisp steps
    #    into something resembling watercolor bleed.
    if soften > 0:
        img = img.filter(ImageFilter.GaussianBlur(radius=soften))

    # 4. Saturation + warmth. Warmth = pushing R up and B down a touch.
    if saturation != 1.0:
        img = ImageEnhance.Color(img).enhance(saturation)
    if warmth != 0.0:
        img = _warmth(img, warmth)

    return img


def _posterize(img: Image.Image, levels: int) -> Image.Image:
    """Snap each channel byte to one of `levels` evenly-spaced values."""
    levels = max(levels, 2)
    step_in = 256.0 / levels       # input bucket width
    step_out = 255.0 / (levels - 1)  # output value spacing
    lut = [int(min(255, round((i // step_in) * step_out))) for i in range(256)]
    # Image.point with a 256-entry list applies the LUT to each channel.
    return img.point(lut * len(img.getbands()))


def _warmth(img: Image.Image, warmth: float) -> Image.Image:
    """Add `warmth*255` to R, subtract from B, clipped to [0, 255]."""
    delta = int(round(warmth * 255))
    if delta == 0:
        return img
    bands = list(img.split())  # R, G, B (and maybe A)
    if len(bands) < 3:
        return img
    r_lut = [max(0, min(255, i + delta)) for i in range(256)]
    b_lut = [max(0, min(255, i - delta)) for i in range(256)]
    bands[0] = bands[0].point(r_lut)
    bands[2] = bands[2].point(b_lut)
    return Image.merge(img.mode, bands)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--in", dest="src", required=True,
                   help="Folder of source PNG/JPGs to stylize.")
    p.add_argument("--out", dest="dst", required=True,
                   help="Folder for stylized output. Created if missing.")
    p.add_argument("--levels", type=int, default=5,
                   help="Color levels per channel (lower = more cartoon). 4-8 sensible.")
    p.add_argument("--smooth", type=int, default=4,
                   help="Median filter radius. 0 disables.")
    p.add_argument("--saturation", type=float, default=1.15)
    p.add_argument("--warmth", type=float, default=0.02,
                   help="Add to R / subtract from B, fraction of 255.")
    p.add_argument("--soften", type=float, default=1.2,
                   help="Gaussian blur radius applied after posterize.")
    p.add_argument("--ext", default=".jpg,.jpeg,.png",
                   help="Comma-separated extensions to process.")
    p.add_argument("--max-size", type=int, default=1024,
                   help="Downscale longest edge to this many pixels. 0 disables. "
                        "Stylized textures usually look better small.")
    args = p.parse_args()

    src = Path(args.src).resolve()
    dst = Path(args.dst).resolve()
    dst.mkdir(parents=True, exist_ok=True)
    exts = {e.strip().lower() for e in args.ext.split(",")}

    files = sorted(f for f in src.iterdir()
                   if f.is_file() and f.suffix.lower() in exts)
    if not files:
        print(f"# No matching files in {src} (looking for {exts})")
        return

    print(f"# stylize {len(files)} file(s) from {src} -> {dst}")
    for f in files:
        out = dst / (f.stem + ".png")
        img = Image.open(f)
        if args.max_size and max(img.size) > args.max_size:
            ratio = args.max_size / max(img.size)
            img = img.resize(
                (int(img.size[0] * ratio), int(img.size[1] * ratio)),
                Image.LANCZOS,
            )
        stylized = stylize(
            img,
            levels=args.levels,
            smooth=args.smooth,
            saturation=args.saturation,
            warmth=args.warmth,
            soften=args.soften,
        )
        stylized.save(out, format="PNG", optimize=True)
        print(f"  {f.name} -> {out.name}  ({stylized.size[0]}x{stylized.size[1]})")


if __name__ == "__main__":
    main()
