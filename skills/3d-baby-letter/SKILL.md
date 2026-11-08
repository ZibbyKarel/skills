---
name: 3d-baby-letter
description: Generate a parametric, multicolor, 3D-printable baby-birth keepsake — a big initial letter of the child's name with inset decorative pieces (date, time, weight, length, an animal, and the child's script name) scattered randomly across the letter and cut into pockets. Supports a classic layout (clock + calendar) or a polaroid-photo-frame layout, fully parametric fonts (local file, installed system font, or auto-downloaded Google Font) and per-part colors, random or bottom-centered name placement, and optional wall-mounting (blind keyholes, invisible from the front) or a slide-in stand. Use this whenever the user asks for a 3D-printable baby/birth/name keepsake, nursery letter, or similar personalized multi-piece inlaid letter model.
---

# Baby Letter 3D — parametric birth keepsake generator

Generates STL/3MF files for a 3D-printable keepsake: a large initial letter with
decorative pieces (weight, ruler/length, an animal, and either clock+calendar or a
polaroid photo frame) inlaid into shallow pockets cut into the letter, plus the
child's full name in a script font somewhere on the letter. Every part can be a
different filament color. Optional wall-mount (blind screw keyholes, invisible from
the front) or a stand the letter slides into.

Nothing here has been physically test-printed — treat results as geometry-validated
designs, not print-proven ones.

## Setup

```bash
pip install --break-system-packages trimesh shapely manifold3d fonttools matplotlib numpy
```

For 3D preview renders (optional, needs Node + a sandboxed Chromium):

```bash
npm install playwright three   # run once in the render directory
# Playwright's bundled Chromium must be present; if not: npx playwright install chromium
```

Save `make_letter.py` (below) and, if you want renders, `render_views.js` (below,
in its own directory with `node_modules/three` installed next to it).

## Gathering input before running

Before generating, get from the user (ask if missing, don't guess silently on
anything that changes the deliverable):

- child's full name (for the script-font name) and which letter is the "big" initial
  (defaults to the first letter of the name)
- birth date, time, weight, length
- an animal: `bear`, `bunny`, or `mouse` (ask which, or suggest one)
- layout: `classic` (clock + calendar) or `polaroid` (photo frame with date+time on
  it instead) — ask if they want a spot for a birth/ultrasound photo
- mounting: `wall` (hang on screws), `stand` (slide-in base, stands upright), `both`,
  or `none`
- desired colors per part, if they care (otherwise use the tasteful defaults below)
- fonts, if they have a preference (otherwise pick fitting Google Fonts defaults —
  a rounded/friendly font for the letter, a script font for the name)

