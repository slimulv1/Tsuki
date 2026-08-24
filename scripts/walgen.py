#!/usr/bin/env python3
"""walgen.py v3 - wallpaper-only color engine for the GNUstep/WM theme chain.

Extracts the 16-color pywal cache (+ chrome accent) using ONLY colors that
actually exist in the wallpaper image - no preset hues, no invented axes.

v3 fixes (vs v2):
  * Two-pass sampling: flat/minimal art (<=8 distinct colors) is sampled with
    NEAREST so two-color images keep their exact colors; LANCZOS blends between
    regions (which used to invent phantom hues like purple in navy+cyan or
    red-brown in black+khaki) are avoided entirely. Photos still use LANCZOS.
  * Adaptive k-means: k = number of distinct colors for minimal images, so a
    2-color wallpaper gets exactly 2 clusters, never over-segmented phantoms.
  * Population floor on hue anchors: tiny resampling-artifact clusters can no
    longer claim an ANSI slot.
  * Neutral backgrounds never invent tints: a near-black dominant cluster keeps
    pure gray instead of being forced to s=0.15 at a meaningless hue 0 (the
    old "black wallpaper -> red tint" bug).
  * Neutral palettes are derived from the image's own luminance percentiles
    instead of a fixed ramp, so white, black and gray wallpapers each get an
    honest, distinct ramp.
  * Auto light/dark: bright, low-chroma wallpapers (white minimalism) produce
    a light scheme.
  * Stale-cache cleanup: when the wallpaper changes, old cache files are
    removed before the new colors are written.
  * Deterministic: the same image always yields the byte-identical 16-color
    palette. k-means uses a fixed seed (KMEANS_SEED below); every sort is a
    stable sort; there is no wall-clock / entropy / iteration-order input
    anywhere in the pipeline. Verify with:
      walgen.py img --cache-dir /tmp/a && walgen.py img --cache-dir /tmp/b
      diff /tmp/a/colors /tmp/b/colors   # must be empty

Writes byte-exact pywal cache files so every downstream script (wmwal.sh,
dunstwal.sh, conkywal.sh, kittywal.sh, xtermwal.sh, set-icon-theme.sh,
update-opencode-theme.sh) keeps working unchanged:

    ~/.cache/wal/colors     (16 lines: color0..color15)
    ~/.cache/wal/colors.sh  (shell vars: background/foreground/cursor + color0..15)
    ~/.cache/wal/colors.json
    ~/.cache/wal/wal        (path of the wallpaper)
    ~/.cache/wal/accents    (accent / accent_dim for WM/dunst/conky chrome)

Guaranteed error-free: any failure (bad image, missing numpy, weird mode,
grayscale/solid image) degrades to a safe neutral palette and exits 0.

Usage: walgen.py <image> [--light] [--cache-dir DIR]
"""

import argparse
import hashlib
import json
import os
import sys

try:
    import numpy as np
    _HAS_NUMPY = True
except Exception:
    np = None
    _HAS_NUMPY = False

try:
    from PIL import Image, ImageOps
except Exception:
    sys.stderr.write("walgen: Pillow is required\n")
    sys.exit(1)

# ---------------------------------------------------------------------------
# Perceptual color math (CIELAB via sRGB linearization)
# ---------------------------------------------------------------------------

def _lin(c):
    """Vectorized sRGB -> linear."""
    return np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)


def rgb_to_lab(rgb):
    """rgb: (N,3) float array in [0,1]. Returns (N,3) CIELAB."""
    r, g, b = _lin(rgb[:, 0]), _lin(rgb[:, 1]), _lin(rgb[:, 2])
    x = 0.4124 * r + 0.3576 * g + 0.1805 * b
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = 0.0193 * r + 0.1192 * g + 0.9505 * b

    def f(t):
        d = 6.0 / 29.0
        return np.where(t > d ** 3, t ** (1.0 / 3.0), t / (3 * d * d) + 4.0 / 29.0)

    L = 116.0 * f(y) - 16.0
    a = 500.0 * (f(x / 0.95047) - f(y))
    b = 200.0 * (f(y) - f(z / 1.08883))
    return np.stack([L, a, b], axis=1)


