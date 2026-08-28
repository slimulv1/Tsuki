#!/usr/bin/env python3
"""wallpicker.py - fullscreen filmstrip wallpaper picker for dwm (GTK3 / PyGObject).

A wallpaper picker: the focused wallpaper opens as a large centred HERO
preview while the rest flank it as thin receding strips (a shelf). Selection
changes glide on an OutCubic slide - smooth filmstrip animation, clocked by
the display's frame clock (not a fixed-tick timer).

Layout (values are per-active-monitor fractions):
  hero    = 46% of screen height, drawn aspect-fit inside a frame matched to
            the monitor's real aspect ratio, 3px salmon (#e08a80) border
  strips  = dynamically sized so the first side strip lands exactly GAP px
            from the hero AND the last strip keeps GAP breathing room at the
            screen edge; height 80% of hero height, crop-fill, black overlay
            alpha = min(0.40, 0.14 + |dist-to-hero| * 0.05)

Thumbnails are decoded to EXACT boxes (width x height) the cells actually
paint, cache-differentiated per box, so strips stay sharp without retaining
invisible wide-image pixels.

stdout contract (for dwm keybind pipes such as `wallpicker.py | feh --bg-fill ...`):
  Enter -> prints the absolute wallpaper path, exit 0
  Esc   -> prints nothing, exit 0

Usage: wallpicker.py [--dir DIR] [--dry-run]

Implementation notes (decode/cache layer): thumbnails come from the sibling C
helper `imgdec` (libjpeg-turbo DCT-scaled decode + stb resize) writing straight
into an atomic temp cache file, else a small pool of worker threads using
Pillow (JPEG DCT downscale + LANCZOS resize); results are published to a PNG
disk cache under ~/.cache/dwmwal/picker/ (md5(path)-WxH.png, invalidated by
source mtime) and handed to GTK as GdkPixbufs on the worker thread. Without
both, the picker falls back to plain gdk-pixbuf scaling.
"""

import argparse
import hashlib
import io
import math
import os
import subprocess
import sys
import tempfile
import threading
from collections import deque

try:
    import cairo  # pycairo: needed for the SOURCE/OVER operator constants
    import gi
    # Pin every namespace BEFORE importing - otherwise PyGObject may pull the
    # newest Gdk (4.x) transitively and collide with the Gtk 3.0 stack.
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    gi.require_version("GdkPixbuf", "2.0")
    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, Pango, PangoCairo
except (ImportError, ValueError, AttributeError) as exc:
    sys.stderr.write("wallpicker: PyGObject/GTK3/cairo stack unavailable: %s\n" % exc)
    sys.exit(1)

try:
    from PIL import Image
    Image.MAX_IMAGE_PIXELS = 300_000_000
except ImportError:  # Pillow optional: decode falls back to gdk-pixbuf
    Image = None

# ---------------------------------------------------------------- constants

OVERLAY_ALPHA = 0.55          # desktop dimming behind the picker
SALMON = (0xe0 / 255, 0x8a / 255, 0x80 / 255)   # hero border + caption ink
HINT_INK = (0x97 / 255, 0x86 / 255, 0x7f / 255)  # hint line + filter UI
PLACEHOLDER = (0.08, 0.07, 0.07)                # unloaded/broken cells

FONT_STACK = "CaskaydiaCove Nerd Font Mono, monospace"
CAPTION_PX = 21
HINT_PX = 17
FILTER_PX = 18

ANIM_MS = 320                 # OutCubic glide duration (frame-clock based)
FOCUS_RETRY_MS = 50           # keyboard-focus retry cadence after map
FOCUS_RETRY_MAX = 40          # attempts before giving up (~2 s total)
GAP = 10                      # gap between neighbouring strips
HERO_H_FRAC = 0.46            # hero height / screen height
STRIP_W_FRAC = 0.05           # provisional strip width / screen height
STRIP_H_FRAC = 0.80           # strip height / hero height
HERO_MAX_W_FRAC = 0.62        # safety clamp on narrow screens
CY_FRAC = 0.44                # hero centre height / screen height (room for caption)
RECEDE_BASE = 0.14            # strip overlay alpha at |rel| = 0
RECEDE_STEP = 0.05            # extra alpha per step away from the hero
RECEDE_CAP = 0.40             # maximum recede darkness
SS = 1                        # supersample factor for pixbuf loading
PREFETCH_RADIUS = 4           # strips preloaded either side of the hero
LOAD_QUEUE_MAX = 64           # decode backlog cap; overflow is re-requested
MAX_CACHE = 384               # scaled-pixbuf cache entries before eviction
DISK_CACHE_DIR = os.path.expanduser("~/.cache/dwmwal/picker")  # PNG thumbs
IMGDEC_TIMEOUT_S = 5.0        # hard cap on one imgdec subprocess decode

HERO_DEBOUNCE_MS = 75         # defer a full-size hero decode during key-repeat
RAPID_RETARGET_US = 120_000   # key-repeat window (monotonic ns) for debounce


def _imgdec_bin():
    """Path of the sibling imgdec C helper when built+executable, else None."""
    exe = os.path.join(os.path.dirname(os.path.abspath(__file__)), "imgdec")
    if os.path.isfile(exe) and os.access(exe, os.X_OK):
        return exe
    return None


def _probe_size(path):
    """Read only the image header for (w, h); None if unavailable.

    Cheap: Pillow decodes just the header (SOF) + dimension fields, no pixel
    data. Used to size the strip decode so a portrait box stays sharp after
    cover-crop from a landscape source.
    """
    if Image is None:
        return None
    try:
        with Image.open(path) as im:
            return im.width, im.height
    except Exception:
        return None


