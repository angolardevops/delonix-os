#!/usr/bin/env python3
"""
Gera todos os PNG da marca Delonix a partir de primitivas (sem depender de um
rasterizador de SVG instalado no host de build).

A marca (manual da Delonix): a flor do delonix regia lida como um **globo com
anéis de sinal e antenas de rede** — esfera central com meridianos, dois anéis
concêntricos partidos e seis antenas radiais terminadas em esfera.

Saídas:
  plymouth/   background.png logo.png wordmark.png anim-NN.png bar-* bullet.png
  sddm/       background.png logo.png ring-NN.png
  wallpaper/  <WxH>.png (várias resoluções)
  grub/       background.png logo.png
  ksplash/    background.png logo.png

Uso:  python3 branding/gen-assets.py [--out <.../usr/share>] [--fast]

Paleta:
  vermelho vivo #ef3b2c · Delonix #e0202f · escuro #a81419 · brasa #f5a623
  fundo #0d0f12 · texto #e6e8ec · ténue #8b9099
"""
from __future__ import annotations

import argparse
import math
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

RED_HOT = (239, 59, 44)
RED = (224, 32, 47)
RED_DARK = (190, 22, 30)
EMBER = (245, 166, 35)
BG = (13, 15, 18)
FG = (230, 232, 236)
MUTED = (139, 144, 153)

# Geometria da marca, em fracções do lado da imagem (medidas sobre o manual).
SPHERE_R = 0.215
RING_R = (0.320, 0.400)
RING_W = 0.026
SPOKE_IN = 0.230
SPOKE_OUT = 0.430
SPOKE_W = 0.034
KNOB_R = 0.046
SPOKE_ANGLES = (90, 30, -30, -90, 150, 210)  # seis antenas, de 60 em 60 graus

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


# ---------------------------------------------------------------- utilitários
def linear_gradient(size: int, top: tuple, bottom: tuple, diagonal: bool = True) -> Image.Image:
    """Gradiente linear (diagonal por omissão, como no manual da marca)."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = ((x + y) / (2 * (size - 1))) if diagonal else (y / (size - 1))
            px[x, y] = (
                int(top[0] + (bottom[0] - top[0]) * t),
                int(top[1] + (bottom[1] - top[1]) * t),
                int(top[2] + (bottom[2] - top[2]) * t),
            )
    return img


def paint(mask: Image.Image, top: tuple, bottom: tuple) -> Image.Image:
    """Pinta uma máscara com o gradiente da marca."""
    grad = linear_gradient(mask.width, top, bottom).convert("RGBA")
    grad.putalpha(mask)
    return grad


def sphere(size: int, *, meridians: bool = True) -> Image.Image:
    """Esfera vermelha com brilho em cima-à-esquerda e malha de meridianos."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = (size - 1) / 2
    lx, ly = c - size * 0.22, c - size * 0.24          # foco da luz
    for y in range(size):
        for x in range(size):
            dx, dy = x - c, y - c
            d = math.hypot(dx, dy) / c
            if d > 1.0:
                continue
            # sombreado esférico + brilho especular
            lit = 1.0 - min(1.0, math.hypot(x - lx, y - ly) / (size * 0.95))
            t = max(0.0, min(1.0, 0.30 + 0.70 * (1.0 - lit)))
            r = int(RED_HOT[0] + (RED_DARK[0] - RED_HOT[0]) * t)
            g = int(RED_HOT[1] + (RED_DARK[1] - RED_HOT[1]) * t)
            b = int(RED_HOT[2] + (RED_DARK[2] - RED_HOT[2]) * t)
            edge = 1.0 if d < 0.965 else max(0.0, (1.0 - d) / 0.035)
            px[x, y] = (r, g, b, int(255 * edge))

    if meridians:
        mesh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(mesh)
        w = max(1, int(size * 0.012))
        col = EMBER + (78,)
        # paralelos (elipses achatadas) e meridianos (elipses estreitas)
        for k in (-0.55, -0.2, 0.2, 0.55):
            h = size * 0.5 * math.sqrt(max(0.02, 1 - k * k))
            cy = c + k * c * 0.92
            d.ellipse([c - h, cy - h * 0.22, c + h, cy + h * 0.22], outline=col, width=w)
        for k in (-0.62, -0.25, 0.25, 0.62):
            wdt = size * 0.5 * math.sqrt(max(0.02, 1 - k * k))
            cx = c + k * c * 0.92
            d.ellipse([cx - wdt * 0.24, c - size * 0.47, cx + wdt * 0.24, c + size * 0.47],
                      outline=col, width=w)
        # recorta a malha ao disco da esfera
        clip = Image.new("L", (size, size), 0)
        ImageDraw.Draw(clip).ellipse([1, 1, size - 2, size - 2], fill=255)
        mesh.putalpha(Image.composite(mesh.split()[3], Image.new("L", (size, size), 0), clip))
        img.alpha_composite(mesh)
    return img