def lab_to_rgb(lab):
    """lab: (N,3) float array. Returns (N,3) uint8 array."""
    L, a, b = lab[:, 0], lab[:, 1], lab[:, 2]
    d = 6.0 / 29.0
    fy = (L + 16.0) / 116.0
    fx = fy + a / 500.0
    fz = fy - b / 200.0

    def finv(t):
        return np.where(t > d, t ** 3, 3 * d * d * (t - 4.0 / 29.0))

    x = finv(fx) * 0.95047
    y = finv(fy)
    z = finv(fz) * 1.08883
    rr = 3.2406 * x - 1.5372 * y - 0.4986 * z
    gg = -0.9689 * x + 1.8758 * y + 0.0415 * z
    bb = 0.0557 * x - 0.2040 * y + 1.0570 * z

    def srgb(c):
        out = np.where(c <= 0.0031308, 12.92 * c, 1.055 * np.abs(c) ** (1.0 / 2.4) - 0.055)
        return np.clip(out, 0.0, 1.0)

    out = np.stack([srgb(rr), srgb(gg), srgb(bb)], axis=1)
    return (out * 255.0 + 0.5).astype(np.uint8)


def rgb_to_hsl(rgb):
    """rgb: (N,3) float [0,1]. Returns (N,3) hue[0,360], lightness, saturation."""
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    mx = rgb.max(axis=1)
    mn = rgb.min(axis=1)
    l = (mx + mn) / 2.0
    delta = mx - mn
    sat = np.zeros_like(l)
    nz = delta > 0
    sat[nz] = delta[nz] / (1.0 - np.abs(2.0 * l[nz] - 1.0) + 1e-12)
    h = np.zeros_like(l)
    h[nz] = np.where(
        mx[nz] == r[nz],
        60.0 * (((g[nz] - b[nz]) / delta[nz]) % 6.0),
        np.where(
            mx[nz] == g[nz],
            60.0 * ((b[nz] - r[nz]) / delta[nz] + 2.0),
            60.0 * ((r[nz] - g[nz]) / delta[nz] + 4.0),
        ),
    )
    h = h % 360.0
    return np.stack([h, l, sat], axis=1)


def hsl_to_rgb(hsl):
    """hsl: (N,3) hue[0,360], lightness, saturation. Returns (N,3) uint8."""
    h, l, s = hsl[:, 0], np.clip(hsl[:, 1], 0, 1), np.clip(hsl[:, 2], 0, 1)
    c = (1.0 - np.abs(2.0 * l - 1.0)) * s
    hp = h / 60.0
    x = c * (1.0 - np.abs(hp % 2.0 - 1.0))
    z = np.zeros_like(h)
    r = np.select(
        [hp < 1, hp < 2, hp < 3, hp < 4, hp < 5, hp < 6],
        [c, x, z, z, x, c],
        default=z,
    )
    g = np.select(
        [hp < 1, hp < 2, hp < 3, hp < 4, hp < 5, hp < 6],
        [x, c, c, x, z, z],
        default=z,
    )
    b = np.select(
        [hp < 1, hp < 2, hp < 3, hp < 4, hp < 5, hp < 6],
        [z, z, x, c, c, x],
        default=z,
    )
    m = l - 0.5 * c
    out = np.stack([r + m, g + m, b + m], axis=1)
    return (np.clip(out, 0, 1) * 255.0 + 0.5).astype(np.uint8)


def _hex(c):
    return "#%02x%02x%02x" % (int(c[0]), int(c[1]), int(c[2]))


# ---------------------------------------------------------------------------
# Clustering: k-means++ (Lloyd refinement) in chroma-boosted CIELAB
# ---------------------------------------------------------------------------

CHROMA_BOOST = 1.7  # bias cluster separation toward hue/chroma, not lightness
KMEANS_SEED = 7     # fixed seed: same image -> byte-identical palette every run