If the user wants several distinct variants (e.g. multiple names, or "show me a few
options"), vary `--seed`, fonts, colors, animal, layout and mount across runs so each
is visually distinct, not just a recolor.

## Running

```bash
python3 make_letter.py --name "Natálie" --animal bunny --layout classic \
    --date 11.12.2025 --time 09:05 --weight "4100 g" --length "57 cm" \
    --mount wall --seed 7 --out out/natalie
```

Key flags (full list in the script's `--help` / argparse block):

- `--name`, `--initial` — full name; initial defaults to the name's first letter
- `--animal {bear,bunny,mouse}`
- `--layout {classic,polaroid}`
- `--date`, `--time`, `--weight`, `--length` — free text, rendered with `--num-font`
- `--height` — letter height in mm (default 170)
- `--letter-font` / `--letter-weight`, `--name-font` / `--name-weight`,
  `--num-font` / `--num-weight` — each a file path, an installed family name
  (resolved via `fc-match`), or a Google Fonts family name (auto-downloaded). Variable
  fonts are instanced at the requested weight automatically.
- `--name-min-stroke` — thin script fonts get their strokes fattened until they clear
  this minimum (mm), so delicate fonts still print as one connected piece
- `--fatten` — extra mm added around the letter glyph (raise if a piece/scale report
  shows the letter is too thin to hold pockets, e.g. Comfortaa's narrow "S" needed 9)
- `--piece-scale`, `--min-overlap`, `--max-rot`, `--seed` — layout search knobs
- `--thick`, `--base`, `--tol` — pocket depth, floor thickness, pocket clearance
- `--color ROLE=COLOR` (repeatable) — per-part color, e.g.
  `--color letter=#cfe8dc --color name=white --color heart=red`. Roles: `letter,
name, heart, animal, animal_detail, animal_face, weight, weight_text, ruler,
ruler_text, clock, clock_text, calendar, calendar_text, polaroid, polaroid_text,
stand`. Unset roles use the script's defaults (`COLORS` dict); `animal`'s default
  depends on the chosen animal unless overridden.
- `--name-placement {random,bottom}` — `random` (default) places the name anywhere on
  the letter, rotated within `±--name-max-rot` degrees (never upside down); `bottom`
  is the classic horizontal placement at the base
- `--name-max-rot` — max |rotation| in degrees for random name placement (default 35)
- `--mount {wall,stand,both,none}` — `wall` cuts blind keyhole slots into the back
  only (not visible or reachable from the front, sized for screw heads ≤9mm,
  symmetric where there's room); `stand` builds a separate `stand.stl` whose slot is
  the exact 3D negative of the model's bottom 14mm, collision-checked at build time;
  `both` does both; `none` skips mounting entirely
- `--out` — output directory

## After running: read the stdout report

The script prints a validation report — read it every time, don't just assume success:

- `fonts: ...` — which resolved font files were used
- `letter WxH mm, piece scale, seed` — if piece scale had to shrink well below 1.0
  (e.g. ≤0.65), the letter was too thin/small for its pieces; raise `--fatten`,
  `--height`, or lower `--min-overlap`
- per-piece `on letter: NN%` overlap
- `pieces gap >= 2 mm: True/False` — must be True
- `letter stays one piece: True/False` — must be True (pockets must not sever the
  letter into disconnected parts or paper-thin necks)
- `every name island glued on letter: True/False` — must be True (checks every glyph
  island, including diacritics like "á", sits solidly on the letter)
- `name keeps counters (holes): N` — sanity count of letter holes in the name (e.g. a/o)
- for polaroid layout: cut photo size and max recess depth
- `wall keyholes: N (...)mm ... WARNING: no room for a keyhole` if mounting is wall/both
- for stand: `stand: W x D x H mm, slot N mm deep, collision with model X mm3` — X
  must be 0.00 (or extremely close to it)
- `N STL written (colours in colors.txt), non-watertight: [...]` — the list must be
  `none`; a non-watertight mesh needs investigation before sending to a slicer

## Deliverables

For each variant, deliver:

- one `.stl` per named part/role (so a slicer can assign a different filament color
  to each), plus `stand.stl` if a stand was requested
- `colors.txt` — legend mapping each STL filename to its color role and hex color
- `assembled.3mf` — all parts combined for a quick single-file preview
- `preview.png` — top-down 2D diagram (pockets, pieces, name, stand outline)
- optionally, 3D front/back renders (see below) for a more intuitive preview,
  especially useful to confirm wall-mount keyholes are not visible from the front
- the generator script itself (and `variants.sh`-style run commands if several
  variants were made), so the user can regenerate or tweak later

Package multiple variants into one zip with per-variant subfolders. Always mention:
nothing has been physically test-printed; any font/fatten workaround used; and, if
wall-mounted, that the keyholes are blind (back-only) by design — `KEY_TOP` is kept
less than the letter's total thickness (`--base + --thick`) so the cutter never
reaches the front face.

## Optional: 3D preview renders

`make_letter.py` writes `render_scene.json` (vertex/face/color data, pre-transformed
into the "standing upright, front facing -Y" orientation) into each `--out` directory.
Render front/back PNGs with:

```bash
node render_views.js out/natalie/render_scene.json out/natalie/natalie
# -> natalie_front.png, natalie_back.png
```

This needs Playwright with its bundled Chromium (launched headless, software WebGL
via swiftshader) and a local `three.js` build at `node_modules/three/build/three.min.js`
next to `render_views.js`.

## Design notes for revisiting this skill

- **Pockets**: every piece's footprint, buffered by `--tol` for clearance, is unioned
  and intersected with the letter to get the pocket area; holes in that union are
  filled (no isolated islands) before cutting, via `pocket_area()`.
- **Text to polygon**: `text_poly()` converts glyphs to shapely polygons using
  contour nesting-depth parity (not signed area) to separate outer contours from
  holes — robust to fonts with inconsistent winding.
- **Random layout**: `random_layout()` scatters pieces (can overhang the letter edge),
  rejecting placements that don't overlap the letter enough, that come within `gap`mm
  of another piece or the name, or that would split the letter into >1 piece or leave
  a neck thinner than `2*neck` mm (`letter_solid()`). Best spread (max of the minimum
  pairwise centroid distance) wins across `trials` attempts; falls back to smaller
  `--piece-scale` if nothing fits.
- **Random name placement**: `name_candidates()` tries random position/rotation
  (within `±max_rot`)/scale (70-100%) combinations, requiring every glyph island
  (including diacritic marks) to have ≥45% of its area on the letter and the whole
  name ≥70%; ranks candidates and returns the best few so the piece-layout search can
  try each until pieces fit well.
- **Polaroid frame (clip-free design)**: two glued parts in one color — `polaroid_base`
  has a shallow photo recess, `polaroid_front` is the outer frame minus the visible
  window. The frame's own top/bottom margins overlap the photo slightly (`OV_TOP`,
  `OV_BOT`) so no separate clip is needed. To swap the photo: push it up under the top
  margin (there's `PUSH` mm of slack) until the bottom edge clears the bottom margin,
  lift out; insert by reversing.
- **Wall mount (blind keyholes)**: `keyhole_cutter()` cuts a classic keyhole shape
  (circle + travel slot + circle) only from the back, stopping at `KEY_TOP` (4.5mm)
  which is less than the letter's total thickness — so the front face always stays
  solid above the cut and the holes are invisible and unreachable from the front. The
  letter slides down onto wall screws and is held by the narrower shaft above the
  screw-head circle. `find_keyholes()` looks for a symmetric pair at the same height,
  as high as possible, avoiding existing pockets; falls back to one centered hole if
  there's no room for a symmetric pair.
- **Stand mount**: `make_stand()` builds the stand's slot as the exact negative of the
  bottom `STAND_SLOT` mm (14mm) of the _entire_ assembled model (letter + every piece +
  detail + the name), using the `solids` list accumulated while building meshes. A
  collision check (3D boolean intersection, must be ~0 mm³) verifies the model placed
  upright in the slot doesn't collide with the stand. Pieces and the name are kept out
  of that bottom band via an `avoid` keep-out zone passed into both the piece-layout
  search and the name-placement search.
- **Per-part colors**: `COLORS` is a dict of named roles (not individual files), with
  sensible hex defaults; `--color ROLE=COLOR` (repeatable, parsed via
  `matplotlib.colors.to_rgba`) overrides any of them. Every exported mesh is colored
  and tagged with its role in `colors.txt` so a slicer can assign filament per object.
- **If OpenSCAD were available** this would be simpler, but the pipeline deliberately
  avoids it (not present in the sandbox) in favor of pure shapely (2D boolean ops) +
  trimesh/manifold3d (3D boolean ops + extrusion).

## `make_letter.py`

```python
#!/usr/bin/env python3
"""Baby birth keepsake generator: big initial letter with inlaid pieces + script name on top.

Pieces (weight, ruler, animal + heart, and clock + calendar OR a polaroid photo frame) are scattered
randomly over the letter, may overhang its edge, and sit in pockets cut where they overlap the letter.
Every part has its own colour: --color letter=#e8d5b0 --color heart=red ... (see COLORS / --list-colors).

python3 make_letter.py --name Natálie --animal bunny --date 11.12.2025 --time 09:05 \
    --weight "4100 g" --length "57 cm" --seed 7 --out out
Deps: pip install trimesh shapely manifold3d fonttools matplotlib numpy
Fonts (--letter-font / --name-font / --num-font): a .ttf/.otf path, an installed family (fc-list),
or a Google Fonts family name (downloaded from github.com/google/fonts into fonts/). Variable fonts get
instanced at the requested weight (--letter-weight / --name-weight / --num-weight).
"""
import argparse, math, os, random, subprocess, urllib.request
import numpy as np
import trimesh
from shapely.geometry import Point, Polygon, box, LineString, MultiPolygon
from shapely.ops import unary_union
from shapely import affinity
from matplotlib.textpath import TextPath
from matplotlib.font_manager import FontProperties

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIR = os.path.join(HERE, "fonts")
NUM_FONT = None  # set in main()
FC_WEIGHT = {100: 0, 200: 40, 300: 50, 400: 80, 500: 100, 600: 180, 700: 200, 800: 205, 900: 210}  # CSS -> fontconfig

# Every printable part has a colour role; override any of them with --color role=#hex|name.
COLORS = {
    "letter": "#ddc496", "name": "#f5f5f5", "heart": "#c83228",
    "animal": None,                      # None = the animal's own default (bear brown, bunny white, mouse grey)
    "animal_detail": "#f0bec3",          # inner ears, paws, nose (pink) / bear muzzle
    "animal_face": "#6e4128",            # eyes
    "weight": "#6e4128", "weight_text": "#f5f5f5",
    "ruler": "#6e4128", "ruler_text": "#f5f5f5",
    "clock": "#f5f5f5", "clock_text": "#6e4128",
    "calendar": "#6e4128", "calendar_text": "#f5f5f5",
    "polaroid": "#f5f5f5", "polaroid_text": "#6e4128",
    "stand": "#ddc496",
}
ANIMAL_DEFAULT = {"bear": "#6e4128", "bunny": "#f5f5f5", "mouse": "#afafb4"}


def _download_google_font(family, weight):
    """Fetch a family from github.com/google/fonts (raw files; tries the usual file-name patterns)."""
    slug, fname = family.lower().replace(" ", ""), family.replace(" ", "")
    style = {100: "Thin", 200: "ExtraLight", 300: "Light", 400: "Regular", 500: "Medium",
             600: "SemiBold", 700: "Bold", 800: "ExtraBold", 900: "Black"}.get(round(weight / 100) * 100, "Regular")
    names = [f"{fname}[wght].ttf", f"{fname}[wdth,wght].ttf", f"{fname}[opsz,wght].ttf",
             f"{fname}-{style}.ttf", f"{fname}-Regular.ttf", f"{fname}.ttf"]
    os.makedirs(FONT_DIR, exist_ok=True)
    for lic in ("ofl", "apache", "ufl"):
        for n in names:
            dst = os.path.join(FONT_DIR, n)
            if os.path.exists(dst): return dst
            url = f"https://raw.githubusercontent.com/google/fonts/main/{lic}/{slug}/" + n.replace("[", "%5B").replace("]", "%5D").replace(",", "%2C")
            try:
                with urllib.request.urlopen(url, timeout=20) as r: data = r.read()
            except Exception:
                continue
            open(dst, "wb").write(data)
            return dst
    return None


def resolve_font(spec, weight):
    """spec = file path | installed family | Google Fonts family. Returns a static TTF/OTF path at `weight`."""
    from fontTools.ttLib import TTFont
    path = None
    if os.path.isfile(spec):
        path = spec
    elif os.path.isfile(os.path.join(FONT_DIR, spec)):
        path = os.path.join(FONT_DIR, spec)
    else:
        try:
            out = subprocess.check_output(["fc-match", "-f", "%{family}|%{file}", f"{spec}:weight={FC_WEIGHT[min(900, max(100, round(weight / 100) * 100))]}"]).decode()
            fam, f = out.split("|", 1)
            if spec.lower().replace(" ", "") in fam.lower().replace(" ", ""):
                path = f
        except Exception:
            pass
        if path is None:
            path = _download_google_font(spec, weight)
    if path is None:
        raise SystemExit(f"Font '{spec}' not found (not a file, not installed, not on Google Fonts). Attach the .ttf.")
    tt = TTFont(path)
    if "fvar" in tt:
        axes = {ax.axisTag: ax for ax in tt["fvar"].axes}
        from fontTools.varLib.instancer import instantiateVariableFont
        loc = {}
        for tag, ax in axes.items():
            loc[tag] = min(max(weight, ax.minValue), ax.maxValue) if tag == "wght" else ax.defaultValue
        out = os.path.join(FONT_DIR, f"{os.path.splitext(os.path.basename(path))[0]}-w{int(loc.get('wght', 0))}.ttf")
        if not os.path.exists(out):
            os.makedirs(FONT_DIR, exist_ok=True)
            instantiateVariableFont(tt, loc).save(out)
        path = out
    return path


# ---------------- 2D helpers ----------------
def as_polys(g):
    return [p for p in (g.geoms if hasattr(g, "geoms") else [g]) if isinstance(p, Polygon) and not p.is_empty]


def text_poly(s, fontfile, fit_w=None, fit_h=None, size=100):
    """Text -> shapely geometry with real holes (even-odd nesting), centered at origin, fitted into fit_w x fit_h."""
    from fontTools.ttLib import TTFont
    cmap = TTFont(fontfile, lazy=True).getBestCmap()
    missing = [c for c in s if c != " " and ord(c) not in cmap]
    if missing:
        raise SystemExit(f"Font {os.path.basename(fontfile)} lacks glyphs: {missing}")
    tp = TextPath((0, 0), s, size=size, prop=FontProperties(fname=fontfile))
    rings = [Polygon(r).buffer(0) for r in tp.to_polygons() if len(r) >= 3]
    rings = [r for r in rings if not r.is_empty and r.area > 1e-6]
    # nesting depth decides fill (robust to fonts with inconsistent winding / overlapping contours)
    depth = [sum(1 for j, o in enumerate(rings) if j != i and o.area > r.area and o.contains(r.representative_point()))
             for i, r in enumerate(rings)]
    outers = unary_union([r for r, d in zip(rings, depth) if d % 2 == 0])
    holes = [r for r, d in zip(rings, depth) if d % 2 == 1]
    g = outers.difference(unary_union(holes)) if holes else outers
    minx, miny, maxx, maxy = g.bounds
    sc = 1.0
    if fit_w: sc = fit_w / (maxx - minx)
    if fit_h: sc = min(sc, fit_h / (maxy - miny)) if fit_w else fit_h / (maxy - miny)
    g = affinity.scale(g, sc, sc, origin=(0, 0))
    minx, miny, maxx, maxy = g.bounds
    return affinity.translate(g, -(minx + maxx) / 2, -(miny + maxy) / 2)


def rrect(w, h, r):
    return box(-w / 2 + r, -h / 2 + r, w / 2 - r, h / 2 - r).buffer(r, 32)


def ell(cx, cy, rx, ry, rot=0):
    e = affinity.rotate(affinity.scale(Point(0, 0).buffer(1, 64), rx, ry), rot, origin=(0, 0))
    return affinity.translate(e, cx, cy)


def circ(cx, cy, r):
    return Point(cx, cy).buffer(r, 48)


def heart(size):
    t = np.linspace(0, 2 * math.pi, 200)
    p = Polygon(np.c_[16 * np.sin(t) ** 3, 13 * np.cos(t) - 5 * np.cos(2 * t) - 2 * np.cos(3 * t) - np.cos(4 * t)]).buffer(0)
    minx, miny, maxx, maxy = p.bounds
    p = affinity.scale(p, size / (maxx - minx), size / (maxx - minx), origin=(0, 0))
    minx, miny, maxx, maxy = p.bounds
    return affinity.translate(p, -(minx + maxx) / 2, -(miny + maxy) / 2)


# ------------- pieces: (body shape, [(detail geometry, color)], accent heart offset or None) -------------
def piece_calendar(date):
    shape = unary_union([rrect(40, 36, 3)] + [affinity.translate(rrect(4, 9, 1.8), x, 19.5) for x in (-11, 0, 11)])
    d, m, y = (date.replace(" ", "").split(".") + ["", ""])[:3]
    det = unary_union([affinity.translate(text_poly(f"{d}.{m}.", NUM_FONT, fit_w=30, fit_h=10), 0, 5.5),
                       affinity.translate(text_poly(y, NUM_FONT, fit_w=26, fit_h=9), 0, -6.0),
                       box(-14, -15.2, 14, -13.8)]
                      + [affinity.translate(rrect(2.2, 5, 1), x, 19.5) for x in (-11, 0, 11)])
    return shape, [(det, "calendar_text")], None


def piece_clock(tm):
    shape = unary_union([circ(0, 0, 19)]
                        + [circ(math.cos(math.radians(a)) * 20, math.sin(math.radians(a)) * 20, 7) for a in (50, 130)]
                        + [LineString([(sx * 9, -16), (sx * 15, -28)]).buffer(2.2) for sx in (-1, 1)])
    return shape, [(text_poly(tm, NUM_FONT, fit_w=26, fit_h=9), "clock_text")], None


def piece_weight(weight):
    """Classic trapezoid weight with a ring handle; the baby's weight written on it (like the ruler)."""
    body = Polygon([(-20, -17), (20, -17), (14, 9), (-14, 9)]).buffer(2.5, 32).buffer(-1, 32)
    ring = circ(0, 15, 9).difference(circ(0, 15, 4.8))
    shape = unary_union([body, ring, box(-7, 6, 7, 10)])
    txt = text_poly(weight, NUM_FONT, fit_w=30, fit_h=9)
    return shape, [(affinity.translate(txt, 0, -4.5), "weight_text")], None


def piece_ruler(length):
    ticks = []
    for i in range(31):
        y = -28 + i * 1.8
        ln = 5 if i % 5 == 0 else 2.6
        ticks.append(box(8.2 - ln, y - 0.4, 8.2, y + 0.4))
    txt = affinity.rotate(text_poly(length, NUM_FONT, fit_w=34, fit_h=6), 90, origin=(0, 0))
    return rrect(18, 64, 2), [(unary_union(ticks + [affinity.translate(txt, -3.6, 0)]), "ruler_text")], None


def piece_bear():
    shape = unary_union([ell(0, -8, 17, 19), circ(0, 13, 14), circ(-11.5, 24, 6), circ(11.5, 24, 6),
                         ell(-19.5, -3, 6, 10.5, 25), ell(19.5, -3, 6, 10.5, -25),
                         ell(-11.5, -27, 8, 7), ell(11.5, -27, 8, 7)]).buffer(0.8).buffer(-0.8)
    det = unary_union([ell(0, 9, 6, 4.8), circ(-5.5, 16, 1.5), circ(5.5, 16, 1.5)])
    return shape, [(det, "animal_detail")], (0, -6)


def piece_bunny():
    shape = unary_union([ell(0, -12, 16, 17),                      # body
                         circ(0, 9, 11.5),                         # head
                         ell(-5.5, 29, 4.6, 13, 12), ell(5.5, 29, 4.6, 13, -12),   # ears
                         ell(-10, -27, 8.5, 4.5), ell(10, -27, 8.5, 4.5),         # feet
                         ell(-15, -8, 4.5, 8, 20), ell(15, -8, 4.5, 8, -20)        # arms
                         ]).buffer(0.8).buffer(-0.8)
    inner_ears = unary_union([ell(-5.8, 30, 2.2, 9, 12), ell(5.8, 30, 2.2, 9, -12)])
    face = unary_union([circ(-4.5, 11, 1.5), circ(4.5, 11, 1.5), ell(0, 6.5, 2.2, 1.6)])
    paws = unary_union([ell(-10, -27, 4.5, 2.4), ell(10, -27, 4.5, 2.4)])
    return shape, [(inner_ears, "animal_detail"), (face, "animal_face"), (paws, "animal_detail")], (0, -11)


def piece_mouse():
    shape = unary_union([ell(0, -12, 14, 16),                          # body
                         ell(0, 7, 12.5, 11),                          # head
                         circ(-12, 17, 8.5), circ(12, 17, 8.5),        # big round ears
                         ell(-9, -27, 7, 4), ell(9, -27, 7, 4),        # feet
                         ell(-13, -8, 4, 7, 25), ell(13, -8, 4, 7, -25),  # arms
                         LineString([(11, -20), (19, -22), (23, -16), (21, -9), (24, -4)]).buffer(1.6)  # tail
                         ]).buffer(0.8).buffer(-0.8)
    inner_ears = unary_union([circ(-12, 17.5, 5.5), circ(12, 17.5, 5.5)]).difference(ell(0, 7, 13, 11.5))
    face = unary_union([circ(-4.5, 8.5, 1.6), circ(4.5, 8.5, 1.6)])
    nose = unary_union([circ(0, 3, 1.8), ell(-8, -27, 3.8, 2), ell(8, -27, 3.8, 2)])
    return shape, [(inner_ears, "animal_detail"), (face, "animal_face"), (nose, "animal_detail")], (0, -11)


ANIMALS = {"bear": piece_bear, "bunny": piece_bunny, "mouse": piece_mouse}

# Polaroid (local, unscaled mm). Two parts in the same colour, glued together:
#   base  = plate with a shallow photo recess (photo lies flush),
#   front = frame on top whose margins overlap the photo: top margin OV_TOP, bottom margin OV_BOT, sides flush.
# Swap the photo: push it up under the top margin (slot has PUSH mm extra room) until its bottom edge clears the
# bottom margin, lay it down, let it slide down under the bottom margin. No clip, nothing else covers the photo.
PW, PH = 56, 68
SIDE_M, TOP_M, BOTTOM_M = 3.0, 7.5, 15.0          # visible frame margins (top/bottom = edge -> window)
OV_TOP, OV_BOT, PUSH, LAND = 4.0, 1.5, 2.2, 1.3    # photo overlaps, extra slide room, glue land above the slot
FRONT_T, RECESS = 1.2, 0.5                         # front frame thickness, photo recess depth in the base


def polaroid_parts():
    """Returns outer, window (visible photo), photo (actual photo size), recess (photo + slide room)."""
    outer = rrect(PW, PH, 2.5)
    wx = PW / 2 - SIDE_M
    win_top, win_bot = PH / 2 - TOP_M, -PH / 2 + BOTTOM_M
    window = box(-wx, win_bot, wx, win_top)
    photo = box(-wx, win_bot - OV_BOT, wx, win_top + OV_TOP)
    rec_top = win_top + OV_TOP + PUSH
    assert rec_top <= PH / 2 - LAND + 1e-6, "TOP_M too small for OV_TOP + PUSH + LAND"
    assert PUSH > OV_BOT + 0.5, "PUSH must exceed OV_BOT so the photo clears the bottom margin"
    recess = box(-wx - 0.2, win_bot - OV_BOT - 0.3, wx + 0.2, rec_top)
    return outer, window, photo, recess


def piece_polaroid(date, tm):
    outer = polaroid_parts()[0]
    txt = text_poly(f"{date}  {tm}", NUM_FONT, fit_w=PW - 12, fit_h=6)
    return outer, [(affinity.translate(txt, 0, -PH / 2 + BOTTOM_M / 2), "polaroid_text")], None


# ---------------- random layout ----------------
def pocket_area(L, bodies, tol):
    """Pocket footprint: each piece outline + clearance, inner holes filled (no loose letter islands)."""
    return unary_union([Polygon(q.exterior) for b in bodies for q in as_polys(b.buffer(tol, 32))]).intersection(L)


def letter_solid(L, bodies, tol, neck=1.5):
    """True if the letter minus pockets stays one piece with no neck thinner than 2*neck mm."""
    return len(as_polys(L.difference(pocket_area(L, bodies, tol)).buffer(-neck))) == 1


def random_layout(L, name, bodies, rng, scale, min_overlap, max_rot, gap, trials, tol=0.15, avoid=None):
    """Throw pieces randomly; each must overlap the letter >= min_overlap of its area, keep gap to each other
    and to the name, and the letter must stay one solid piece after cutting pockets. Best spread wins."""
    minx, miny, maxx, maxy = L.bounds
    keepout = name.buffer(gap + 1)
    if avoid is not None: keepout = keepout.union(avoid)
    order = sorted(bodies, key=lambda k: -bodies[k].area)
    best = None
    for _ in range(trials):
        placed, ok = {}, True
        for k in order:
            for _try in range(400):
                rot = rng.uniform(-max_rot, max_rot)
                g = affinity.rotate(affinity.scale(bodies[k], scale, scale, origin=(0, 0)), rot, origin=(0, 0))
                x, y = rng.uniform(minx - 10, maxx + 10), rng.uniform(miny, maxy + 10)
                c = affinity.translate(g, x, y)
                ov = c.intersection(L).area / c.area
                if ov < min_overlap: continue
                if c.intersects(keepout): continue
                if any(c.distance(p[0]) < gap for p in placed.values()): continue
                placed[k] = (c, rot, x, y)
                break
            else:
                ok = False
                break
        if not ok: continue
        if not letter_solid(L, [p[0] for p in placed.values()], tol): continue   # pockets must not split the letter
        cs = [p[0].centroid for p in placed.values()]
        spread = min(a.distance(b) for i, a in enumerate(cs) for b in cs[i + 1:])
        if best is None or spread > best[0]: best = (spread, placed)
    return best[1] if best else None


def ex(poly, h, z=0.0):
    ms = [trimesh.creation.extrude_polygon(g, h) for g in as_polys(poly) if g.area > 1e-3]
    m = trimesh.util.concatenate(ms)
    m.apply_translation([0, 0, z])
    return m


def draw(ax, g, fc, ec="none", lw=0.0):
    from matplotlib.path import Path
    from matplotlib.patches import PathPatch
    for p in as_polys(g):
        verts, codes = [], []
        for ring in [p.exterior] + list(p.interiors):
            xy = np.asarray(ring.coords)
            verts += xy.tolist(); codes += [Path.MOVETO] + [Path.LINETO] * (len(xy) - 2) + [Path.CLOSEPOLY]
        ax.add_patch(PathPatch(Path(verts, codes), fc=fc, ec=ec, lw=lw))


# ---------------- name placement ----------------
def name_support(name, L):
    """(worst island share on the letter, total share on the letter)"""
    isl = as_polys(name)
    return min(i.intersection(L).area / i.area for i in isl), name.intersection(L).area / name.area


def place_name_bottom(name, L):
    minx, miny, maxx, maxy = L.bounds
    name = affinity.translate(name, (minx + maxx) / 2 - name.centroid.x, 0)
    for dy in np.arange(miny + 25, miny + 0.45 * (maxy - miny), 2):
        cand = affinity.translate(name, 0, dy - name.centroid.y)
        if name_support(cand, L)[0] > 0.35:
            return cand
    return affinity.translate(name, 0, miny + 30 - name.centroid.y)


def name_candidates(name_full, L, rng, max_rot, n=8, avoid=None):
    """Random pose for the name: rotation within +-max_rot (never upside down), size 70-100 % of the bottom-placement
    width, anywhere on the letter; every island (incl. accents) must sit at least 45 % on the letter."""
    minx, miny, maxx, maxy = L.bounds
    found = []
    for _ in range(6000):
        rot = rng.uniform(-max_rot, max_rot)
        sc = rng.uniform(0.7, 1.0)
        g = affinity.rotate(affinity.scale(name_full, sc, sc, origin="centroid"), rot, origin="centroid")
        c = g.centroid
        g = affinity.translate(g, rng.uniform(minx, maxx) - c.x, rng.uniform(miny, maxy) - c.y)
        if avoid is not None and g.intersects(avoid): continue
        worst, total = name_support(g, L)
        if worst < 0.45 or total < 0.7: continue
        found.append((sc + 0.3 * total + rng.uniform(0, 0.15), g))
        if len(found) >= 4 * n: break
    found.sort(key=lambda t: -t[0])
    return [g for _, g in found[:n]]


# ---------------- mounting ----------------
KEY_HEAD_R, KEY_SHAFT_W, KEY_TRAVEL, KEY_FLOOR, KEY_TOP = 4.75, 4.5, 10.0, 1.8, 4.5   # keyhole for a screw head <= 9 mm


def keyhole_footprint(x, y):
    return unary_union([circ(x, y, KEY_HEAD_R), box(x - KEY_HEAD_R, y, x + KEY_HEAD_R, y + KEY_TRAVEL),
                        circ(x, y + KEY_TRAVEL, KEY_HEAD_R)])


def find_keyholes(L, pockets, wall=2.5):
    """Up to two keyholes at the same height, as high as possible, straddling the letter's centroid,
    only where the letter is solid (keyhole channel reaches z=KEY_TOP, pockets start at --base)."""
    forbidden = pockets.buffer(1.5)
    cx = L.centroid.x
    minx, miny, maxx, maxy = L.bounds
    ok = lambda x, y: L.contains(keyhole_footprint(x, y).buffer(wall)) and not keyhole_footprint(x, y).intersects(forbidden)
    single = None
    for y in np.arange(maxy - KEY_TRAVEL - KEY_HEAD_R - wall, L.centroid.y, -2.0):
        xs = [x for x in np.arange(minx, maxx, 2.0) if ok(x, y)]
        left, right = [x for x in xs if x < cx - 12], [x for x in xs if x > cx + 12]
        pairs = [(abs((l + r) / 2 - cx), l, r) for l in left for r in right if r - l >= 30]
        good = [p for p in pairs if p[0] < 12]
        if good:
            _, l, r = min(good, key=lambda t: t[0] - 0.01 * (t[2] - t[1]))
            return [(l, y), (r, y)]
        if single is None:
            near = [x for x in xs if abs(x - cx) < 10]
            if near: single = [(min(near, key=lambda x: abs(x - cx)), y)]
    return single or []


def keyhole_cutter(x, y):
    parts = [trimesh.creation.cylinder(radius=KEY_HEAD_R, height=KEY_TOP + 1, sections=48).apply_translation([x, y, (KEY_TOP - 1) / 2])]
    shaft = unary_union([box(x - KEY_SHAFT_W / 2, y, x + KEY_SHAFT_W / 2, y + KEY_TRAVEL), circ(x, y + KEY_TRAVEL, KEY_SHAFT_W / 2)])
    parts.append(ex(shaft, KEY_FLOOR + 1, -1))
    parts.append(ex(keyhole_footprint(x, y), KEY_TOP - KEY_FLOOR, KEY_FLOOR))
    return trimesh.boolean.union(parts, engine="manifold")


STAND_DEPTH, STAND_SLOT, STAND_FLOOR, STAND_MARGIN = 55.0, 14.0, 4.0, 14.0


def make_stand(solids, L, tol):
    """Stand block with a slot that is the exact negative of the bottom STAND_SLOT mm of the model
    (letter + pieces + details + name), so the letter slides in and stands. Stand frame: X = letter x,
    Y = depth (front = -Y), Z = up; the letter's lowest point rests on the slot floor."""
    minx, miny, maxx, maxy = L.bounds
    ycut = miny + STAND_SLOT
    region = box(minx - 50, miny - 1, maxx + 50, ycut + 10)
    cutters, xs = [], []
    for poly, z0, z1 in solids:
        g = poly.intersection(region)
        if g.is_empty or g.area < 1: continue
        g = g.buffer(tol, 16)
        xs += [g.bounds[0], g.bounds[2]]
        m = ex(g, (z1 - z0) + 2 * tol, 0)
        M = np.array([[1, 0, 0, 0], [0, 0, -1, -(z0 - tol)], [0, 1, 0, STAND_FLOOR - miny], [0, 0, 0, 1]], float)
        m.apply_transform(M)
        cutters.append(m)
    top_z = max(z1 for _, _, z1 in solids)
    sx0, sx1 = min(xs) - STAND_MARGIN, max(xs) + STAND_MARGIN
    yc = -top_z / 2
    block = ex(rrect(sx1 - sx0, STAND_DEPTH, 6), STAND_FLOOR + STAND_SLOT, 0)
    block.apply_translation([(sx0 + sx1) / 2, yc, 0])
    stand = trimesh.boolean.difference([block, trimesh.boolean.union(cutters, engine="manifold")], engine="manifold")
    return stand, (sx1 - sx0, STAND_DEPTH, STAND_FLOOR + STAND_SLOT)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="Natálie")
    ap.add_argument("--initial", default=None, help="defaults to first letter of name")
    ap.add_argument("--animal", default="bunny", choices=list(ANIMALS))
    ap.add_argument("--layout", default="classic", choices=["classic", "polaroid"],
                    help="classic = clock + calendar; polaroid = photo frame with date + time instead of them")
    ap.add_argument("--date", default="11.12.2025")
    ap.add_argument("--time", default="09:05")
    ap.add_argument("--weight", default="4100 g")
    ap.add_argument("--length", default="57 cm")
    ap.add_argument("--height", type=float, default=170, help="letter height mm")
    ap.add_argument("--letter-font", default="Nunito", help="big letter font: path | installed family | Google Fonts name")
    ap.add_argument("--letter-weight", "--font-weight", type=int, default=800, help="letter weight 100-1000 (lower = thinner)")
    ap.add_argument("--name-font", default="Pacifico", help="script font for the name")
    ap.add_argument("--name-weight", type=int, default=400)
    ap.add_argument("--name-min-stroke", type=float, default=1.6, help="min stroke width of the name in mm (thin fonts get thickened)")
    ap.add_argument("--num-font", default="Liberation Sans", help="font for date/time/weight/length")
    ap.add_argument("--num-weight", type=int, default=700)
    ap.add_argument("--fatten", type=float, default=4, help="extra mm added around the glyph")
    ap.add_argument("--piece-scale", type=float, default=0.95)
    ap.add_argument("--min-overlap", type=float, default=0.55, help="min share of each piece lying on the letter")
    ap.add_argument("--max-rot", type=float, default=18, help="random rotation range in degrees")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--thick", type=float, default=3.0, help="piece thickness = pocket depth")
    ap.add_argument("--base", type=float, default=3.0, help="floor under pockets")
    ap.add_argument("--tol", type=float, default=0.15, help="pocket clearance per side")
    ap.add_argument("--color", action="append", default=[], metavar="ROLE=COLOR",
                    help="part colour, repeatable, e.g. --color letter=#f3e5c8 --color heart=red; roles: " + ", ".join(COLORS))
    ap.add_argument("--name-placement", default="random", choices=["random", "bottom"],
                    help="random = anywhere on the letter, rotated within +-name-max-rot; bottom = horizontal at the bottom")
    ap.add_argument("--name-max-rot", type=float, default=35)
    ap.add_argument("--mount", default="wall", choices=["wall", "stand", "both", "none"],
                    help="wall = keyholes in the back; stand = separate stand with a slot shaped like the letter's bottom")
    ap.add_argument("--out", default="out")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    from matplotlib.colors import to_rgba
    cols = dict(COLORS, animal=ANIMAL_DEFAULT[a.animal])
    for c in a.color:
        role, _, val = c.partition("=")
        if role not in cols: raise SystemExit(f"unknown colour role '{role}'; use one of: {', '.join(cols)}")
        cols[role] = val
    rgba = {r: [int(round(x * 255)) for x in to_rgba(v)] for r, v in cols.items()}
    rng = random.Random(a.seed)
    top = a.base + a.thick
    global NUM_FONT
    letter_ttf = resolve_font(a.letter_font, a.letter_weight)
    name_ttf = resolve_font(a.name_font, a.name_weight)
    NUM_FONT = resolve_font(a.num_font, a.num_weight)
    print("fonts:", *(os.path.basename(p) for p in (letter_ttf, name_ttf, NUM_FONT)))

    # ---- big letter (outer shape with its counters kept open)
    G = text_poly((a.initial or a.name[0]).upper(), letter_ttf, fit_h=a.height)
    L = G.buffer(a.fatten, 48) if a.fatten else G
    L = max(as_polys(L), key=lambda g: g.area)
    minx, miny, maxx, maxy = L.bounds
    Lw = maxx - minx

    # ---- name on top, lowered until every island (incl. accents) is well supported by the letter
    name = text_poly(a.name, name_ttf, fit_w=max(Lw * 1.05, 120)).buffer(0.3).buffer(-0.1)
    # thin script fonts: grow strokes until (almost) nothing disappears when eroded by half the min stroke
    r = a.name_min_stroke / 2
    grow = 0.0
    def too_thin(g):  # a stroke thinner than min_stroke breaks apart / vanishes when eroded by half of it
        return len(as_polys(g.buffer(-r))) > len(as_polys(g)) or g.difference(g.buffer(-r).buffer(r)).area > 5
    while too_thin(name) and grow < 1.2:
        grow += 0.1
        name = name.buffer(0.1, 16)
    if grow: print(f"  name strokes thickened by {grow:.1f} mm per side (min stroke {a.name_min_stroke} mm)")
    # with a stand the bottom STAND_SLOT mm disappear in the slot: keep name and pieces out of that band
    avoid = box(minx - 60, miny - 60, maxx + 60, miny + STAND_SLOT + 3) if a.mount in ("stand", "both") else None
    name_bottom = place_name_bottom(name, L)
    if avoid is not None and name_bottom.intersects(avoid):
        name_bottom = affinity.translate(name_bottom, 0, miny + STAND_SLOT + 3.5 - name_bottom.bounds[1])
    if a.name_placement == "random":
        name_options = name_candidates(name_bottom, L, rng, a.name_max_rot, avoid=avoid) or [name_bottom]
    else:
        name_options = [name_bottom]

    # ---- pieces
    defs = {"animal": ANIMALS[a.animal](), "weight": piece_weight(a.weight), "ruler": piece_ruler(a.length)}
    if a.layout == "polaroid":
        defs["polaroid"] = piece_polaroid(a.date, a.time)
    else:
        defs.update(clock=piece_clock(a.time), calendar=piece_calendar(a.date))
    attempt = None
    for name_try in name_options:                       # first name pose whose pieces still fit near full size
        placed, scale = None, a.piece_scale
        while placed is None and scale >= 0.6:
            placed = random_layout(L, name_try, {k: v[0] for k, v in defs.items()}, rng, scale, a.min_overlap, a.max_rot, 2.0, 40, a.tol, avoid)
            if placed is None: scale -= 0.05
        if placed is not None and (attempt is None or scale > attempt[2]):
            attempt = (name_try, placed, scale)
        if attempt and attempt[2] >= a.piece_scale - 0.1: break
    if attempt is None:
        raise SystemExit("Pieces do not fit - raise --height / --fatten or lower --min-overlap")
    name, placed, scale = attempt
    name_islands_ok = name_support(name, L)[0] > 0.2

    def tf(g, k):
        _, rot, x, y = placed[k]
        return affinity.translate(affinity.rotate(affinity.scale(g, scale, scale, origin=(0, 0)), rot, origin=(0, 0)), x, y)

    P = {}
    for k, (shape, dets, hoff) in defs.items():
        body = tf(shape, k)
        dl = [(tf(d, k).intersection(body.buffer(-0.4)), c) for d, c in dets]
        if hoff: dl.append((tf(affinity.translate(heart(11), *hoff), k), "heart"))
        merged = {}                                   # one geometry per colour role
        for d, role in dl: merged[role] = unary_union([merged[role], d]) if role in merged else d
        dl = [(g, r) for r, g in merged.items()]
        P[k] = (body, dl)

    pockets = pocket_area(L, [b for b, _ in P.values()], a.tol)
    rest = L.difference(pockets)
    print(f"letter {Lw:.0f}x{maxy - miny:.0f} mm, piece scale {scale:.2f}, seed {a.seed}")
    for k, (b, _) in P.items():
        print(f"  {k:9s} on letter {b.intersection(L).area / b.area:.0%}")
    print("  pieces gap >= 2 mm:", all(P[i][0].distance(P[j][0]) >= 2 - 1e-6 for i in P for j in P if i < j))
    print("  letter stays one piece:", letter_solid(L, [b for b, _ in P.values()], a.tol))
    print("  every name island glued on letter:", name_islands_ok)
    print("  name keeps counters (holes):", sum(len(p.interiors) for p in as_polys(name)))
    if "polaroid" in P:
        _, win0, photo0, _ = polaroid_parts()
        pw_, ph_ = photo0.bounds[2] - photo0.bounds[0], photo0.bounds[3] - photo0.bounds[1]
        print(f"  PHOTO: cut to {pw_ * scale:.0f} x {ph_ * scale:.0f} mm (visible {(win0.bounds[2] - win0.bounds[0]) * scale:.0f} x "
              f"{(win0.bounds[3] - win0.bounds[1]) * scale:.0f} mm), max {RECESS - 0.05:.2f} mm thick")

    cut = [ex(pockets, a.thick + 1, z=a.base)]
    keys = []
    if a.mount in ("wall", "both"):
        keys = find_keyholes(L, pockets)
        cut += [keyhole_cutter(x, y) for x, y in keys]
        print(f"  wall keyholes: {len(keys)} " + " ".join(f"({x - minx:.0f},{y - miny:.0f})mm" for x, y in keys)
              + (f", spacing {keys[1][0] - keys[0][0]:.0f} mm" if len(keys) == 2 else "") + ("  WARNING: no room for a keyhole" if not keys else ""))
    base_m = trimesh.boolean.difference([ex(L, top)] + cut, engine="manifold")
    meshes = {"letter": (base_m, "letter")}
    solids = [(L, 0.0, top)]
    photo_window = photo_outline = None
    for k, (b, dl) in P.items():
        if k == "polaroid":
            outer0, win0, photo0, rec0 = polaroid_parts()
            base_t = a.thick - FRONT_T
            base = trimesh.boolean.difference([ex(b, base_t, a.base), ex(tf(rec0, k), RECESS + 1, a.base + base_t - RECESS)], engine="manifold")
            meshes["polaroid_base"] = (base, "polaroid")
            meshes["polaroid_front"] = (ex(b.difference(tf(win0, k)), FRONT_T, a.base + base_t), "polaroid")
            photo_window, photo_outline = tf(win0, k), tf(photo0, k)
        else:
            meshes[k] = (ex(b, a.thick, a.base), k)
        solids.append((b, a.base, top))
        for d, role in dl:
            if not d.is_empty:
                meshes[role if role.startswith(k) or role == "heart" else f"{k}_{role}"] = (ex(d, 1.0, top), role)
                solids.append((d, top, top + 1.0))
    meshes["name"] = (ex(name, 2.5, top), "name")
    solids.append((name, top, top + 2.5))
    stand = stand_in_place = None
    if a.mount in ("stand", "both"):
        stand, sdim = make_stand(solids, L, a.tol + 0.1)
        # fit check: whole model placed upright in the stand must not collide with it
        Mst = np.array([[1, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, STAND_FLOOR - miny], [0, 0, 0, 1]], float)
        coll = 0.0
        for n, (mm, _) in meshes.items():
            q = mm.copy(); q.apply_transform(Mst)
            hit = trimesh.boolean.intersection([q, stand], engine="manifold")
            coll += 0 if hit.is_empty else hit.volume
        print(f"  stand: {sdim[0]:.0f} x {sdim[1]:.0f} x {sdim[2]:.0f} mm, slot {STAND_SLOT:.0f} mm deep, collision with model {coll:.2f} mm3")
        stand_in_place = (stand, Mst)

    scene = trimesh.Scene()
    bad = []
    legend = []
    for n, (m, role) in meshes.items():
        m.visual.face_colors = rgba[role]
        scene.add_geometry(m, node_name=n, geom_name=n)
        pm = m.copy(); pm.apply_translation(-pm.bounds[0])
        pm.export(os.path.join(a.out, f"{n}.stl"))
        legend.append(f"{n}.stl\t{role}\t{cols[role]}")
        if not m.is_watertight: bad.append(n)
    scene.export(os.path.join(a.out, "assembled.3mf"))
    if stand is not None:
        sm = stand.copy(); sm.apply_translation(-sm.bounds[0]); sm.export(os.path.join(a.out, "stand.stl"))
        legend.append(f"stand.stl\tstand\t{cols['stand']}")
        if not stand.is_watertight: bad.append("stand")
    open(os.path.join(a.out, "colors.txt"), "w").write("file\trole\tcolor\n" + "\n".join(legend) + "\n")
    print(f"  {len(meshes)} STL written (colours in colors.txt), non-watertight: {bad or 'none'}")

    # ---- render data: model standing upright (front = -Y), stand in place, for 3D renders (render_views.js)
    import json
    Mup = np.array([[1, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, STAND_FLOOR - miny], [0, 0, 0, 1]], float)
    rd = []
    for n, (mm, role) in list(meshes.items()) + ([("stand", (stand, "stand"))] if stand is not None else []):
        q = mm.copy()
        if n != "stand": q.apply_transform(Mup)
        rd.append({"name": n, "color": cols[role], "pos": q.vertices.round(3).ravel().tolist(), "idx": q.faces.ravel().tolist()})
    json.dump({"meshes": rd, "stand": stand is not None}, open(os.path.join(a.out, "render_scene.json"), "w"))

    # ---- preview
    import matplotlib; matplotlib.use("Agg"); import matplotlib.patches
    import matplotlib.pyplot as plt
    col = lambda role: tuple(x / 255 for x in rgba[role])
    fig, ax = plt.subplots(figsize=(8, 8))
    draw(ax, L, col("letter"))
    draw(ax, pockets, tuple(0.85 * x for x in col("letter")[:3]))
    for k, (b, dl) in P.items():
        draw(ax, b, col(k), "#6b5a45", 0.4)
        if k == "polaroid":   # photo shown only as a hint: dashed = photo edge, the frame margins overlap it
            xs_, ys_ = photo_outline.exterior.xy
            ax.plot(xs_, ys_, ls="--", lw=0.7, color="#8aa0b8")
            draw(ax, photo_window, "#dfe6ee")
            ax.text(photo_window.centroid.x, photo_window.centroid.y, "fotka", ha="center", va="center", color="#8aa0b8", fontsize=11)
        for d, role in dl: draw(ax, d, col(role))
    draw(ax, name, col("name"), "#8a8a8a", 0.5)
    if stand is not None:
        sb = stand.bounds
        ax.add_patch(matplotlib.patches.FancyBboxPatch((sb[0][0], L.bounds[1] - STAND_FLOOR), sb[1][0] - sb[0][0], sb[1][2],
                     boxstyle="round,pad=0,rounding_size=3", fc=col("stand"), ec="#6b5a45", lw=0.6, alpha=0.55, zorder=5))
    ax.autoscale_view(); ax.set_aspect("equal"); ax.axis("off"); fig.patch.set_facecolor("#e9e3d9")
    fig.savefig(os.path.join(a.out, "preview.png"), dpi=130, bbox_inches="tight", facecolor=fig.get_facecolor())


if __name__ == "__main__":
    main()
```

## `render_views.js`

```javascript
// usage: node render_views.js <render_scene.json> <out_prefix>
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");
(async () => {
  const [, , scenePath, outPrefix] = process.argv;
  const data = JSON.parse(fs.readFileSync(scenePath, "utf8"));
  const browser = await chromium.launch({
    args: [
      "--use-gl=angle",
      "--use-angle=swiftshader",
      "--enable-unsafe-swiftshader",
    ],
  });
  const page = await browser.newPage({
    viewport: { width: 900, height: 900 },
    deviceScaleFactor: 1,
  });
  await page.setContent(
    '<html><body style="margin:0;background:#ece6dc"><canvas id="c" width="900" height="900"></canvas></body></html>',
  );
  await page.addScriptTag({
    path: path.join(__dirname, "node_modules/three/build/three.min.js"),
  });
  const views = [
    ["front", [-0.55, -1.0, 0.45]],
    ["back", [0.45, 1.0, 0.25]],
  ];
  for (const [vname, dir] of views) {
    const png = await page.evaluate(
      ({ data, dir }) => {
        const T = THREE;
        const r = new T.WebGLRenderer({
          canvas: document.getElementById("c"),
          antialias: true,
          preserveDrawingBuffer: true,
        });
        r.setClearColor(0xece6dc);
        const scene = new T.Scene();
        const box = new T.Box3();
        for (const m of data.meshes) {
          const g = new T.BufferGeometry();
          g.setAttribute("position", new T.Float32BufferAttribute(m.pos, 3));
          g.setIndex(m.idx);
          const gf = g.toNonIndexed();
          gf.computeVertexNormals();
          const mat = new T.MeshStandardMaterial({
            color: new T.Color(m.color),
            roughness: 0.8,
            metalness: 0.0,
            flatShading: true,
          });
          const mesh = new T.Mesh(gf, mat);
          scene.add(mesh);
          box.expandByObject(mesh);
          const e = new T.LineSegments(
            new T.EdgesGeometry(g, 50),
            new T.LineBasicMaterial({
              color: 0x000000,
              transparent: true,
              opacity: 0.12,
            }),
          );
          scene.add(e);
        }
        const c = box.getCenter(new T.Vector3());
        const sz = box.getSize(new T.Vector3()).length();
        const cam = new T.PerspectiveCamera(30, 1, 1, 5000);
        const d = new T.Vector3(...dir).normalize();
        cam.position.copy(c).addScaledVector(d, sz * 1.75);
        cam.up.set(0, 0, 1);
        cam.lookAt(c);
        scene.add(new T.HemisphereLight(0xffffff, 0x8a7a66, 1.6));
        const dl = new T.DirectionalLight(0xffffff, 1.6);
        dl.position.copy(c).add(new T.Vector3(-1, -2, 3).multiplyScalar(sz));
        scene.add(dl);
        const dl2 = new T.DirectionalLight(0xffffff, 0.5);
        dl2.position.copy(c).add(new T.Vector3(2, 1, 1).multiplyScalar(sz));
        scene.add(dl2);
        r.render(scene, cam);
        return document.getElementById("c").toDataURL("image/png");
      },
      { data, dir },
    );
    fs.writeFileSync(
      `${outPrefix}_${vname}.png`,
      Buffer.from(png.split(",")[1], "base64"),
    );
  }
  await browser.close();
})();
```