def logo(size: int = 256, *, ring_scale: float = 1.0, ring_alpha: float = 1.0,
         extra_ring: float | None = None, extra_alpha: float = 0.0,
         zoom: float = 1.0) -> Image.Image:
    """
    A marca Delonix. `ring_scale`/`extra_ring` servem a animação do splash:
    os anéis são ondas de sinal que se expandem a partir do globo.

    `zoom` < 1 encolhe a marca dentro da tela — é o que dá margem para a onda
    de sinal sair do corpo da marca sem ficar cortada nos cantos.
    """
    ss = 3
    s = size * ss
    c = s / 2
    sphere_r = SPHERE_R * zoom
    ring_r = tuple(r * zoom for r in RING_R)
    spoke_in, spoke_out = SPOKE_IN * zoom, SPOKE_OUT * zoom
    spoke_w, knob_r, ring_w = SPOKE_W * zoom, KNOB_R * zoom, RING_W * zoom
    mask = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(mask)

    def arc_gap(radius: float, width: float, alpha: int = 255) -> None:
        """Anel partido nos pontos onde as antenas o atravessam."""
        box = [c - radius, c - radius, c + radius, c + radius]
        gap = 7  # meia-abertura do corte, em graus
        for i, a in enumerate(sorted(SPOKE_ANGLES)):
            nxt = sorted(SPOKE_ANGLES)[(i + 1) % len(SPOKE_ANGLES)]
            start = -nxt + gap        # PIL conta ângulos ao contrário (y para baixo)
            end = -a - gap
            if end < start:
                end += 360
            d.arc(box, start=start, end=end, fill=alpha, width=int(width))

    # --- antenas ---------------------------------------------------------------
    for a in SPOKE_ANGLES:
        rad = math.radians(a)
        x0, y0 = c + math.cos(rad) * s * spoke_in, c - math.sin(rad) * s * spoke_in
        x1, y1 = c + math.cos(rad) * s * spoke_out, c - math.sin(rad) * s * spoke_out
        d.line([x0, y0, x1, y1], fill=255, width=int(s * spoke_w))
        k = s * knob_r
        d.ellipse([x1 - k, y1 - k, x1 + k, y1 + k], fill=255)

    # --- anéis de sinal --------------------------------------------------------
    for r in ring_r:
        arc_gap(s * r * ring_scale, s * ring_w, int(255 * ring_alpha))
    if extra_ring:
        arc_gap(s * extra_ring * zoom, s * ring_w * 0.8, int(255 * extra_alpha))

    img = paint(mask, RED_HOT, RED_DARK)

    # --- globo ------------------------------------------------------------------
    sph = sphere(int(s * sphere_r * 2))
    img.alpha_composite(sph, (int(c - sph.width / 2), int(c - sph.height / 2)))

    return img.resize((size, size), Image.LANCZOS)


def logo_frames(size: int, count: int = 24) -> list[Image.Image]:
    """Sequência de sinal a propagar-se: os anéis expandem e desvanecem."""
    frames = []
    for i in range(count):
        t = i / count
        scale = 0.94 + 0.10 * t                       # anéis a abrir
        alpha = 1.0 - 0.35 * t                        # a esmorecer no fim
        extra = RING_R[1] * (1.10 + 0.48 * t)         # onda a sair
        extra_a = max(0.0, 0.55 * (1.0 - t) - 0.05)
        # zoom=0.78 deixa a margem que a onda precisa para sair sem ser cortada
        frames.append(logo(size, ring_scale=scale, ring_alpha=alpha,
                           extra_ring=extra, extra_alpha=extra_a, zoom=0.78))
    return frames


