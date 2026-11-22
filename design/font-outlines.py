"""Glyph outlines and advances for the macOS system fonts used by the template.

OpenPencil cannot load the system fonts by family name, so generate-template.mjs stores
pre-rendered glyph outlines (derivedTextGlyphs) on every text node that uses them.
argv[1]: JSON {"<family>": [[weight, "<file under /System/Library/Fonts>", {axis: value}], ...]}.
Prints JSON: {"<family><weight>": {"<char>": [advance_em, base64_commands]}}.
"""

import base64
import json
import struct
import sys
from pathlib import Path

from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont

LETTERS = sorted({chr(k) for k in range(32, 127)} | set("·…≈—»©çğıöşüÇĞİÖŞÜ−×÷⌘⌥⇧⌃"))
FONTS = Path("/System/Library/Fonts")


class Outline(BasePen):
    def __init__(self, glyphs, units):
        super().__init__(glyphs)
        self.data = bytearray()
        self.units = units

    def points(self, op, *points):
        self.data.append(op)
        for x, y in points:
            self.data.extend(struct.pack("<ff", x / self.units, y / self.units))

    def _moveTo(self, xy):
        self.points(1, xy)

    def _lineTo(self, xy):
        self.points(2, xy)

    def _curveToOne(self, a, b, c):
        self.points(4, a, b, c)

    def _closePath(self):
        self.data.append(0)


faces = {}
for family, entries in json.loads(sys.argv[1]).items():
    for weight, file, axes in entries:
        font = TTFont(FONTS / file)
        units = font["head"].unitsPerEm
        cmap = font.getBestCmap()
        glyphs = (
            font.getGlyphSet(location=axes) if "fvar" in font else font.getGlyphSet()
        )
        face = {}
        for ch in LETTERS:
            name = cmap.get(ord(ch))
            if not name:
                continue
            pen = Outline(glyphs, units)
            glyphs[name].draw(pen)
            face[ch] = [
                glyphs[name].width / units,
                base64.b64encode(pen.data or b"\x00").decode(),
            ]
        faces[family + str(weight)] = face
print(json.dumps(faces))
