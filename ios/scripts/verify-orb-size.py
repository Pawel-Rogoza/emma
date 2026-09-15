#!/usr/bin/env python3
"""Sprawdza, że ikonka Emmy ma tę samą wielkość w obu renderach.

Po co: `EmmaOrb` rysuje postać na dwa sposoby — reliefem SceneKit (mruganie) albo
obrazkiem zapasowym (np. przy „Reduce Motion” albo po zejściu aplikacji do tła).
Jeśli te dwa rendery różnią się wielkością, przełączenie wygląda jak powiększanie
i zmniejszanie ikonki zamiast mrugania. Ten skrypt mierzy widoczną obwiednię postaci
na dwóch zrzutach i przerywa, gdy różnica przekracza tolerancję.

Jak zdobyć zrzuty (symulator, ekran „Emma”):
  1. Zrzuty robi `ScreenshotCaptureUITests`; katalog wskazuje `EMMA_SHOT_DIR`
     w schemacie testowym (zmienna środowiskowa nie przechodzi z `xcodebuild`).
  2. Raz uruchom test normalnie, raz z włączonym „Reduce Motion”:
         xcrun simctl spawn booted defaults write com.apple.Accessibility ReduceMotionEnabled -int 1
         xcrun simctl spawn booted notifyutil -p com.apple.accessibility.reduce.motion.status
  3. Porównaj powstałe `09-emma.png`:
         python3 ios/scripts/verify-orb-size.py --relief A/09-emma.png --still B/09-emma.png

Kod wyjścia 0 = rozmiary zgodne, 1 = różnica ponad tolerancję.
"""
import argparse
import struct
import sys
import zlib
from collections import deque

# Zakładka Emmy w zrzucie; okno wystarczające dla postaci 100–148 pt (skala 3x).
SEARCH = (300, 0, 900, 700)


def load_png(path):
    data = open(path, 'rb').read()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise SystemExit(f'{path}: to nie jest PNG')
    pos, idat, ihdr = 8, [], None
    while pos < len(data):
        (length,) = struct.unpack('>I', data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        if ctype == b'IHDR':
            ihdr = struct.unpack('>IIBBBBB', chunk)
        elif ctype == b'IDAT':
            idat.append(chunk)
        elif ctype == b'IEND':
            break
        pos += 12 + length
    width, height, depth, color, _, _, interlace = ihdr
    if depth != 8 or interlace != 0:
        raise SystemExit(f'{path}: nieobsługiwany PNG (depth={depth}, interlace={interlace})')
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color]
    raw = zlib.decompress(b''.join(idat))
    stride = width * channels
    out = bytearray(height * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if ftype == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, channels, out


def pixel(img, x, y):
    width, _, channels, buf = img
    i = (y * width + x) * channels
    return buf[i], buf[i + 1], buf[i + 2]


def largest_change_region(a, b, tol=24, min_area=400, window=SEARCH):
    """Największy spójny obszar różniący się między zrzutami — tak trafiamy w postać.

    Szukamy tylko w oknie `window`: postać na ekranie Emmy jest u góry, a pełny
    skan 1206×2622 px w czystym Pythonie trwał minuty.
    """
    width, height, _, _ = a
    wx0, wy0, wx1, wy1 = window
    wx1, wy1 = min(wx1, width - 1), min(wy1, height - 1)
    mask = bytearray(width * height)
    for y in range(wy0, wy1 + 1):
        for x in range(wx0, wx1 + 1):
            ra, ga, ba = pixel(a, x, y)
            rb, gb, bb = pixel(b, x, y)
            if abs(ra - rb) + abs(ga - gb) + abs(ba - bb) > tol:
                mask[y * width + x] = 1
    seen = bytearray(width * height)
    best = None
    for y in range(wy0, wy1 + 1):
        for x in range(wx0, wx1 + 1):
            idx = y * width + x
            if not mask[idx] or seen[idx]:
                continue
            queue, seen[idx] = deque([(x, y)]), 1
            count = 0
            minx = maxx = x
            miny = maxy = y
            while queue:
                cx, cy = queue.popleft()
                count += 1
                minx, maxx = min(minx, cx), max(maxx, cx)
                miny, maxy = min(miny, cy), max(maxy, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < width and 0 <= ny < height:
                        ni = ny * width + nx
                        if mask[ni] and not seen[ni]:
                            seen[ni] = 1
                            queue.append((nx, ny))
            if count >= min_area and (best is None or count > best[0]):
                best = (count, (minx, miny, maxx, maxy))
    return best[1] if best else None


def visible_size(img, box, tol=40):
    x0, y0, x1, y1 = box
    ring = []
    for x in range(x0, x1 + 1):
        ring.append(pixel(img, x, y0))
        ring.append(pixel(img, x, y1))
    for y in range(y0, y1 + 1):
        ring.append(pixel(img, x0, y))
        ring.append(pixel(img, x1, y))
    bg = tuple(sorted(c[i] for c in ring)[len(ring) // 2] for i in range(3))
    minx = miny = maxx = maxy = None
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            r, g, b = pixel(img, x, y)
            if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > tol:
                minx = x if minx is None else min(minx, x)
                maxx = x if maxx is None else max(maxx, x)
                miny = y if miny is None else min(miny, y)
                maxy = y if maxy is None else max(maxy, y)
    if minx is None:
        return None
    return (maxx - minx + 1, maxy - miny + 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--relief', required=True, help='zrzut z renderem 3D (mruganie)')
    parser.add_argument('--still', required=True, help='zrzut z obrazkiem zapasowym')
    parser.add_argument('--max-diff', type=float, default=0.02,
                        help='dopuszczalna różnica rozmiaru, domyślnie 2%%')
    args = parser.parse_args()

    relief, still = load_png(args.relief), load_png(args.still)
    if relief[:2] != still[:2]:
        raise SystemExit('Zrzuty mają różne wymiary — porównaj zrzuty z tego samego urządzenia.')
    region = largest_change_region(relief, still)
    if region is None:
        raise SystemExit('Nie znalazłem różnicy między zrzutami — czy oba pokazują ekran Emmy?')
    pad = 24
    window = (max(0, region[0] - pad), max(0, region[1] - pad),
              min(relief[0] - 1, region[2] + pad), min(relief[1] - 1, region[3] + pad))
    size_relief = visible_size(relief, window)
    size_still = visible_size(still, window)
    if size_relief is None or size_still is None:
        raise SystemExit('Nie znalazłem postaci w wyciętym oknie.')

    print(f'Postać w reliefie:  {size_relief[0]}x{size_relief[1]} px')
    print(f'Postać w obrazku:   {size_still[0]}x{size_still[1]} px')
    ratios = [abs(size_relief[i] / size_still[i] - 1) for i in (0, 1)]
    print(f'Różnica: szerokość {ratios[0] * 100:.2f}%, wysokość {ratios[1] * 100:.2f}%'
          f' (tolerancja {args.max_diff * 100:.1f}%)')
    if max(ratios) > args.max_diff:
        print('BŁĄD: ikonka zmienia rozmiar przy przełączeniu renderu.')
        return 1
    print('OK: ikonka ma stały rozmiar w obu renderach.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
