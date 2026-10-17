#!/usr/bin/env python3
# Usage : python3 scripts/outils/icone.py App/Ressources/Assets.xcassets/AppIcon.appiconset (Pillow requis)
"""Icône de l'app : le réacteur de la console (anneau du son, noyau, arc de progression), sur le fond de la console."""
import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

N = 2048                      # dessin à 2x, réduit à 1024 (bords nets)
C = N / 2
R = N * 0.42                  # « R » de la console pour l'icône

def fond():
    im = Image.new("RGB", (N, N))
    px = im.load()
    for y in range(N):
        for x in range(N):
            t = (x * 0.35 + y) / (N * 1.35)                     # dégradé 160° #08111a → #050a10
            r, g, b = 8 + (5 - 8) * t, 17 + (10 - 17) * t, 26 + (16 - 26) * t
            d = math.hypot(x - C, y - C * 0.98) / (N * 0.62)    # halo #12334a au centre
            k = max(0.0, 1 - d) ** 1.6 * 0.55
            px[x, y] = (int(r + (18 - r) * k), int(g + (51 - g) * k), int(b + (74 - b) * k))
    return im

def calque():
    return Image.new("RGB", (N, N), (0, 0, 0))

def radial(d, a, r0, r1, couleur, w):
    d.line([(C + math.cos(a) * r0, C + math.sin(a) * r0), (C + math.cos(a) * r1, C + math.sin(a) * r1)], fill=couleur, width=int(w))

def arc(d, r, a0, a1, couleur, w):
    d.arc([C - r, C - r, C + r, C + r], math.degrees(a0), math.degrees(a1), fill=couleur, width=int(w))

base = fond()
lum = calque()      # lumière additive (traits vifs)
halo = calque()     # même lumière, floutée (lueur)
dl, dh = ImageDraw.Draw(lum), ImageDraw.Draw(halo)
beam = (63, 184, 255)
r0, ecart = R * 0.52, R * 0.30
for i in range(120):
    a = -math.pi / 2 + i / 120 * 2 * math.pi
    u = i / 120
    k = u * 2 if u < .5 else (1 - u) * 2
    v = 0.30 + 0.55 * (0.5 + 0.5 * math.sin(k * 7.5)) * (1.1 - 0.6 * k)    # un « spectre » de voix figé
    longue = i % 8 == 0
    l = ecart * v * (1.18 if longue else 1)
    radial(dh, a, r0, r0 + l, tuple(int(c * 0.9) for c in beam), 26 if longue else 20)
    radial(dl, a, r0, r0 + l, tuple(int(c * (0.55 + v * 0.45)) for c in beam), 9 if longue else 7)
arc(dl, r0 - R * 0.03, 0, 360, (24, 70, 98), 3)
arc(dl, r0 + ecart * 1.28, 0, 360, (16, 48, 70), 3)
# rails : trois arcs sarcelle/faisceau et trois arcs champagne
for i in range(3):
    a = i * 2 * math.pi / 3 + 0.4
    arc(dl, R * 0.95, a, a + 0.42, (97, 202, 255), 7)
    arc(dh, R * 0.95, a, a + 0.42, (60, 140, 190), 22)
    b = -a + 1.2
    arc(dl, R * 0.42, b, b + 0.6, (215, 198, 164), 8)
halo = halo.filter(ImageFilter.GaussianBlur(28))
img = ImageChops.add(ImageChops.add(base, halo), lum)
d = ImageDraw.Draw(img)
# noyau : disque sombre bordé, arc de progression, lueur intérieure
rc = R * 0.30
d.ellipse([C - rc, C - rc, C + rc, C + rc], fill=(5, 8, 12), outline=(110, 140, 162), width=5)
glow = calque(); dg = ImageDraw.Draw(glow)
arc(dg, rc + 26, -90, -90 + 250, (63, 184, 255), 30)
glow = glow.filter(ImageFilter.GaussianBlur(14))
img = ImageChops.add(img, glow)
d = ImageDraw.Draw(img)
d.arc([C - rc - 26, C - rc - 26, C + rc + 26, C + rc + 26], -90, -90 + 250, fill=(120, 205, 255), width=12)
# point du satellite
sa = -2.2
sx, sy = C + math.cos(sa) * R * 1.02, C + math.sin(sa) * R * 1.02
d.ellipse([sx - 12, sy - 12, sx + 12, sy + 12], fill=(191, 230, 255))
img = img.resize((1024, 1024), Image.LANCZOS)
sortie = sys.argv[1]
img.save(sortie + "/AppIcon.png")
img.save(sortie + "/AppIcon-Sombre.png")
img.convert("L").point(lambda p: min(255, int(p * 1.6))).save(sortie + "/AppIcon-Teinte.png")
