"""Shrinks the theme and style screenshots and joins the recorded theme clips into one GIF.

Usage: make_gif.py <recordings folder> <docs folder> <theme> [<theme> ...]
Each theme's recording is a folder of numbered PNGs made with `Agentville --record`.
"""
import glob
import os
import sys

from PIL import Image

WIDTH = 960


def shrink(image):
    if image.width <= WIDTH:
        return image
    return image.resize((WIDTH, round(image.height * WIDTH / image.width)), Image.LANCZOS)


def main():
    recordings, docs, themes = sys.argv[1], sys.argv[2], sys.argv[3:]

    # Stills, at the width the README shows them.
    for path in glob.glob(os.path.join(docs, "themes", "*.png")) + glob.glob(os.path.join(docs, "styles", "*.png")):
        shrink(Image.open(path).convert("RGB")).save(path, optimize=True)

    frames = []
    for theme in themes:
        paths = sorted(glob.glob(os.path.join(recordings, theme, "frame_*.png")))
        if not paths:
            print(f"no frames for {theme}", file=sys.stderr)
            continue
        for path in paths:
            frames.append(shrink(Image.open(path).convert("RGB")))
    if not frames:
        sys.exit("no frames recorded")
    # One palette per frame keeps each theme's colours true.
    quantized = [frame.quantize(colors=200, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for frame in frames]
    out = os.path.join(docs, "themes.gif")
    quantized[0].save(out, save_all=True, append_images=quantized[1:], duration=100, loop=0, optimize=True)
    print(out, len(frames), "frames", os.path.getsize(out) // 1024, "KB")


if __name__ == "__main__":
    main()