def kmeans_pp(points, weights, k, iters=15, seed=KMEANS_SEED):
    """Weighted k-means++ in a vectorized way. Never raises on k > n."""
    n = len(points)
    k = max(1, min(k, n))
    rng = np.random.default_rng(seed)
    wsum = weights.sum()
    if wsum <= 0:
        weights = np.ones_like(weights, dtype=np.float64)
        wsum = weights.sum()
    centers = np.empty((k, 3))
    centers[0] = points[rng.choice(n, p=weights / wsum)]
    for c in range(1, k):
        d2 = np.min(((points - centers[:c, None, :]) ** 2).sum(axis=2), axis=0)
        probs = d2 * weights
        s = probs.sum()
        if s <= 0:
            centers[c] = points[rng.integers(n)]
        else:
            centers[c] = points[rng.choice(n, p=probs / s)]
    for _ in range(iters):
        dists = ((points - centers[:, None, :]) ** 2).sum(axis=2)
        assign = dists.argmin(axis=0)
        moved = False
        for c in range(k):
            mask = assign == c
            if mask.any():
                newc = (points[mask] * weights[mask, None]).sum(axis=0) / weights[mask].sum()
                if np.abs(newc - centers[c]).sum() > 1e-9:
                    moved = True
                centers[c] = newc
            else:
                far = np.argmax(dists.min(axis=0))
                centers[c] = points[far]
                moved = True
        if not moved:
            break
    return centers


# ---------------------------------------------------------------------------
# Image -> dominant clusters
# ---------------------------------------------------------------------------

