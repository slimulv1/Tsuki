#!/usr/bin/env python3
"""wallpicker.py - fullscreen filmstrip wallpaper picker for dwm (GTK3 / PyGObject).

A rofi replacement: the focused wallpaper opens as a large centred HERO
preview while the rest flank it as thin receding strips (a shelf). Selection
changes glide on an OutCubic slide - the animation rofi can never do.

Layout mirrors the ryoku quickshell reference (LayoutStrips.qml):
  hero    = 46% of screen height, drawn aspect-fit inside a 16:9 frame,
            3px salmon (#e08a80) border, 2px corner radius
  strips  = width 5% of screen height, height 80% of hero height, gap 10px,
            crop-fill (object-fit: cover), black overlay
            alpha = min(0.40, 0.14 + |dist-to-hero| * 0.05)

stdout contract (for dwm keybind pipes such as `wallpicker.py | feh --bg-fill ...`):
  Enter -> prints the absolute wallpaper path, exit 0
  Esc   -> prints nothing, exit 0

Usage: wallpicker.py [--dir DIR] [--dry-run]

Implementation notes (decode/cache layer): thumbnails come from the
sibling C helper `imgdec` (libjpeg-turbo DCT-scaled decode + stb resize)
when built, else a small pool of worker threads using Pillow (JPEG DCT
downscale + LANCZOS resize); results are published to a PNG disk cache
under ~/.cache/dwmwal/picker/ (md5(path)-width.png, invalidated by source
mtime) and handed to GTK as GdkPixbufs on the worker thread. Without both,
the picker falls back to plain gdk-pixbuf scaling.
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

ANIM_MS = 320                 # OutCubic glide duration
TICK_MS = 16                  # ~60 fps animation tick
FOCUS_RETRY_MS = 50           # keyboard-focus retry cadence after map
FOCUS_RETRY_MAX = 40          # attempts before giving up (~2 s total)
GAP = 10                      # gap between neighbouring strips
HERO_H_FRAC = 0.46            # hero height / screen height
STRIP_W_FRAC = 0.05           # strip width / screen height
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


def _imgdec_bin():
    """Path of the sibling imgdec C helper when built+executable, else None."""
    exe = os.path.join(os.path.dirname(os.path.abspath(__file__)), "imgdec")
    if os.path.isfile(exe) and os.access(exe, os.X_OK):
        return exe
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
    """Recursively collect jpg/jpeg/png under root, sorted by absolute path.

    Validation is extension-only on purpose: probing every candidate with
    gdk-pixbuf dominated startup (seconds on 100+ files). Broken images are
    instead tolerated lazily - decode failures cache as None and the picker
    paints placeholders / hops past broken heroes.
    """
    wanted_exts = (".jpg", ".jpeg", ".png")
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
        self.pf_queued = set()      # (path, kind) keys awaiting decode
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
        self.set_default_size(screen.get_width(), screen.get_height())

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

    # ------------------------------------------------------------ lifecycle

    def quit(self):
        """Leave without printing anything (cancel path)."""
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
        """One focus/grab attempt; True keeps the retry source alive."""
        if self.focus_dead:
            self.focus_timer_id = None
            return GLib.SOURCE_REMOVE
        try:
            gdk_win = self.get_window()
            if gdk_win is None:
                return self._retry_failed("no gdk window yet")
            gdk_win.focus(Gdk.CURRENT_TIME)   # XSetInputFocus, WM-independent
            if self.focus_attempts == 0:
                self.present()                # WM-level activate, once enough
            self.grab_focus()
            status = Gdk.keyboard_grab(gdk_win, True, Gdk.CURRENT_TIME)
        except Exception as exc:
            return self._retry_failed(exc)
        if status == Gdk.GrabStatus.SUCCESS:
            return GLib.SOURCE_REMOVE         # keyboard ours - done retrying
        return self._retry_failed(status)

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
        """All layout constants derived per-frame from the screen size."""
        hero_h = height * HERO_H_FRAC
        hero_w = min(hero_h * 16.0 / 9.0, width * HERO_MAX_W_FRAC)
        hero_h = hero_w * 9.0 / 16.0  # keep exact 16:9 after the width clamp
        strip_w = max(2.0, height * STRIP_W_FRAC)
        strip_h = hero_h * STRIP_H_FRAC
        cx = width / 2.0
        cy = height * CY_FRAC
        max_side = int((width / 2.0) / (strip_w + GAP)) + 1
        return {
            "w": width, "h": height,
            "hero_w": hero_w, "hero_h": hero_h,
            "strip_w": strip_w, "strip_h": strip_h,
            "cx": cx, "cy": cy,
            "max_side": min(max_side, 18),
        }

    def _slot_rect(self, i, side, m):
        """Rectangle of the i-th (integer, i >= 1) strip on `side` of the hero."""
        dist = (i - 1) * (m["strip_w"] + GAP) + GAP
        w, h = m["strip_w"], m["strip_h"]
        if side >= 0:
            x = m["cx"] + m["hero_w"] / 2.0 + dist
        else:
            x = m["cx"] - m["hero_w"] / 2.0 - dist - w
        return x, m["cy"] - h / 2.0, w, h

    def _frame_for(self, rel, m):
        """Geometry + darkness for an item at fractional distance `rel`.

        Morph zone is |rel| < 0.5 — cells are spaced exactly 1.0 apart, so at
        most ONE cell can ever sit in the zone. With the old |rel| < 1.0 zone,
        a fractional pos (inevitable during key-repeat) put TWO half-shrunk
        previews inside the hero frame at once. Beyond 0.5 the strips glide
        continuously (dist grows linearly from the first slot), so the belt
        motion stays seamless and the morph completes in the first half of
        the approach to the hero.
        """
        ar = abs(rel)
        side = 1.0 if rel >= 0 else -1.0
        hx = m["cx"] - m["hero_w"] / 2.0
        hy = m["cy"] - m["hero_h"] / 2.0
        if ar < 0.5:
            t = ar * 2.0
            sx, sy, sw, sh = self._slot_rect(1, side, m)
            return (_lerp(hx, sx, t), _lerp(hy, sy, t),
                    _lerp(m["hero_w"], sw, t), _lerp(m["hero_h"], sh, t),
                    (RECEDE_BASE + RECEDE_STEP) * t)
        dist = (ar - 0.5) * (m["strip_w"] + GAP) + GAP
        w, h = m["strip_w"], m["strip_h"]
        if side >= 0:
            x = m["cx"] + m["hero_w"] / 2.0 + dist
        else:
            x = m["cx"] - m["hero_w"] / 2.0 - dist - w
        return x, m["cy"] - h / 2.0, w, h, min(RECEDE_CAP,
                                               RECEDE_BASE + RECEDE_STEP * ar)

    # ------------------------------------------------------------- pixbufs

    @staticmethod
    def _target_width(kind, m):
        """Pixel width a slot's thumbnail decodes to (height follows ratio).

        Strips draw at ~half their on-screen size, so they decode at twice
        the strip width to stay crisp under cover-crop rescaling; heroes
        decode at exactly their frame width.
        """
        if kind == "hero":
            return max(2, int(m["hero_w"] * SS))
        return max(2, int(m["strip_w"] * SS) * 2)

    def _pixbuf(self, path, kind, m, idx):
        """Cache lookup only - decoding happens on the background workers.

        Returns the pixbuf once ready, else None so the caller paints the
        placeholder backing plate while the load is in flight. Never blocks
        the main thread, so slides stay smooth while large JPEGs decode.
        """
        key = (path, kind)
        if key in self.cache:
            return self.cache[key]
        self._enqueue(key, path, self._target_width(kind, m), idx)
        return None

    def _enqueue(self, key, path, width, idx):
        """Queue one decode job; heroes jump ahead of queued strips.

        Deduped against cached/in-flight keys and capped as a backstop -
        work dropped here is simply re-requested by the next draw or
        prefetch pass, so losing a job is always safe.
        """
        if key in self.cache or key in self.pf_queued:
            return
        job = (idx, path, key, width)
        with self.load_cond:
            if len(self.load_q) >= LOAD_QUEUE_MAX:
                return
            self.pf_queued.add(key)
            if key[1] == "hero":
                self.load_q.appendleft(job)
            else:
                self.load_q.append(job)
            self.load_cond.notify()

    @staticmethod
    def _cachefile_for(path, width):
        """PNG cache path for (path, width); None when unusable."""
        try:
            digest = hashlib.md5(os.path.abspath(path).encode()).hexdigest()
            return os.path.join(DISK_CACHE_DIR, "%s-%d.png" % (digest, width))
        except Exception:
            return None

    def _disk_cache_get(self, path, width):
        """Return an RGB image from the disk cache, or None on miss.

        Hit condition: cached PNG exists AND its mtime is not older than
        the source wallpaper's (an edited source invalidates its thumb).
        """
        cachefile = self._cachefile_for(path, width)
        if cachefile is None or not os.path.exists(cachefile):
            return None
        try:
            if os.path.getmtime(cachefile) < os.path.getmtime(path):
                return None  # stale: source is newer than cached thumb
            with Image.open(cachefile) as hit:
                return hit.convert("RGB")
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

    def _disk_cache_put(self, path, width, img):
        """Publish `img` to the disk cache atomically; best-effort only.

        Broken images (img None) are deliberately not written to disk -
        they stay as in-memory Nones so a repaired source retries later.
        """
        if img is None:
            return
        cachefile = self._cachefile_for(path, width)
        if cachefile is None:
            return
        try:
            buf = io.BytesIO()
            img.save(buf, format="PNG")
            self._atomic_write(cachefile, buf.getvalue())
        except Exception:
            pass

    def _imgdec_decode(self, path, width):
        """Fast decode via the C imgdec helper (libjpeg-turbo scaled DCT).

        Runs the sibling binary (JPEG/WebP/PNG -> width-fitted PNG),
        validates its output, hands the bytes to gdk-pixbuf and republishes
        them to the disk cache through the same atomic writer so mtime
        validation stays uniform. Any failure/timeout returns None and the
        caller falls back to Pillow/gdk silently.
        """
        exe = _imgdec_bin()
        if exe is None:
            return None
        cachefile = self._cachefile_for(path, width)
        if cachefile is not None and os.path.exists(cachefile) and \
                os.path.getmtime(cachefile) >= os.path.getmtime(path):
            return None  # disk cache will have handled it upstream
        try:
            proc = subprocess.run(
                [exe, path, str(int(width))],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                timeout=IMGDEC_TIMEOUT_S)
        except Exception:
            return None
        png = proc.stdout
        if proc.returncode != 0 or png[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        try:
            loader = GdkPixbuf.PixbufLoader.new()
            loader.write(png)
            loader.close()
            pixbuf = loader.get_pixbuf()
        except Exception:
            return None
        if cachefile is not None:
            self._atomic_write(cachefile, png)
        return pixbuf

    def _decode_pixbuf(self, path, width):
        """Produce a GdkPixbuf for `path` at `width` px (worker thread).

        Preference order: valid disk-cached PNG (~ms), C imgdec helper
        (libjpeg-turbo DCT-scaled decode + stb resize, published to disk
        cache), Pillow DCT-scaled + LANCZOS decode (published to disk
        cache), legacy gdk-pixbuf decode when both are unavailable. Any
        failure yields None, which the main thread caches as 'broken' and
        paints a placeholder for.
        """
        if Image is not None:
            img = self._disk_cache_get(path, width)
            if img is None:
                pixbuf = self._imgdec_decode(path, width)
                if pixbuf is not None:
                    return pixbuf
                img = _pil_thumb(path, width)
                self._disk_cache_put(path, width, img)
            if img is not None:
                try:
                    # pure C conversion, thread-safe off the GTK main loop
                    return GdkPixbuf.Pixbuf.new_from_data(
                        img.tobytes(), GdkPixbuf.Colorspace.RGB, False, 8,
                        img.width, img.height, img.width * 3, None, None)
                except Exception:
                    return None
        return _gdk_decode(path, width)

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
                idx, path, key, width = self.load_q.popleft()
            if key in self.cache:
                continue  # decoded by another job while this one sat queued
            GLib.idle_add(self._on_pixbuf_ready, idx, key,
                          self._decode_pixbuf(path, width))

    def _on_pixbuf_ready(self, idx, key, pixbuf):
        """Main-thread landing pad for worker results: cache, repaint, and
        hop past the focused item when its hero failed to decode."""
        self.pf_queued.discard(key)
        self.cache[key] = pixbuf
        if len(self.cache) > MAX_CACHE:
            # drop oldest entries; dict preserves insertion order
            for stale in list(self.cache.keys())[: len(self.cache) - MAX_CACHE]:
                del self.cache[stale]
        if pixbuf is None and self.visible and \
                key == (self.visible[self.target], "hero"):
            self._advance_past_broken()
        self.queue_draw()
        return False

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
        self.queue_draw()
        return False

    def prefetch_soon(self):
        """Schedule a low-priority idle preload of nearby strips + hero."""
        if self.pf_pending:
            return
        self.pf_pending = True
        GLib.idle_add(self._prefetch, priority=GLib.PRIORITY_LOW)

    def _prefetch(self):
        """Queue nearby loads in priority order: focused hero first, then
        strips radiating outward. Decoding itself runs on the worker."""
        self.pf_pending = False
        n = len(self.visible)
        if not n:
            return False
        alloc = self.get_allocation()
        m = self._metrics(alloc.width, alloc.height)
        self._enqueue((self.visible[self.target], "hero"),
                      self.visible[self.target],
                      self._target_width("hero", m), self.target)
        sw = self._target_width("strip", m)
        for off in range(1, PREFETCH_RADIUS + 1):
            for sidx in ((self.target + off) % n, (self.target - off) % n):
                self._enqueue((self.visible[sidx], "strip"),
                              self.visible[sidx], sw, sidx)
        return False

    # ---------------------------------------------------------------- input

    def step(self, delta):
        """Move selection one slot, animating a single-step circular slide.

        Retarget from self.target (not self.pos): with key-repeat the glide
        is restarted every ~33ms, so anchoring on pos would leave pos stuck
        on fractional values — two cells then sit in the morph zone (|rel|<1)
        and BOTH render as half-shrunk previews inside the hero frame.
        Anchoring on the integer target keeps pos chasing a whole number.
        """
        n = len(self.visible)
        if n < 2:
            return
        dest = self.target + delta
        self.animate_to(dest, dest % n)

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
        """Start/re-target the OutCubic glide towards dest_pos."""
        # Fast key-repeat can leave pos several steps behind the target.
        # Snap to within one step of the destination so at most ONE
        # hero<->strip morph is ever on screen and pos always catches up
        # with the caption index.
        gap = dest_pos - self.pos
        if abs(gap) > 1.5:
            self.pos = dest_pos - (1.0 if gap > 0 else -1.0)
        self.anim_from = self.pos
        self.anim_to = float(dest_pos)
        self.anim_t0 = GLib.get_monotonic_time()
        self.target = target_idx % max(1, len(self.visible))
        if self.anim_id is None:
            self.anim_id = GLib.timeout_add(TICK_MS, self.tick)
        self.prefetch_soon()
        self.queue_draw()

    def tick(self):
        """Animation timer: interpolate position, repaint, stop when settled."""
        progress = (GLib.get_monotonic_time() - self.anim_t0) / (ANIM_MS * 1000.0)
        if progress >= 1.0:
            self.pos = self.anim_to % max(1, len(self.visible))
            self.anim_id = None
            self.queue_draw()
            return False  # remove timer source
        eased = _out_cubic(min(progress, 1.0))
        self.pos = self.anim_from + (self.anim_to - self.anim_from) * eased
        self.queue_draw()
        return True

    def rebuild_filter(self):
        """Apply self.filter_text over basenames (case-insensitive substring)."""
        needle = self.filter_text.lower()
        self.visible = [p for p in self.files
                        if needle in os.path.splitext(os.path.basename(p))[0].lower()]
        self.pos = 0.0
        self.target = 0
        self.anim_id = None  # any in-flight glide is moot after a rebuild
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
        """Draw pixbuf into rect: 'cover' crops (CSS object-fit: cover),
        'contain' letterboxes (aspect preserved, centred)."""
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
            frac = self.pos - base
            cells = []
            for off in range(-m["max_side"], m["max_side"] + 1):
                rel = off - frac
                if abs(rel) > m["max_side"] + 1:
                    continue
                idx = (base + off) % n
                cells.append((abs(rel), rel, idx))
            cells.sort(reverse=True)  # farthest first, hero painted last
            for _, rel, idx in cells:
                x, y, w, h, alpha = self._frame_for(rel, m)
                path = self.visible[idx]
                is_hero_zone = abs(rel) < 0.5
                pixbuf = self._pixbuf(path, "hero" if is_hero_zone else "strip",
                                      m, idx)
                cr.save()
                self._rounded_path(cr, x, y, w, h, 2.0)
                cr.clip()
                cr.set_source_rgb(*PLACEHOLDER)
                cr.fill()  # backing plate for load gaps / transparent PNGs
                if pixbuf is not None:
                    self._paint_pixbuf(cr, pixbuf, x, y, w, h, "cover")
                if alpha > 0.003:
                    cr.set_source_rgba(0.0, 0.0, 0.0, alpha)
                    cr.paint()
                cr.restore()
                self.hit_rects.append((idx, x, y, w, h))

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
        sys.stderr.write("wallpicker: no jpg/jpeg/png images under %s\n" % root)
        return 1

    picker = Picker(files)
    picker.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
