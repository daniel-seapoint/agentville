"""Shrinks the theme and style screenshots and joins recorded clips into one GIF.

Usage: make_gif.py <docs folder> <gif name> <clip folder> [<clip folder> ...]
Each clip is a folder of numbered PNGs made with `Agentville --record`; they play in the order given.
Set GIF_FRAMES to take more frames from each clip than the default eight, for a longer GIF.
"""
import glob
import os
import sys

from PIL import Image

WIDTH = 1600
# The GIF is smaller: every other recorded frame, eight per clip.
GIF_WIDTH = 800
STEP = 2
FRAMES_PER_CLIP = int(os.environ.get("GIF_FRAMES", "8"))


def shrink(image, width=WIDTH):
    if image.width <= width:
        return image
    return image.resize((width, round(image.height * width / image.width)), Image.LANCZOS)


def main():
    docs, name, clips = sys.argv[1], sys.argv[2], sys.argv[3:]

    # Stills, at the width the README shows them.
    for path in glob.glob(os.path.join(docs, "themes", "*.png")) + glob.glob(os.path.join(docs, "styles", "*.png")):
        shrink(Image.open(path).convert("RGB")).save(path, optimize=True)

    frames = []
    for clip_folder in clips:
        paths = sorted(glob.glob(os.path.join(clip_folder, "frame_*.png")))[::STEP][:FRAMES_PER_CLIP]
        if not paths:
            print(f"no frames in {clip_folder}", file=sys.stderr)
            continue
        clip = [shrink(Image.open(path).convert("RGB"), GIF_WIDTH) for path in paths]
        # One palette per clip keeps its colours true and lets unchanged pixels carry over.
        palette = clip[0].quantize(colors=128, method=Image.Quantize.MEDIANCUT)
        frames += [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in clip]
    if not frames:
        sys.exit("no frames recorded")
    out = os.path.join(docs, name)
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=100 * STEP, loop=0, optimize=True)
    print(out, len(frames), "frames", os.path.getsize(out) // 1024, "KB")


if __name__ == "__main__":
    main()