def _pil_thumb(path, width):
    """DCT-scaled decode + LANCZOS. Returns RGB PIL Image or None."""
    try:
        with Image.open(path) as im:
            s = next((f for f in (8, 4, 2) if im.width // f >= width * 1.5), 0)
            if s:
                im.draft("RGB", (im.width // s, im.height // s))
            im = im.convert("RGB")
            h = max(1, round(im.height * width / im.width))
            return im.resize((width, h), Image.Resampling.LANCZOS,
                             reducing_gap=2.0)
    except Exception:
        return None


def _gdk_decode(path, width):
    """Legacy fallback (no Pillow): gdk-pixbuf scaled to fit `width`.

    Kept so a missing Pillow degrades performance only - never crashes.
    """
    try:
        return GdkPixbuf.Pixbuf.new_from_file_at_size(path, width, 1 << 24)
    except Exception:
        return None


def _out_cubic(p):
    """OutCubic easing curve."""
    return 1.0 - (1.0 - p) ** 3


def _lerp(a, b, t):
    """Linear interpolation."""
    return a + (b - a) * t


def find_wallpapers(root):
    """Recursively collect jpg/jpeg/png/webp under root, sorted by path.

    Validation is extension-only on purpose: probing every candidate with
    gdk-pixbuf dominated startup (seconds on 100+ files). Broken images are
    instead tolerated lazily - decode failures cache as None and the picker
    paints placeholders / hops past broken heroes.
    """
    wanted_exts = (".jpg", ".jpeg", ".png", ".webp")
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            if os.path.splitext(name)[1].lower() in wanted_exts:
                found.append(os.path.abspath(os.path.join(dirpath, name)))
    found.sort()
    return found


class Picker(Gtk.Window):
    """Fullscreen filmstrip carousel."""

    def __init__(self, files):
        Gtk.Window.__init__(self)
        self.files = files          # full sorted model
        self.visible = list(files)  # filtered view shown by the carousel
        self.filter_text = ""
        self.pos = 0.0              # continuous selection position (animated)
        self.target = 0             # integer index the animation heads to
        self.anim_from = 0.0
        self.anim_to = 0.0
        self.anim_t0 = 0
        self.anim_id = None
        self.cache = {}             # (path, kind) -> GdkPixbuf or None(broken)
        self.hit_rects = []         # [(idx, x, y, w, h)] rebuilt every draw
        self.had_focus = False
        self.focus_timer_id = None   # GLib source id of the grab-retry loop
        self.focus_attempts = 0      # grab attempts spent so far
        self.focus_dead = False      # True once quitting; halts retries
        self.pf_pending = False
        self.scroll_acc = 0.0
        self._last_hero_pixbuf = None     # last sharp hero (morph fallback)
        self._hero_timer_id = None        # pending hero-decode debounce timer
        self._last_retarget_us = 0        # monotonic ns of the last step/hold
        self._surface_cache = {}          # id(pixbuf) -> (pixbuf, cairo surface)
        self.pf_queued = set()      # (path, kind) keys awaiting decode
        self._inflight = set()      # keys being decoded by a worker right now
        self.load_cond = threading.Condition()
        self.load_q = deque()       # decode jobs; heroes jump the queue
        # Small decode pool: Pillow drops the GIL inside decode/resize, so
        # these threads genuinely run in parallel across cores.
        n_loaders = min(8, os.cpu_count() or 4)
        self.loaders = []
        for i in range(n_loaders):
            loader = threading.Thread(target=self._load_worker,
                                      name="loader-%d" % i, daemon=True)
            loader.start()
            self.loaders.append(loader)
        self._logical_target = float(self.target)
        self._aspect_cache = {}   # path -> (w, h) probed from headers

        self.set_title("wallpicker")
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_accept_focus(True)
        self.set_focus_on_map(True)
        self.set_keep_above(True)
        self.set_app_paintable(True)
        # NOTIFICATION hint: dwm treats DOCK windows as statusbar-like chrome
        # and never selects/focuses them (keys never arrive even when a
        # keyboard grab "succeeds"). NOTIFICATION stays undecorated/floaty
        # while remaining a normal, focusable client for dwm.
        self.set_type_hint(Gdk.WindowTypeHint.NOTIFICATION)

        screen = self.get_screen()
        self.rgba_ok = False
        visual = screen.get_rgba_visual()
        if visual is not None and screen.is_composited():
            self.set_visual(visual)
            self.rgba_ok = True

        self.connect("draw", self.on_draw)
        self.connect("key-press-event", self.on_key_press)
        self.connect("button-press-event", self.on_button_press)
        self.connect("scroll-event", self.on_scroll)
        self.connect("map-event", self.on_map)
        self.connect("focus-in-event", self.on_focus_in)
        self.connect("focus-out-event", self.on_focus_out)
        self.connect("delete-event", self.on_delete)
        self.connect("destroy", lambda *_: self.quit())
        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK
                        | Gdk.EventMask.SCROLL_MASK
                        | Gdk.EventMask.SMOOTH_SCROLL_MASK)
        self.fullscreen()

        # Active-monitor placement: match the monitor under the pointer, not
        # just the primary screen, so the picker opens where the user is.
        try:
            display = Gdk.Display.get_default()
            pointer = display.get_default_seat().get_pointer()
            _screen, pointer_x, pointer_y = pointer.get_position()
            monitor = display.get_monitor_at_point(pointer_x, pointer_y)
            geometry = monitor.get_geometry()
            self.move(geometry.x, geometry.y)
            self.set_default_size(geometry.width, geometry.height)
            self.fullscreen()
        except Exception as exc:
            sys.stderr.write("wallpicker: active-monitor placement failed: %s\n" % exc)

    # ------------------------------------------------------------ lifecycle

    def quit(self):
        """Leave without printing anything (cancel path)."""
        self._cancel_hero_timer()
        self._stop_animation()
        self.stop_focus_retry()
        try:
            # Release a server-side grab so the keyboard is not left stuck
            # with a dead picker window.
            Gdk.keyboard_ungrab(Gdk.CURRENT_TIME)
        except Exception:
            pass  # grab never taken / display already torn down
        try:
            Gtk.main_quit()
        except RuntimeError:
            pass  # main loop already gone

    def apply(self):
        """Print the selected wallpaper's absolute path and leave."""
        if not self.visible:
            return  # nothing to apply while the filter matches zero files
        path = self.visible[self.target % len(self.visible)]
        sys.stdout.write(path + "\n")
        sys.stdout.flush()
        self.quit()

    def on_map(self, _win, _event):
        """Take keyboard focus aggressively once mapped (dwm focus races)."""
        self.start_focus_retry()
        self.prefetch_soon()

    # --------------------------------------------------- keyboard focus war

    def start_focus_retry(self):
        """Poll focus + a server-side keyboard grab until one lands.

        A single grab attempt loses the race against dwm's post-keybind
        focus handling (the previous app keeps the X keyboard); retrying
        every FOCUS_RETRY_MS for up to ~2 s makes the arrow keys reach the
        picker no matter who held the keyboard first.
        """
        self.focus_attempts = 0
        self.focus_dead = False
        if self.focus_timer_id is None:
            self.focus_timer_id = GLib.timeout_add(FOCUS_RETRY_MS,
                                                   self._focus_retry_tick)

    def stop_focus_retry(self):
        """Cancel any pending retry tick (quit/destroy path)."""
        self.focus_dead = True
        if self.focus_timer_id is not None:
            GLib.source_remove(self.focus_timer_id)
            self.focus_timer_id = None

    def _focus_retry_tick(self):
        """One focus/grab attempt; True keeps the retry source alive.

        Clears self.focus_timer_id whenever the source detaches itself
        (including a successful grab), so a later start_focus_retry()
        re-arms cleanly instead of leaving a stale id behind.
        """
        if self.focus_dead:
            self.focus_timer_id = None
            keep = GLib.SOURCE_REMOVE
        else:
            try:
                gdk_win = self.get_window()
                if gdk_win is None:
                    keep = self._retry_failed("no gdk window yet")
                else:
                    gdk_win.focus(Gdk.CURRENT_TIME)   # XSetInputFocus
                    if self.focus_attempts == 0:
                        self.present()                # WM-level activate
                    self.grab_focus()
                    status = Gdk.keyboard_grab(gdk_win, True, Gdk.CURRENT_TIME)
                    keep = (GLib.SOURCE_REMOVE
                            if status == Gdk.GrabStatus.SUCCESS
                            else self._retry_failed(status))
            except Exception as exc:
                keep = self._retry_failed(exc)
        if not keep:
            self.focus_timer_id = None
        return keep

    def _retry_failed(self, status):
        """Log a non-success result; stop after FOCUS_RETRY_MAX attempts."""
        nick = getattr(status, "value_nick", str(status))
        sys.stderr.write("wallpicker: keyboard grab '%s' "
                         "(attempt %d/%d)\n"
                         % (nick, self.focus_attempts + 1, FOCUS_RETRY_MAX))
        self.focus_attempts += 1
        if self.focus_attempts >= FOCUS_RETRY_MAX:
            sys.stderr.write("wallpicker: giving up on keyboard grab\n")
            self.focus_timer_id = None
            return GLib.SOURCE_REMOVE
        return True                           # same source fires again

    def on_focus_in(self, _win, _event):
        self.had_focus = True

    def on_focus_out(self, _win, _event):
        # Rofi-style: losing focus while running means the user moved on.
        if self.had_focus:
            self.quit()

    def on_delete(self, _win, _event):
        self.quit()
        return True

    # ------------------------------------------------------------- geometry

    def _metrics(self, width, height):
        """Layout constants derived per-frame; hero crop matches the monitor.

        Strips are sized dynamically so the first side strip sits exactly
        GAP px from the hero AND the last strip keeps GAP breathing room at
        the physical screen edge (superior to a fixed STRIP_W_FRAC width).
        """
        monitor_ratio = width / max(1.0, float(height))
        hero_h = height * HERO_H_FRAC
        hero_w = min(hero_h * monitor_ratio, width * HERO_MAX_W_FRAC)
        hero_h = hero_w / monitor_ratio  # keep the exact ratio after clamping
        strip_h = hero_h * STRIP_H_FRAC
        cx = width / 2.0
        cy = height * CY_FRAC
        m = {
            "w": width, "h": height,
            "hero_w": hero_w, "hero_h": hero_h,
            "strip_h": strip_h,
            "cx": cx, "cy": cy,
        }
        count = len(self.visible)
        side_count = min(4, count // 2)
        if side_count > 0:
            side_space = cx - hero_w / 2.0
            total_gaps = GAP * (side_count + 1)
            m["strip_w"] = max(2.0, (side_space - total_gaps) / side_count)
            m["max_side"] = side_count
        else:
            m["strip_w"] = 2.0
            m["max_side"] = 0
        return m

    def _frame_for(self, rel, m):
        """Geometry + darkness for an item at fractional distance `rel`.

        Morph zone is |rel| < 1.0: the outgoing and incoming heroes interpolate
        towards the first strip slot with their edges kept exactly GAP px apart,
        so the whole row slides as one continuous filmstrip (no empty first
        column at the instant the old hero leaves the frame).
        """
        distance = abs(rel)
        side = 1.0 if rel >= 0 else -1.0
        hero_x = m["cx"] - m["hero_w"] / 2.0
        hero_y = m["cy"] - m["hero_h"] / 2.0
        strip_width = m["strip_w"]
        strip_height = m["strip_h"]
        if side >= 0:
            first_x = m["cx"] + m["hero_w"] / 2.0 + GAP
        else:
            first_x = m["cx"] - m["hero_w"] / 2.0 - GAP - strip_width
        first_y = m["cy"] - strip_height / 2.0
        if distance < 1.0:
            return (_lerp(hero_x, first_x, distance),
                    _lerp(hero_y, first_y, distance),
                    _lerp(m["hero_w"], strip_width, distance),
                    _lerp(m["hero_h"], strip_height, distance),
                    RECEDE_BASE * distance)
        extra = (distance - 1.0) * (strip_width + GAP)
        x = first_x + extra if side >= 0 else first_x - extra
        darkness = min(RECEDE_CAP,
                       RECEDE_BASE + RECEDE_STEP * (distance - 1.0))
        return x, first_y, strip_width, strip_height, darkness

    # ------------------------------------------------------------- pixbufs

    def _target_width(self, kind, m):
        """Exact box (width, height) a slot's thumbnail decodes to.

        The C helper centre-crops/writes into this box before caching, so a
        narrow side cell keeps full on-screen sharpness without retaining the
        invisible left/right pixels of a wide wallpaper.
        """
        if kind == "hero":
            return (max(2, int(round(m["hero_w"] * SS))),
                    max(2, int(round(m["hero_h"] * SS))))
        # Strips are cover-cropped (heavily on the vertical axis for narrow
        # portrait boxes), so decode at 2x on-screen size to stay sharp when
        # Cairo upscales into the box. imgdec never upscales beyond the
        # source, so small originals just decode at their native resolution.
        return (max(2, int(round(m["strip_w"] * SS * 2))),
                max(2, int(round(m["strip_h"] * SS * 2))))

    def _pixbuf(self, path, kind, m, idx):
        """Cache lookup only - decoding happens on the background workers.

        Never exposes an empty hero slot while a sharp decode is pending:
        falls back to that wallpaper's strip thumbnail or the last sharp hero
        so the morph never flashes a bare placeholder plate.
        """
        key = (path, kind)
        if key in self.cache:
            pixbuf = self.cache[key]
            if pixbuf is not None and kind == "hero":
                self._last_hero_pixbuf = pixbuf
            return pixbuf

        # A retargeted animation may briefly keep the outgoing cell in hero
        # geometry. Full-size decode there is obsolete work before the result
        # lands, especially under fast key repeat.
        focused_path = (self.visible[self.target] if self.visible else None)
        if kind == "hero" and path != focused_path:
            return (self.cache.get((path, "strip")) or
                    self._last_hero_pixbuf)
        if kind == "hero" and self._hero_timer_id is not None:
            return (self.cache.get((path, "strip")) or
                    self._last_hero_pixbuf)

        # Not cached: submit a decode, then show the best available fallback.
        self._enqueue(key, path, self._target_width(kind, m), idx)
        if kind == "hero":
            strip_pixbuf = self.cache.get((path, "strip"))
            if strip_pixbuf is not None:
                return strip_pixbuf
            return self._last_hero_pixbuf
        # The old hero becomes the first side strip at the end of the first
        # move; reuse its already-sharp hero pixbuf while the strip decode is
        # in flight instead of flashing the placeholder.
        hero_pixbuf = self.cache.get((path, "hero"))
        if hero_pixbuf is not None:
            return hero_pixbuf
        return None

    def _enqueue(self, key, path, size, idx):
        """Queue one decode job; heroes jump ahead of queued strips.

        While animating, any queued hero icdecode superseded by a newer
        selection is dropped so budget goes to the current hero. Deduped
        against cached/in-flight keys and capped as a backstop - work dropped
        here is simply re-requested by the next draw or prefetch pass.
        """
        if key[1] == "hero" and self.anim_id is not None:
            with self.load_cond:
                kept = deque()
                for job in self.load_q:
                    old_key = job[2]
                    if old_key[1] == "hero" and old_key != key:
                        self.pf_queued.discard(old_key)
                    else:
                        kept.append(job)
                self.load_q.clear()
                self.load_q.extend(kept)
        if key in self.cache or key in self.pf_queued:
            return
        job = (idx, path, key, size)
        with self.load_cond:
            if len(self.load_q) >= LOAD_QUEUE_MAX:
                return
            self.pf_queued.add(key)
            if key[1] == "hero":
                self.load_q.appendleft(job)
            else:
                self.load_q.append(job)
            self.load_cond.notify()

    def _cachefile_for(self, path, size):
        """PNG cache path for (path, box-size); None when unusable.

        `size` is a (w, h) box; a bare int degrades to (int, 0).
        """
        try:
            width, height = size if isinstance(size, tuple) else (size, 0)
            digest = hashlib.md5(os.path.abspath(path).encode()).hexdigest()
            return os.path.join(DISK_CACHE_DIR,
                                "%s-%dx%d.png" % (digest, int(width), int(height)))
        except Exception:
            return None

    @staticmethod
    def _atomic_write(cachefile, data):
        """Atomically publish `data` bytes to `cachefile`; best-effort only.

        Writes go to a temp file in the same directory followed by
        os.replace(), so concurrent readers never see partial files.
        """
        try:
            os.makedirs(DISK_CACHE_DIR, exist_ok=True)
            fd, tmpname = tempfile.mkstemp(dir=DISK_CACHE_DIR, suffix=".png")
            try:
                with os.fdopen(fd, "wb") as fh:
                    fh.write(data)
                os.replace(tmpname, cachefile)
            except Exception:
                try:
                    os.unlink(tmpname)
                except OSError:
                    pass
        except Exception:
            pass  # disk cache must never break the picker

    def _imgdec_decode(self, path, size):
        """Decode directly into an atomic cache file via the C helper.

        imgdec accepts `imgdec <input> <W>x<H> [outfile]`: the C helper
        decodes, cover-resizes and center-crops to the exact box, so the
        atomic cache file is already the exact slot size - sharp at 2x with
        no wasted pixels. `size` is the box (2x on-screen, from _target_width).
        """
        exe = _imgdec_bin()
        if exe is None:
            return None
        width, height = size if isinstance(size, tuple) else (size, 0)
        width = max(2, int(width))
        height = max(2, int(height))
        cachefile = self._cachefile_for(path, size)
        if cachefile is None:
            return None
        try:
            os.makedirs(DISK_CACHE_DIR, exist_ok=True)
            fd, temp_name = tempfile.mkstemp(dir=DISK_CACHE_DIR,
                                             prefix=".wallpicker-", suffix=".tmp")
            os.close(fd)
            try:
                command = ["/usr/bin/nice", "-n", "10",
                           exe, path, f"{width}x{height}", temp_name]
                result = subprocess.run(
                    command, stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL, timeout=IMGDEC_TIMEOUT_S)
                if result.returncode != 0:
                    return None
                with open(temp_name, "rb") as handle:
                    if handle.read(8) != b"\x89PNG\r\n\x1a\n":
                        return None
                os.replace(temp_name, cachefile)
                temp_name = ""
                return GdkPixbuf.Pixbuf.new_from_file(cachefile)
            finally:
                if temp_name:
                    try:
                        os.unlink(temp_name)
                    except OSError:
                        pass
        except Exception:
            return None

    def _decode_pixbuf(self, path, size):
        """Produce a GdkPixbuf for `path` at the exact box (worker thread).

        Preference order: exact-box disk cache (mtime-validated), C imgdec
        helper (fast src->box PNG written atomically to the cache), Pillow
        DCT-scaled + LANCZOS decode, legacy gdk-pixbuf decode. Any failure
        yields None, which the main thread caches as 'broken' and paints a
        placeholder for.

        The box is often portrait (tall narrow strip) while sources are
        landscape. A width-only decode leaves the vertical axis under-resolved
        and Cairo must upscale it ~3x -> blur. The C helper now decodes,
        cover-resizes and center-crops to the exact box in one shot (box-mode,
        `imgdec <in> <W>x<H>`), so the cache is already the sharp slot. The
        Pillow/gdk fallback decodes at an aspect-aware width then centre-crops
        to the exact box, so the cached PNG is always the exact WxH slot no
        matter which decoder produced it (keeps the cache contract uniform).
        """
        width, height = size if isinstance(size, tuple) else (size, 0)
        width = max(2, int(width))
        height = max(2, int(height))
        cachefile = self._cachefile_for(path, size)
        try:
            if cachefile and os.path.isfile(cachefile) and \
                    os.path.getmtime(cachefile) >= os.path.getmtime(path):
                return GdkPixbuf.Pixbuf.new_from_file(cachefile)
        except (OSError, GLib.Error):
            pass

        pixbuf = self._imgdec_decode(path, size)
        if pixbuf is not None:
            return pixbuf

        # Safe fallbacks when the helper is unavailable. Both fallbacks decode
        # an aspect-aware width (enough to cover the box on the tight axis)
        # then centre-crop to the exact WxH box - the same cover-crop imgdec
        # does - so the PNG cached under `{md5}-{W}x{H}.png` is always the
        # exact slot size, whichever decoder published it. Only computed here
        # (not on the imgdec/cache-hit path) to keep the hot path free of the
        # header probe.
        dims = self._aspect_cache.get(path)
        if dims is None:
            dims = _probe_size(path)
            if dims is not None:
                self._aspect_cache[path] = dims
        decode_w = width
        if dims is not None and dims[0] > 0 and dims[1] > 0:
            sw, sh = dims
            if height:
                decode_w = max(width, int(math.ceil(height * (sw / sh))))
        if Image is not None:
            img = _pil_thumb(path, decode_w)
            if img is not None:
                # Cover crop to the exact box so the cache + pixbuf match the
                # WxH slot exactly (same as imgdec box-mode).
                pw, ph = img.size
                if pw >= width and ph >= height:
                    l = (pw - width) // 2
                    t = (ph - height) // 2
                    img = img.crop((l, t, l + width, t + height))
                if cachefile is not None:
                    try:
                        buf = io.BytesIO()
                        img.save(buf, format="PNG")
                        self._atomic_write(cachefile, buf.getvalue())
                    except Exception:
                        pass
                try:
                    # pure C conversion, thread-safe off the GTK main loop
                    return GdkPixbuf.Pixbuf.new_from_data(
                        img.tobytes(), GdkPixbuf.Colorspace.RGB, False, 8,
                        img.width, img.height, img.width * 3, None, None)
                except Exception:
                    pass
        return _gdk_decode(path, decode_w)

    def _load_worker(self):
        """Pop decode jobs and post pixbufs back to the main thread.

        Several instances run in parallel (see __init__): Pillow releases
        the GIL inside libjpeg/resize so threads genuinely overlap decode
        work. gdk-pixbuf conversion is pure C and thread-safe - only
        drawing must stay on the GTK main thread.
        """
        while True:
            with self.load_cond:
                while not self.load_q:
                    self.load_cond.wait()
                idx, path, key, size = self.load_q.popleft()
            if key in self.cache:
                continue  # decoded by another job while this one sat queued
            with self.load_cond:
                if key in self._inflight:
                    continue  # a sibling worker is already decoding this key
                self._inflight.add(key)
            try:
                pixbuf = self._decode_pixbuf(path, size)
            finally:
                with self.load_cond:
                    self._inflight.discard(key)
            GLib.idle_add(self._on_pixbuf_ready, idx, key, pixbuf)

    def _on_pixbuf_ready(self, index, key, pixbuf):
        """Main-thread landing pad for worker results: cache, repaint, and
        hop past the focused item when its hero failed to decode.

        Keeps nearby strips but caps expensive full-size hero pixbufs and
        purges Cairo-surface cache entries no longer referenced.
        """
        self.pf_queued.discard(key)
        self.cache[key] = pixbuf
        if len(self.cache) > MAX_CACHE:
            stale_count = len(self.cache) - MAX_CACHE
            for stale_key in list(self.cache.keys())[:stale_count]:
                self.cache.pop(stale_key, None)
        if pixbuf is None and self.visible and \
                key == (self.visible[self.target], "hero"):
            self._advance_past_broken()
        else:
            self._queue_carousel_draw()
        # Keep at most 3 hero keys + the current hero; drop the rest so the
        # memory-hungry full-size decodes don't pile up on navigation.
        hero_keys = [cached_key for cached_key in self.cache
                     if cached_key[1] == "hero"]
        current_key = ((self.visible[self.target], "hero")
                       if self.visible else None)
        for stale_key in hero_keys:
            if len(hero_keys) <= 3:
                break
            if stale_key == current_key:
                continue
            self.cache.pop(stale_key, None)
            hero_keys.remove(stale_key)
        live_pixbuf_ids = {id(cached) for cached in self.cache.values()
                           if cached is not None}
        if self._last_hero_pixbuf is not None:
            live_pixbuf_ids.add(id(self._last_hero_pixbuf))
        for cache_key in list(self._surface_cache):
            if cache_key not in live_pixbuf_ids:
                self._surface_cache.pop(cache_key, None)
        return GLib.SOURCE_REMOVE

    def _advance_past_broken(self):
        """If the focused item failed to decode, hop to the next good one."""
        n = len(self.visible)
        if not n:
            return False
        for _ in range(n):
            if self.visible[self.target] not in self.cache or \
                    self.cache.get((self.visible[self.target], "hero")) is not None:
                break
            self.target = (self.target + 1) % n
        self.pos = float(self.target)
        self._logical_target = float(self.target)
        self.queue_draw()
        return False

    def prefetch_soon(self):
        """Schedule a low-priority idle preload of nearby strips + hero."""
        if self.pf_pending:
            return
        self.pf_pending = True
        GLib.idle_add(self._prefetch, priority=GLib.PRIORITY_LOW)

    def _prefetch(self):
        """Prefetch strips immediately, but debounce the costly hero decode."""
        self.pf_pending = False
        count = len(self.visible)
        if not count:
            return GLib.SOURCE_REMOVE
        allocation = self.get_allocation()
        metrics = self._metrics(allocation.width, allocation.height)
        if self._hero_timer_id is None:
            hero_size = self._target_width("hero", metrics)
            index = self.target % count
            path = self.visible[index]
            self._enqueue((path, "hero"), path, hero_size, index)
            if self.anim_id is None and count > 2:
                with self.load_cond:
                    for neighbor in ((self.target - 1) % count,
                                     (self.target + 1) % count):
                        neighbor_path = self.visible[neighbor]
                        key = (neighbor_path, "hero")
                        if key in self.cache or key in self.pf_queued or \
                                len(self.load_q) >= LOAD_QUEUE_MAX:
                            continue
                        self.pf_queued.add(key)
                        self.load_q.append(
                            (neighbor, neighbor_path, key, hero_size))
                    self.load_cond.notify_all()
        strip_size = self._target_width("strip", metrics)
        for offset in range(1, PREFETCH_RADIUS + 1):
            for index in ((self.target + offset) % count,
                          (self.target - offset) % count):
                path = self.visible[index]
                self._enqueue((path, "strip"), path, strip_size, index)
        return GLib.SOURCE_REMOVE

    # ---------------------------------------------------------------- input

    def step(self, delta):
        """Advance on an unwrapped axis so crossing n-1 -> 0 stays forward."""
        count = len(self.visible)
        if count < 2:
            return
        destination = self._logical_target + delta
        self.animate_to(destination, int(round(destination)) % count)

    def select_index(self, idx):
        """Animate to an arbitrary index via the shortest circular path."""
        n = len(self.visible)
        if not n:
            return
        diff = (idx - self.pos) % n
        if diff > n / 2.0:
            diff -= n
        self.animate_to(self.pos + diff, idx % n)

    def animate_to(self, dest_pos, target_idx):
        """Start/re-target the OutCubic glide, clocked by the frame clock.

        Under fast key-repeat the hero decode is debounced with a short
        timer (HERO_DEBOUNCE_MS) so a full-size decode is only requested once
        the rapid retargeting has settled.
        """
        self._logical_target = float(dest_pos)
        # Snap to within one step of the destination so at most ONE
        # hero<->strip morph is ever on screen and pos always catches up
        # with the caption index.
        gap = dest_pos - self.pos
        if abs(gap) > 1.5:
            self.pos = dest_pos - (1.0 if gap > 0 else -1.0)
        self.anim_from = self.pos
        self.anim_to = float(dest_pos)
        frame_clock = self.get_frame_clock()
        self.anim_t0 = (frame_clock.get_frame_time() if frame_clock
                        else GLib.get_monotonic_time())
        self.target = target_idx % max(1, len(self.visible))
        now = GLib.get_monotonic_time()
        rapid_repeat = (self._last_retarget_us > 0 and
                        now - self._last_retarget_us < RAPID_RETARGET_US)
        self._last_retarget_us = now
        self._cancel_hero_timer()
        if rapid_repeat:
            self._hero_timer_id = GLib.timeout_add(
                HERO_DEBOUNCE_MS, self._request_settled_hero)
        else:
            self._request_settled_hero()
        if self.anim_id is None:
            self.anim_id = self.add_tick_callback(self._animation_frame)
        self.prefetch_soon()
        self._queue_carousel_draw()

    def _animation_frame(self, _widget, frame_clock, *_data):
        """Advance exactly once per compositor frame (OutCubic easing)."""
        elapsed = frame_clock.get_frame_time() - self.anim_t0
        progress = elapsed / (ANIM_MS * 1000.0)
        if progress >= 1.0:
            self.pos = self.anim_to
            self.anim_id = None
            self.prefetch_soon()
            self._queue_carousel_draw()
            return GLib.SOURCE_REMOVE
        eased = _out_cubic(max(0.0, min(progress, 1.0)))
        self.pos = self.anim_from + (self.anim_to - self.anim_from) * eased
        self._queue_carousel_draw()
        return GLib.SOURCE_CONTINUE

    def _stop_animation(self):
        """Detach the frame-clock callback, if one is active."""
        if self.anim_id is None:
            return
        try:
            self.remove_tick_callback(self.anim_id)
        except (ValueError, GLib.Error):
            pass
        self.anim_id = None

    def _cancel_hero_timer(self):
        """Cancel a deferred full-size hero decode."""
        if self._hero_timer_id is None:
            return
        try:
            GLib.source_remove(self._hero_timer_id)
        except GLib.Error:
            pass
        self._hero_timer_id = None

    def _request_settled_hero(self):
        """Decode the hero only after key-repeat has settled briefly."""
        self._hero_timer_id = None
        if not self.visible:
            return GLib.SOURCE_REMOVE
        allocation = self.get_allocation()
        metrics = self._metrics(allocation.width, allocation.height)
        index = self.target % len(self.visible)
        path = self.visible[index]
        self._enqueue((path, "hero"), path,
                      self._target_width("hero", metrics), index)
        return GLib.SOURCE_REMOVE

    def _queue_carousel_draw(self):
        """Invalidate only the moving shelf, not the full-screen dimmer."""
        allocation = self.get_allocation()
        metrics = self._metrics(allocation.width, allocation.height)
        top = max(0, int(metrics["cy"] - metrics["hero_h"] / 2.0) - 3)
        bottom = min(allocation.height,
                     int(metrics["cy"] + metrics["hero_h"] / 2.0 +
                         CAPTION_PX + 24.0))
        self.queue_draw_area(0, top, allocation.width, max(1, bottom - top))

    def rebuild_filter(self):
        """Apply self.filter_text over basenames (case-insensitive substring).

        Cancels obsolete animation/decode work before filtering so a rebuild
        never resurrects a stale glide or its hero decode.
        """
        self._cancel_hero_timer()
        self._stop_animation()
        with self.load_cond:
            for job in self.load_q:
                self.pf_queued.discard(job[2])
            self.load_q.clear()
        needle = self.filter_text.lower()
        self.visible = [p for p in self.files
                        if needle in os.path.splitext(os.path.basename(p))[0].lower()]
        self.pos = 0.0
        self.target = 0
        self.anim_id = None  # any in-flight glide is moot after a rebuild
        self._logical_target = float(self.target)
        self.prefetch_soon()
        self.queue_draw()

    def on_key_press(self, _win, event):
        keyval = Gdk.keyval_name(event.keyval) or ""
        mods = event.state & (Gdk.ModifierType.CONTROL_MASK
                              | Gdk.ModifierType.MOD1_MASK
                              | Gdk.ModifierType.MOD4_MASK)
        if keyval in ("Left", "KP_Left"):
            self.step(-1)
        elif keyval in ("Right", "KP_Right"):
            self.step(1)
        elif keyval in ("Home", "KP_Home"):
            self.select_index(0)
        elif keyval in ("End", "KP_End"):
            self.select_index(len(self.visible) - 1)
        elif keyval in ("Return", "KP_Enter", "ISO_Enter"):
            self.apply()
        elif keyval in ("Escape",):
            self.quit()
        elif keyval == "BackSpace":
            if self.filter_text:
                self.filter_text = self.filter_text[:-1]
                self.rebuild_filter()
        elif not mods:
            text = event.string or ""
            if text and all(ch.isprintable() and ch != "\x7f" for ch in text):
                self.filter_text += text.lower()
                self.rebuild_filter()
        return True  # modal: swallow everything so dwm never sees it

    def on_scroll(self, _win, event):
        direction = event.direction
        if direction == Gdk.ScrollDirection.SMOOTH:
            ok, _dx, dy = event.get_scroll_deltas()
            if ok and dy:
                self.scroll_acc += dy
                while self.scroll_acc >= 1.0:
                    self.step(1)
                    self.scroll_acc -= 1.0
                while self.scroll_acc <= -1.0:
                    self.step(-1)
                    self.scroll_acc += 1.0
        elif direction in (Gdk.ScrollDirection.DOWN, Gdk.ScrollDirection.RIGHT):
            self.step(1)
        elif direction in (Gdk.ScrollDirection.UP, Gdk.ScrollDirection.LEFT):
            self.step(-1)
        else:
            self.scroll_acc = 0.0
        return True

    def on_button_press(self, _win, event):
        if event.button != 1:
            return True
        px, py = event.x, event.y
        for idx, x, y, w, h in reversed(self.hit_rects):
            if x <= px <= x + w and y <= py <= y + h:
                self.select_index(idx)
                if event.type == Gdk.EventType.DOUBLE_BUTTON_PRESS:
                    self.apply()
                break
        return True

    # ---------------------------------------------------------------- paint

    def _rounded_path(self, cr, x, y, w, h, r):
        r = max(0.0, min(r, w / 2.0, h / 2.0))
        cr.new_sub_path()
        cr.arc(x + r, y + r, r, math.pi, 1.5 * math.pi)
        cr.arc(x + w - r, y + r, r, 1.5 * math.pi, 2.0 * math.pi)
        cr.arc(x + w - r, y + h - r, r, 0, 0.5 * math.pi)
        cr.arc(x + r, y + h - r, r, 0.5 * math.pi, math.pi)
        cr.close_path()

    def _paint_pixbuf(self, cr, pixbuf, x, y, w, h, mode):
        """Draw pixbuf into rect, reusing a cached Cairo surface per pixbuf.

        'cover' crops (CSS object-fit: cover), 'contain' letterboxes (aspect
        preserved, centred). Falls back to a per-frame gdk conversion if a
        Cairo surface cannot be built.
        """
        cache_key = id(pixbuf)
        cached = self._surface_cache.get(cache_key)
        if cached is None or cached[0] is not pixbuf:
            try:
                surface = Gdk.cairo_surface_create_from_pixbuf(
                    pixbuf, 1, self.get_window())
            except Exception:
                self._paint_pixbuf_legacy(cr, pixbuf, x, y, w, h, mode)
                return
            cached = (pixbuf, surface)
            self._surface_cache[cache_key] = cached
        surface = cached[1]
        source_width = pixbuf.get_width()
        source_height = pixbuf.get_height()
        if source_width <= 0 or source_height <= 0:
            return
        if mode == "contain":
            scale = min(w / source_width, h / source_height)
        else:
            scale = max(w / source_width, h / source_height)
        destination_x = x + (w - source_width * scale) / 2.0
        destination_y = y + (h - source_height * scale) / 2.0
        cr.save()
        cr.rectangle(x, y, w, h)
        cr.clip()
        cr.translate(destination_x, destination_y)
        cr.scale(scale, scale)
        cr.set_source_surface(surface, 0, 0)
        cr.paint()
        cr.restore()

    def _paint_pixbuf_legacy(self, cr, pixbuf, x, y, w, h, mode):
        """Fallback when a Cairo surface cannot be built (pure gdk path)."""
        pw, ph = pixbuf.get_width(), pixbuf.get_height()
        if pw <= 0 or ph <= 0:
            return
        scale = (min(w / pw, h / ph) if mode == "contain" else max(w / pw, h / ph))
        dx = x + (w - pw * scale) / 2.0
        dy = y + (h - ph * scale) / 2.0
        cr.save()
        cr.rectangle(x, y, w, h)
        cr.clip()
        cr.translate(dx, dy)
        cr.scale(scale, scale)
        Gdk.cairo_set_source_pixbuf(cr, pixbuf, 0, 0)
        cr.paint()
        cr.restore()

    def _draw_text(self, win, cr, text, x, y, px, color, center=False,
                   max_width=None):
        """Render one mono text line; returns consumed height in px."""
        layout = win.create_pango_layout(text)
        desc = Pango.FontDescription.from_string(FONT_STACK)
        desc.set_absolute_size(px * Pango.SCALE)
        layout.set_font_description(desc)
        if max_width is not None:
            layout.set_width(int(max_width * Pango.SCALE))
            layout.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        lw, lh = layout.get_pixel_size()
        cr.save()
        cr.set_source_rgb(*color)
        cr.move_to(x - lw / 2.0 if center else x, y)
        PangoCairo.show_layout(cr, layout)
        cr.restore()
        return lh

    def on_draw(self, win, cr):
        alloc = win.get_allocation()
        m = self._metrics(alloc.width, alloc.height)
        n = len(self.visible)
        self.hit_rects = []

        # dimmed backdrop - real ARGB transparency when a compositor allows it,
        # otherwise a solid near-black fallback so the picker stays readable.
        if self.rgba_ok and win.get_visual() == win.get_screen().get_rgba_visual():
            cr.set_source_rgba(0.0, 0.0, 0.0, OVERLAY_ALPHA)
        else:
            cr.set_source_rgb(0.04, 0.035, 0.035)
        cr.set_operator(cairo.Operator.SOURCE)
        cr.paint()
        cr.set_operator(cairo.Operator.OVER)

        if n:
            base = math.floor(self.pos)
            fraction = self.pos - base
            cells = []
            # With floor(pos), the negative end already acts as the guard
            # during reverse motion; only one extra positive cell is needed.
            guard = m["max_side"] + 1
            for offset in range(-m["max_side"], guard + 1):
                relative = offset - fraction
                if abs(relative) > guard + 1:
                    continue
                index = (base + offset) % n
                cells.append((abs(relative), relative, index))
            cells.sort(reverse=True)  # farthest first, hero painted last

            for _, relative, index in cells:
                x, y, w, h, alpha = self._frame_for(relative, m)
                path = self.visible[index]
                # Both cells in the hero<->strip morph use the hero lookup for
                # the whole transition; _pixbuf falls back to that wallpaper's
                # strip/last-hero thumbnail via a 1.0 cutoff (0.5 would switch
                # the outgoing hero to an uncached strip mid-first-move).
                hero_zone = abs(relative) < 1.0
                pixbuf = self._pixbuf(path, "hero" if hero_zone else "strip",
                                      m, index)
                # Skip cells not yet on screen (guard cell crossing in).
                if x >= m["w"] or x + w <= 0.0:
                    continue
                cr.save()
                self._rounded_path(cr, x, y, w, h, 2.0)
                cr.clip()
                cr.set_source_rgb(*PLACEHOLDER)
                cr.fill()  # opaque backing plate inside the frame area
                if pixbuf is not None:
                    self._paint_pixbuf(cr, pixbuf, x, y, w, h, "cover")
                if alpha > 0.003:
                    cr.set_source_rgba(0.0, 0.0, 0.0, alpha)
                    cr.paint()
                cr.restore()
                self.hit_rects.append((index, x, y, w, h))

            # fixed salmon frame around the hero slot
            cr.save()
            self._rounded_path(cr, m["cx"] - m["hero_w"] / 2.0,
                               m["cy"] - m["hero_h"] / 2.0,
                               m["hero_w"], m["hero_h"], 2.0)
            cr.set_source_rgb(*SALMON)
            cr.set_line_width(3.0)
            cr.stroke()
            cr.restore()

            # caption + hint under the hero
            name = os.path.splitext(os.path.basename(self.visible[self.target]))[0]
            caption_y = m["cy"] + m["hero_h"] / 2.0 + 16.0
            self._draw_text(win, cr, name, m["cx"], caption_y, CAPTION_PX,
                            SALMON, center=True, max_width=m["w"] * 0.5)
            self._draw_text(win, cr,
                            "\u2190 navigate \u00b7 Enter apply \u00b7 Esc cancel "
                            "\u00b7 type to filter",
                            m["cx"], caption_y + CAPTION_PX + 8.0, HINT_PX,
                            HINT_INK, center=True)
        else:
            msg = ("no wallpapers found in collection"
                   if not self.files else "no matches for filter")
            self._draw_text(win, cr, msg, m["cx"], m["cy"], CAPTION_PX,
                            HINT_INK, center=True)

        # filter indicator, bottom-left corner
        if self.filter_text:
            label = "filter: %s_  \u00b7  %d/%d" % (
                self.filter_text, n, len(self.files))
            self._draw_text(win, cr, label, 16.0, m["h"] - FILTER_PX - 18.0,
                            FILTER_PX, HINT_INK)
        return False


def main(argv=None):
    args_parser = argparse.ArgumentParser(
        prog="wallpicker.py",
        description="Fullscreen filmstrip wallpaper picker for dwm (GTK3).")
    args_parser.add_argument("--dir", default="~/Pictures/Wallpapers",
                             help="wallpaper directory (recursive; default: "
                                  "~/Pictures/Wallpapers)")
    args_parser.add_argument("--dry-run", action="store_true",
                             help="list what would be shown, then exit")
    args = args_parser.parse_args(argv)

    if not os.environ.get("DISPLAY"):
        sys.stderr.write("wallpicker: no X display available "
                         "(DISPLAY is not set); refusing to start.\n")
        return 1

    root = os.path.expanduser(args.dir)
    if not os.path.isdir(root):
        sys.stderr.write("wallpicker: directory not found: %s\n" % root)
        return 1

    files = find_wallpapers(root)
    if args.dry_run:
        print("%d wallpapers under %s" % (len(files), root))
        if files:
            print("first: %s" % files[0])
            print("last:  %s" % files[-1])
        return 0
    if not files:
        sys.stderr.write("wallpicker: no jpg/jpeg/png/images under %s\n" % root)
        return 1

    picker = Picker(files)
    picker.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