def _load_pixels(img_path, max_size=224):
    """Downsample + flatten an image to (N, 3) float RGB pixels in [0, 1].

    Two-pass downscaling: a NEAREST probe at ~2x the target size first decides
    whether the image is flat/minimal (<=8 distinct quantized colors). Minimal
    art keeps its exact colors (NEAREST never blends), so two-color wallpapers
    can never produce phantom hues; photos fall through to LANCZOS which is
    better for smooth gradients.
    """
    img = Image.open(img_path)
    img.seek(0)
    img = ImageOps.exif_transpose(img)
    w, h = img.size
    scale = min(1.0, max_size / max(w, h))
    if scale < 1.0:
        pw, ph = max(1, round(w * scale * 2)), max(1, round(h * scale * 2))
        probe = img.resize((pw, ph), Image.NEAREST)
        if probe.mode in ("RGBA", "LA", "PA") or (probe.mode == "P" and "transparency" in probe.info):
            bg = Image.new("RGBA", probe.size, (0, 0, 0, 255))
            probe = Image.alpha_composite(bg, probe.convert("RGBA"))
        parr = np.asarray(probe.convert("RGB")).reshape(-1, 3).astype(np.float64) / 255.0
        nuniq = len(np.unique(np.round(parr * 31.0) / 31.0, axis=0))
        if nuniq <= 8:  # flat / minimal art: exact colors, no blending
            return parr
        img = img.resize(
            (max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS
        )
    if img.mode in ("RGBA", "LA", "PA") or (img.mode == "P" and "transparency" in img.info):
        bg = Image.new("RGBA", img.size, (0, 0, 0, 255))
        img = Image.alpha_composite(bg, img.convert("RGBA"))
    img = img.convert("RGB")
    return np.asarray(img).reshape(-1, 3).astype(np.float64) / 255.0


def load_clusters(pixels, k=8):
    """Return list of (uint8_rgb, population) sorted by population desc.

    k is adaptive: min(k, distinct colors). A 2-color wallpaper gets exactly 2
    clusters, so k-means can never over-segment it into phantom hues.
    """
    if pixels is None or len(pixels) == 0:
        return []
    # quantize slightly to cut unique-color count (speed) without losing fidelity
    quant = np.round(pixels * 31.0) / 31.0
    uniq, counts = np.unique(quant, axis=0, return_counts=True)
    k = max(1, min(k, len(uniq)))
    lab = rgb_to_lab(uniq)
    boosted = np.stack([lab[:, 0], lab[:, 1] * CHROMA_BOOST, lab[:, 2] * CHROMA_BOOST], axis=1)
    centers = kmeans_pp(boosted, counts.astype(np.float64), k)
    unboosted = np.stack([centers[:, 0], centers[:, 1] / CHROMA_BOOST, centers[:, 2] / CHROMA_BOOST], axis=1)
    rgb = lab_to_rgb(unboosted)
    # population: how many original pixels fall in each cluster
    d2 = ((boosted - centers[:, None, :]) ** 2).sum(axis=2)
    assign = d2.argmin(axis=0)
    pops = np.bincount(assign, weights=counts, minlength=k)
    clusters = sorted(zip(rgb.tolist(), pops.tolist()), key=lambda t: -t[1])
    return clusters


# ---------------------------------------------------------------------------
# Hue-anchor assignment -> ANSI 16
# ---------------------------------------------------------------------------

MIN_SEP = 30.0  # min hue distance between any two assigned ANSI accents
EARTH_MIN, EARTH_MAX = 25.0, 65.0  # warm earth-tone hue band (amber-brown)
POP_FLOOR = 0.001  # anchor candidates must represent >= 0.1% of image pixels


def adaptive_floor(max_sat):
    """Saturation floor for accent colors, scaled to the image's colorfulness.

    Images that are actually colorful get vivid accents; muted images stay
    muted so the palette never invents neon hues that are absent from the
    wallpaper. Returns a value in [0.30, 0.60].
    """
    return float(np.clip(max_sat * 1.15, 0.30, 0.60))


def _circmean(hues, weights):
    """Saturation/count-weighted circular mean of hue angles (degrees)."""
    rad = np.deg2rad(np.asarray(hues, dtype=np.float64))
    w = np.asarray(weights, dtype=np.float64)
    return float(np.rad2deg(np.arctan2((np.sin(rad) * w).sum(), (np.cos(rad) * w).sum())) % 360.0)


def dominant_hue(clusters):
    """Hue of the wallpaper's dominant saturated color family.

    The eye reads a wallpaper's accent from its main color family, so the base
    is the most populous cluster that is actually saturated. A near-neutral
    dominant region (dark shadows, large flat areas) has an arbitrary hue in
    HSL, so it is skipped. Crucially this is NOT the top-decile-saturation
    pixels: bright saturated foreground subjects (skin, flowers, neon) would
    otherwise hijack the accent even when they are a small fraction of the
    image (e.g. a blue wallpaper with warm skin highlights must stay blue).
    Returns hue in [0, 360) or None when every cluster is near-neutral.
    """
    for rgb, _ in clusters:  # clusters sorted by population desc
        h, l, s = rgb_to_hsl(np.array([rgb], dtype=np.float64) / 255.0)[0]
        if s >= 0.10:
            return float(h)
    return None


def earth_warm_hue(pixels, base_hue):
    """Warm golden hue of a dark earthy wallpaper, or None.

    Very dark, muted, greenish wallpapers (gruvbox-style olive landscapes)
    perceptually read as brown/khaki — at low lightness olive and brown are
    indistinguishable to the eye. When the image's base hue is greenish AND the
    image is genuinely dark AND its most saturated pixels carry warm golden
    content (khaki shadows, hue 15-60), return that warm hue so the chrome
    matches what the eye sees instead of an invented bright green. Bright
    wallpapers (blue, red, ...) are never steered.
    Returns a warm hue in [0, 360) or None when the image does not qualify.
    """
    if not (55.0 < base_hue < 160.0):  # base hue not greenish: no steering
        return None
    if pixels is None or len(pixels) == 0:
        return None
    hsl = rgb_to_hsl(pixels)
    h, l, s = hsl[:, 0], hsl[:, 1], hsl[:, 2]
    valid = (l > 0.04) & (s > 0.04)
    if int(valid.sum()) < max(16, len(pixels) * 0.001):
        return None
    if float(l[valid].mean()) >= 0.30:  # image is bright: it really is green
        return None
    cutoff = np.quantile(s[valid], 0.90)  # top 10% most saturated pixels
    vivid = valid & (s >= cutoff)
    warm = vivid & (h > 15.0) & (h < 60.0)
    if int(warm.sum()) < max(64, 0.05 * int(vivid.sum())):
        return None
    return _circmean(h[warm], s[warm])


def hue_anchors(clusters, max_sat, force_hue=None, bg_hue=None):
    """Up to 6 well-separated REAL image hues for the ANSI accent slots.

    Only hues that actually appear in the image are used, chosen by vividness
    (population x saturation). force_hue (e.g. the perceived earth-tone accent
    hue) is added as the top-priority candidate so the wallpaper's dominant
    perceived color always gets a slot. A population floor drops resampling
    artifact clusters (tiny LANCZOS blends) that used to invent phantom hues.
    When the image has fewer than 6 distinct hues (monochrome wallpapers) the
    extra slots re-use the image's own hues — the palette stays honest rather
    than inventing foreign colors, and build_ansi16 spreads their lightness so
    the duplicated hues remain distinguishable. No fixed/foreign hue is ever
    invented.
    """
    floor = adaptive_floor(max_sat)
    total = float(sum(pop for _, pop in clusters))
    min_pop = max(3.0, POP_FLOOR * total) if total > 0 else 3.0
    cands = []
    if force_hue is not None:
        cands.append((float(force_hue), max(floor, 0.65), 1e9))
    for rgb, pop in clusters:
        if pop < min_pop:  # phantom/artifact cluster: too small to matter
            continue
        h, l, s = rgb_to_hsl(np.array([rgb], dtype=np.float64) / 255.0)[0]
        if s >= 0.07 and pop > 0:  # skip near-neutral (noisy hue) clusters
            cands.append((float(h), float(s), float(pop)))
    cands.sort(key=lambda t: -t[2] * t[1])  # most vivid (pop x sat) first
    chosen = []
    for h, s, pop in cands:
        if any(min(abs(h - u) % 360, 360 - abs(h - u) % 360) < MIN_SEP for u, _ in chosen):
            continue
        chosen.append((h, max(s, floor)))
        if len(chosen) >= 6:
            break
    if not chosen:  # only reachable if every cluster is near-neutral
        base = (float(force_hue) if force_hue is not None
                else (float(bg_hue) if bg_hue is not None else 0.0))
        chosen = [(base, floor)]
    base = list(chosen)
    i = 0
    while len(chosen) < 6:  # cycle the image's own hues (no invented axes)
        chosen.append(base[i % len(base)])
        i += 1
    return chosen


def build_ansi16(bg_rgb, anchors, light=False):
    """Construct the 16-color palette around the background and 6 anchors.

    A near-neutral dominant background (bs < 0.08: black/white/gray wallpapers)
    keeps s=0 pure gray — the old behavior forced s>=0.15 at a meaningless
    hue 0, turning black wallpapers red.
    """
    bh, bl, bs = rgb_to_hsl(np.array([bg_rgb], dtype=np.float64) / 255.0)[0]
    bh = float(bh)
    bl = float(bl)
    bs = float(bs)
    if light:
        bg_s = 0.0 if bs < 0.08 else max(bs, 0.10)
        bg = hsl_to_rgb(np.array([[bh, 0.90, bg_s]], dtype=np.float64))[0]
        fg = hsl_to_rgb(np.array([[bh, 0.12, min(0.30, bs)]], dtype=np.float64))[0]
        gray = hsl_to_rgb(np.array([[bh, 0.65, 0.05]], dtype=np.float64))[0]
    else:
        bg_s = 0.0 if bs < 0.08 else max(bs, 0.15)
        bg = hsl_to_rgb(np.array([[bh, 0.10, bg_s]], dtype=np.float64))[0]
        fg = hsl_to_rgb(np.array([[bh, 0.82, min(0.30, bs + 0.05)]], dtype=np.float64))[0]
        gray = hsl_to_rgb(np.array([[bh, 0.36, 0.08]], dtype=np.float64))[0]
    dark_l = 0.40 if not light else 0.62
    bright_l = 0.72 if not light else 0.30
    # Gentle lightness ladder so duplicated hues (monochrome wallpapers) stay
    # distinguishable; colorful wallpapers are barely affected.
    ladder = np.linspace(-0.06, 0.06, 6)
    cols = [bg]
    cols += [
        hsl_to_rgb(np.array([[h, np.clip(dark_l + ladder[i], 0.08, 0.92), s]],
                            dtype=np.float64))[0]
        for i, (h, s) in enumerate(anchors)
    ]
    cols += [fg, gray]
    cols += [
        hsl_to_rgb(np.array([[h, np.clip(bright_l + ladder[i], 0.08, 0.92),
                              min(1.0, s + 0.15)]], dtype=np.float64))[0]
        for i, (h, s) in enumerate(anchors)
    ]
    cols += [fg]
    return cols


NEUTRAL_HEX = (
    "#1a1a1a", "#595959", "#6b6b6b", "#808080",
    "#949494", "#a8a8a8", "#bdbdbd", "#d1d1d1",
    "#5c5c5c", "#8f8f8f", "#a3a3a3", "#b8b8b8",
    "#cccccc", "#e0e0e0", "#f5f5f5", "#d1d1d1",
)


def neutral_from_pixels(pixels, light=False):
    """Grayscale ramp derived from the image's OWN luminance distribution.

    Unlike the fixed NEUTRAL_HEX fallback, the ramp follows the wallpaper's
    tone: a black wallpaper gets a truly dark ramp, a white one a light ramp.
    Readability is guaranteed by enforcing a minimum span (and the standard
    dark/light bg-fg anchors).
    """
    l = rgb_to_hsl(pixels)[:, 1]
    lo, hi = float(np.percentile(l, 5)), float(np.percentile(l, 95))
    if hi - lo < 0.25:  # flat image: widen around its own tone
        mid = 0.5 * (lo + hi)
        lo, hi = max(0.0, mid - 0.125), min(1.0, mid + 0.125)
    if light:
        # light scheme: bg (color0) is the LIGHT end, fg (color7/15) the dark end
        lo = min(lo, 0.18)
        hi = max(hi, 0.88)
        idx = [14, 8, 9, 10, 11, 12, 13, 0, 7, 1, 2, 3, 4, 5, 6, 0]
    else:
        lo = min(lo, 0.12)
        hi = max(hi, 0.80)
        idx = [0, 1, 2, 3, 4, 5, 6, 14, 7, 8, 9, 10, 11, 12, 13, 14]
    steps = np.linspace(lo, hi, 15)
    hsl = np.stack([np.zeros(16), steps[idx], np.zeros(16)], axis=1)
    out = hsl_to_rgb(hsl)
    return [_hex(c) for c in out]


def accent_from_hue(hue, light=False):
    """Derive the two chrome accent colors from a hue angle (degrees).

    WM title bars / menu / icons / dunst / conky follow the wallpaper's own
    hue at a readable saturation so chrome changes with the image. Accent is
    meant to pop, so a fixed readable saturation is applied (the hue is what
    tracks the wallpaper; see dominant_hue / earth_warm_hue for where it
    comes from).
    Returns (accent, accent_dim) hex strings.
    """
    if light:
        a_l, a_s = 0.60, 0.70
        d_l, d_s = 0.45, 0.60
    else:
        a_l, a_s = 0.55, 0.65
        d_l, d_s = 0.35, 0.55
    if EARTH_MIN <= hue <= EARTH_MAX:  # warm earth tones: richer, deeper brown
        if light:
            a_l, a_s = 0.52, 0.85
            d_l, d_s = 0.37, 0.75
        else:
            a_l, a_s = 0.46, 0.80
            d_l, d_s = 0.28, 0.70
    accent = hsl_to_rgb(np.array([[hue, a_l, a_s]], dtype=np.float64))[0]
    accent_dim = hsl_to_rgb(np.array([[hue, d_l, d_s]], dtype=np.float64))[0]
    return _hex(accent), _hex(accent_dim)


def neutral_16():
    """Safe grayscale ramp used as the last-resort fallback."""
    return NEUTRAL_HEX


def scheme_from_image(path, light=None):
    """Top-level, fully guarded generator.

    Returns (list of 16 hex colors, accent hex, accent_dim hex). Accents are
    None when the image has no usable dominant color. light=None auto-detects:
    bright, low-chroma images (white minimalism) get a light scheme.
    """
    pixels = _load_pixels(path)
    if pixels is None or len(pixels) == 0:
        return list(neutral_16()), None, None
    if light is None:
        hsl = rgb_to_hsl(pixels)
        mean_l, mean_s = float(hsl[:, 1].mean()), float(hsl[:, 2].mean())
        light = (mean_l >= 0.62) and (mean_s < 0.20)
    clusters = load_clusters(pixels)
    if not clusters:
        return neutral_from_pixels(pixels, light), None, None
    max_sat = max(
        rgb_to_hsl(np.array([rgb], dtype=np.float64) / 255.0)[0][2] for rgb, _ in clusters
    )
    if max_sat < 0.10:
        return neutral_from_pixels(pixels, light), None, None
    accent, accent_dim = None, None
    force_hue = None
    try:  # dominant saturated cluster (never lets an exception break the palette)
        hue = dominant_hue(clusters)
        if hue is not None:
            warm = earth_warm_hue(pixels, hue)
            if warm is not None:
                # steer toward a rich amber-brown (hue ~38) so dark earthy
                # images read as striking brown instead of washed-out golden
                hue = 38.0 + (warm - 38.0) * 0.35
            accent, accent_dim = accent_from_hue(hue, light)
            if EARTH_MIN <= hue <= EARTH_MAX:
                force_hue = hue  # perceived warm hue gets its own palette slot
    except Exception:
        pass
    if accent is None:  # fallback: most populous cluster, any saturation
        hue2 = rgb_to_hsl(np.array([clusters[0][0]], dtype=np.float64) / 255.0)[0][0]
        accent, accent_dim = accent_from_hue(hue2, light)
        if EARTH_MIN <= hue2 <= EARTH_MAX:
            force_hue = hue2
    bg_hue = rgb_to_hsl(np.array([clusters[0][0]], dtype=np.float64) / 255.0)[0][0]
    anchors = hue_anchors(clusters, max_sat, force_hue=force_hue, bg_hue=bg_hue)
    palette = build_ansi16(clusters[0][0], anchors, light)
    return [_hex(c) for c in palette], accent, accent_dim


# ---------------------------------------------------------------------------
# Cache writers (byte-exact pywal formats) + stale-cache cleanup
# ---------------------------------------------------------------------------

def _clear_stale_cache(cache_dir, img_path):
    """Remove the previous wallpaper's cache files when the image changed.

    The old colors would otherwise linger alongside the new ones (and the old
    accent would survive even when the new image is neutral). Only walgen's own
    files are touched; wpg/pywal template outputs are regenerated by wpg.
    """
    try:
        with open(os.path.join(cache_dir, "wal")) as f:
            old = f.read().strip()
    except Exception:
        return  # no recorded wallpaper yet -> nothing stale
    if old and os.path.abspath(old) != os.path.abspath(img_path):
        for name in ("colors", "colors.sh", "colors.json", "wal", "accents"):
            p = os.path.join(cache_dir, name)
            if os.path.exists(p):
                try:
                    os.remove(p)
                except Exception:
                    pass


def write_cache(cache_dir, img_path, colors, light=False):
    os.makedirs(cache_dir, exist_ok=True)
    bg, fg = colors[0], colors[15]

    # ~/.cache/wal/colors
    with open(os.path.join(cache_dir, "colors"), "w") as f:
        for c in colors:
            f.write(c + "\n")

    # ~/.cache/wal/colors.sh
    lines = [
        "# Shell variables",
        "# Generated by 'wal'",
        'wallpaper="%s"' % img_path,
        "",
        "# Special",
        "background='%s'" % bg,
        "foreground='%s'" % fg,
        "cursor='%s'" % fg,
        "",
        "# Colors",
    ]
    for i, c in enumerate(colors):
        lines.append("color%d='%s'" % (i, c))
    lines += [
        "",
        "# FZF colors",
        'export FZF_DEFAULT_OPTS="',
        "    $FZF_DEFAULT_OPTS",
        "    --color fg:7,bg:0,hl:1,fg+:232,bg+:1,hl+:255",
        "    --color info:7,prompt:2,spinner:1,pointer:232,marker:1",
        '"',
        "",
        "# Fix LS_COLORS being unreadable.",
        'export LS_COLORS="${LS_COLORS}:su=30;41:ow=30;42:st=30;44:"',
        "",
    ]
    with open(os.path.join(cache_dir, "colors.sh"), "w") as f:
        f.write("\n".join(lines))

    # ~/.cache/wal/colors.json
    try:
        # Đọc theo block 64KB thay vì f.read() toàn bộ — ảnh lớn không tốn RAM
        _md5 = hashlib.md5()
        with open(img_path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                _md5.update(chunk)
        checksum = _md5.hexdigest()
    except Exception:
        checksum = "00000000000000000000000000000000"
    data = {
        "checksum": checksum,
        "wallpaper": os.path.abspath(img_path),
        "alpha": "100",
        "special": {"background": bg, "foreground": fg, "cursor": fg},
        "colors": {"color%d" % i: c for i, c in enumerate(colors)},
    }
    with open(os.path.join(cache_dir, "colors.json"), "w") as f:
        json.dump(data, f, indent=4)
        f.write("\n")

    # ~/.cache/wal/wal
    with open(os.path.join(cache_dir, "wal"), "w") as f:
        f.write(os.path.abspath(img_path))


def _write_accents(cache_dir, accent, accent_dim):
    """Chrome accent colors derived from the dominant wallpaper hue.

    WM title bars / menus / icons, dunst and conky must track the actual
    wallpaper, not the fixed ANSI anchors (color4 is always blue, color5 always
    magenta). Exported as shell vars for wmwal.sh / dunstwal.sh / conkywal.sh:
        ~/.cache/wal/accents
    """
    with open(os.path.join(cache_dir, "accents"), "w") as f:
        f.write('accent="%s"\n' % accent)
        f.write('accent_dim="%s"\n' % accent_dim)


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Optimal wallpaper color extraction")
    ap.add_argument("image", help="path to the wallpaper image")
    ap.add_argument("--light", action="store_true", help="force a light scheme")
    ap.add_argument("--cache-dir", default=os.path.expanduser("~/.cache/wal"),
                    help="where to write the wal cache (default: ~/.cache/wal)")
    args = ap.parse_args()

    if not os.path.isfile(args.image):
        sys.stderr.write("walgen: image not found: %s\n" % args.image)
        sys.exit(1)

    _clear_stale_cache(args.cache_dir, args.image)

    if not _HAS_NUMPY:
        sys.stderr.write("walgen: numpy unavailable, using neutral palette\n")
        colors = list(neutral_16())
        accent = accent_dim = None
    else:
        try:
            colors, accent, accent_dim = scheme_from_image(
                args.image, light=True if args.light else None
            )
        except Exception as exc:  # never let the chain break
            sys.stderr.write("walgen: extraction failed (%s), using neutral palette\n" % exc)
            colors = list(neutral_16())
            accent = accent_dim = None

    try:
        write_cache(args.cache_dir, args.image, colors, light=bool(args.light))
        if accent is not None and accent_dim is not None:
            _write_accents(args.cache_dir, accent, accent_dim)
        else:
            stale = os.path.join(args.cache_dir, "accents")
            if os.path.exists(stale):
                os.remove(stale)
    except Exception as exc:
        sys.stderr.write("walgen: could not write cache (%s); printing colors only\n" % exc)
    try:
        for i, c in enumerate(colors):
            print("color%d %s" % (i, c))
    except BrokenPipeError:
        try:
            sys.stdout.close()
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
