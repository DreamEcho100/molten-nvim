import re
from typing import List, Optional, Tuple

from molten.outputchunks import ANSI_CODE_REGEX, ImageOutputChunk, Output, TextOutputChunk

SCALE = 2  # export at 2x so small text and tiny images stay readable
FONT_SIZE = 14
SMALL_IMAGE_WIDTH = 300  # images narrower than this are scaled up, plots are left alone


def _hex(color: str) -> Tuple[int, int, int]:
    color = color.lstrip("#")
    return int(color[0:2], 16), int(color[2:4], 16), int(color[4:6], 16)


def _text_lines(text: str) -> List[str]:
    text = ANSI_CODE_REGEX.sub("", text).replace("\r\n", "\n").replace("\r", "\n")
    return text.expandtabs(4).rstrip("\n").split("\n")


def export_image(
    outputs: List[Output],
    path: str,
    bg: str,
    fg: str,
    font_path: Optional[str],
) -> None:
    """Draw the given outputs (an `Out[n]` header, then their text and images in order)
    top to bottom onto one PNG, in the given background and text colours."""
    from PIL import Image, ImageDraw, ImageFont

    size = FONT_SIZE * SCALE
    try:
        font = ImageFont.truetype(font_path, size) if font_path else ImageFont.load_default(size)
    except OSError:
        font = ImageFont.load_default(size)
    bg_rgb, fg_rgb = _hex(bg), _hex(fg)
    dim_rgb = tuple((a + b) // 2 for a, b in zip(bg_rgb, fg_rgb))
    line_height = round(size * 1.4)
    pad = 12 * SCALE
    gap = 8 * SCALE

    # blocks: ("text", lines, colour) or ("image", PIL image)
    blocks: list = []
    for number, output in enumerate(outputs):
        if number:
            blocks.append(("space", gap))
        blocks.append(("text", [f"Out[{output.execution_count}]"], dim_rgb))
        for chunk in output.chunks:
            if isinstance(chunk, ImageOutputChunk):
                try:
                    img = Image.open(chunk.img_path).convert("RGBA")
                except OSError:
                    continue
                if img.width < SMALL_IMAGE_WIDTH:
                    img = img.resize((img.width * SCALE, img.height * SCALE), Image.LANCZOS)
                blocks.append(("image", img))
            elif isinstance(chunk, TextOutputChunk) and chunk.text.strip():
                blocks.append(("text", _text_lines(chunk.text), fg_rgb))

    width = 0
    height = 0
    for block in blocks:
        if block[0] == "text":
            width = max(width, round(max(font.getlength(line) for line in block[1])))
            height += line_height * len(block[1])
        elif block[0] == "image":
            width = max(width, block[1].width)
            height += block[1].height + gap // 2
        else:
            height += block[1]

    canvas = Image.new("RGB", (max(width, 1) + 2 * pad, max(height, 1) + 2 * pad), bg_rgb)
    draw = ImageDraw.Draw(canvas)
    y = pad
    for block in blocks:
        if block[0] == "text":
            for line in block[1]:
                draw.text((pad, y), line, font=font, fill=block[2])
                y += line_height
        elif block[0] == "image":
            canvas.paste(block[1], (pad, y), block[1])
            y += block[1].height + gap // 2
        else:
            y += block[1]
    canvas.save(path)