def backdrop(w: int, h: int, *, glow: float = 1.0, grid: bool = True) -> Image.Image:
    """Fundo escuro com brilho radial vermelho e grelha ténue."""
    img = Image.new("RGB", (w, h), BG)
    px = img.load()
    cx, cy = w * 0.28, h * 0.78
    radius = max(w, h) * 0.75
    for y in range(h):
        for x in range(0, w, 2):
            d = math.hypot(x - cx, y - cy) / radius
            t = max(0.0, 1.0 - d) ** 3 * 0.55 * glow
            rgb = (
                int(BG[0] + (RED_DARK[0] - BG[0]) * t),
                int(BG[1] + (RED_DARK[1] - BG[1]) * t),
                int(BG[2] + (RED_DARK[2] - BG[2]) * t),
            )
            px[x, y] = rgb
            if x + 1 < w:
                px[x + 1, y] = rgb

    if grid:
        overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(overlay)
        step = max(48, w // 40)
        for x in range(0, w, step):
            d.line([(x, 0), (x, h)], fill=(255, 255, 255, 6))
        for y in range(0, h, step):
            d.line([(0, y), (w, y)], fill=(255, 255, 255, 6))
        img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")

    vig = Image.new("L", (w, h), 0)
    ImageDraw.Draw(vig).ellipse([-w * 0.25, -h * 0.25, w * 1.25, h * 1.25], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(max(w, h) // 12))
    return Image.composite(img, Image.new("RGB", (w, h), (0, 0, 0)), vig)


def wordmark(text: str = "DelonixOS", sub: str | None = None, size: int = 44) -> Image.Image:
    font = load_font(size)
    sub_font = load_font(int(size * 0.42))
    tmp = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    tw = tmp.textbbox((0, 0), text, font=font)
    sw = tmp.textbbox((0, 0), sub, font=sub_font) if sub else (0, 0, 0, 0)

    w = max(tw[2], sw[2]) + 40
    h = tw[3] + (sw[3] + 16 if sub else 0) + 24
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text(((w - tw[2]) / 2, 8), text, font=font, fill=FG + (255,))
    if sub:
        d.text(((w - sw[2]) / 2, tw[3] + 22), sub, font=sub_font, fill=MUTED + (255,))
    return img


def solid(w: int, h: int, color: tuple, alpha: int = 255) -> Image.Image:
    return Image.new("RGBA", (w, h), color + (alpha,))


def dot(size: int, color: tuple) -> Image.Image:
    ss = 4
    img = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse([0, 0, size * ss - 1, size * ss - 1], fill=color + (255,))
    return img.resize((size, size), Image.LANCZOS)


# ---------------------------------------------------------------------- main
def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--out",
        default=str(Path(__file__).resolve().parent.parent / "build/branding/usr/share"),
        help="raiz de /usr/share onde escrever (por omissão, o payload do pacote)",
    )
    ap.add_argument("--fast", action="store_true", help="só uma resolução de wallpaper")
    args = ap.parse_args()
    share = Path(args.out)

    ply = share / "plymouth/themes/delonix"
    sddm = share / "sddm/themes/delonix"
    wall = share / "wallpapers/Delonix/contents/images"
    grub = share / "grub/themes/delonix"
    lnf = share / "plasma/look-and-feel/org.delonix.desktop/contents"
    for p in (ply, sddm, wall, grub, lnf / "splash/images", lnf / "previews"):
        p.mkdir(parents=True, exist_ok=True)

    # 24 frames SEMPRE: o delonix.script tem este número fixo (não dá para
    # descobrir em run-time sem arriscar abortar o splash).
    frame_count = 24

    print("→ marca (animação de sinal)")
    frames = logo_frames(220, frame_count)

    print("→ plymouth")
    backdrop(1920, 1080).save(ply / "background.png")
    frames[0].save(ply / "logo.png")
    for i, f in enumerate(frames):
        f.save(ply / f"anim-{i:02d}.png")
    wordmark("DelonixOS", "DevOps · SRE · Platform Engineering").save(ply / "wordmark.png")
    solid(1, 1, (255, 255, 255), 38).save(ply / "bar-track.png")
    solid(1, 1, RED).save(ply / "bar-fill.png")
    dot(12, FG).save(ply / "bullet.png")

    print("→ sddm")
    backdrop(1920, 1080, glow=1.15).save(sddm / "background.png")
    logo(128).save(sddm / "logo.png")

    print("→ ksplash")
    backdrop(1920, 1080, glow=0.9).save(lnf / "splash/images/background.png")
    logo(180).save(lnf / "splash/images/logo.png")

    print("→ wallpapers")
    sizes = [(2560, 1440)] if args.fast else [(1920, 1080), (2560, 1440), (3840, 2160)]
    for w, h in sizes:
        img = backdrop(w, h, glow=0.85)
        mark = logo(int(min(w, h) * 0.16))
        img.paste(mark, (int(w * 0.5 - mark.width / 2), int(h * 0.40 - mark.height / 2)), mark)
        word = wordmark("DelonixOS", "DevOps · SRE · Platform Engineering",
                        size=int(min(w, h) * 0.030))
        img.paste(word, (int(w * 0.5 - word.width / 2), int(h * 0.40 + mark.height * 0.52)), word)
        img.save(wall / f"{w}x{h}.png")
        print(f"   {w}x{h}")

    print("→ grub")
    backdrop(1920, 1080, glow=0.6, grid=False).save(grub / "background.png")
    logo(96).save(grub / "logo.png")

    print("→ pré-visualizações")
    prev = Image.open(wall / f"{sizes[0][0]}x{sizes[0][1]}.png").resize((400, 225), Image.LANCZOS)
    prev.save(lnf / "previews/preview.png")
    prev.save(lnf / "previews/splash.png")
    prev.resize((320, 180), Image.LANCZOS).save(sddm / "preview.png")

    print("feito.")


if __name__ == "__main__":
    main()
