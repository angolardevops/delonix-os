#!/usr/bin/env python3
"""
Monta pré-visualizações dos ecrãs do DelonixOS a partir dos assets reais.

IMPORTANTE: isto NÃO são capturas de ecrã. São montagens que usam os PNG
gerados pelo `gen-assets.py` e as coordenadas/cores escritas nos ficheiros de
tema (delonix.script, Main.qml, theme.txt, o layout do painel). Servem para ver
e decidir o desenho antes de existir uma ISO — e para o README ter alguma coisa
que mostre a distro enquanto a primeira imagem não é construída.

O que é fiel:  GRUB e Plymouth — as posições vêm do tema e são geometria simples.
O que é aproximado: SDDM e desktop — quem os desenha é o Qt e o Plasma, com as
suas fontes e o seu anti-aliasing. As cores, tamanhos e a disposição são os do
código; o resultado final terá o polimento do toolkit.

Uso:  python3 branding/preview.py [--out build/preview]
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# As mesmas constantes do gen-assets.py e dos ficheiros de tema.
RED = (224, 32, 47)
RED_DARK = (138, 15, 24)
ACCENT = (190, 22, 34)
BG = (13, 15, 18)
FG = (230, 232, 236)
MUTED = (139, 144, 153)
SURFACE = (22, 25, 30)
BORDER = (38, 42, 49)
CARD = (22, 25, 30)

FONTES = {
    "bold": ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
             "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"],
    "regular": ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                "/usr/share/fonts/TTF/DejaVuSans.ttf"],
    "mono": ["/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
             "/usr/share/fonts/TTF/DejaVuSansMono.ttf"],
}


def fonte(estilo: str, tamanho: int) -> ImageFont.FreeTypeFont:
    for caminho in FONTES[estilo]:
        if os.path.exists(caminho):
            return ImageFont.truetype(caminho, tamanho)
    return ImageFont.load_default()


def centrado(d: ImageDraw.ImageDraw, y: int, texto: str, f, cor, largura: int) -> int:
    caixa = d.textbbox((0, 0), texto, font=f)
    d.text(((largura - caixa[2]) / 2, y), texto, font=f, fill=cor)
    return caixa[3] - caixa[1]


def rodape(img: Image.Image, texto: str) -> Image.Image:
    """
    Uma imagem partilhada perde o contexto em que foi mostrada. A ressalva vai
    dentro dela, não na legenda.

    ESTENDE a tela em vez de escrever por cima: escrever por cima taparia o
    painel do Plasma e o relógio do SDDM, que são precisamente o que se quer ver.
    """
    faixa = 30
    nova = Image.new("RGB", (img.width, img.height + faixa), (0, 0, 0))
    nova.paste(img.convert("RGB"), (0, 0))
    d = ImageDraw.Draw(nova)
    d.text((12, img.height + 8), texto, font=fonte("regular", 13), fill=(125, 125, 125))
    return nova


# ---------------------------------------------------------------------- GRUB
def grub(assets: Path, larg=1280, alt=720) -> Image.Image:
    """Fiel: as posições são as do theme.txt."""
    img = Image.open(assets / "grub/themes/delonix/background.png").resize((larg, alt))
    img = img.convert("RGB")
    d = ImageDraw.Draw(img)

    # Estes valores espelham o theme.txt à mão. Se mexeres num, mexe no outro —
    # é precisamente esta pré-visualização que apanhou a sobreposição a 720p.
    logo = Image.open(assets / "grub/themes/delonix/logo.png").resize((96, 96))
    img.paste(logo, (larg // 2 - 48, int(alt * 0.10)), logo)

    centrado(d, int(alt * 0.26), "DelonixOS", fonte("bold", 20), FG, larg)
    centrado(d, int(alt * 0.31), "DevOps · SRE · Platform Engineering",
             fonte("regular", 12), MUTED, larg)

    # boot_menu: left = 50%-260, top = 40%, item_height = 34
    x0, y0 = larg // 2 - 260, int(alt * 0.40)
    entradas = [("DelonixOS (linux612)", True),
                ("DelonixOS (linux612 fallback)", False),
                ("Memory test (memtest86+)", False),
                ("UEFI Firmware Settings", False)]
    fi = fonte("regular", 14)
    for i, (texto, seleccionada) in enumerate(entradas):
        y = y0 + i * 38
        if seleccionada:
            d.rectangle([x0 - 10, y - 6, x0 + 520, y + 26], fill=(30, 34, 41))
            d.rectangle([x0 - 10, y - 6, x0 - 7, y + 26], fill=RED)
        d.text((x0 + 8, y), texto, font=fi, fill=FG if seleccionada else MUTED)

    # progress_bar do timeout
    bx, by = larg // 2 - 260, int(alt * 0.88)
    d.rectangle([bx, by, bx + 520, by + 3], fill=BORDER)
    d.rectangle([bx, by, bx + 340, by + 3], fill=RED)
    centrado(d, int(alt * 0.92), "e: editar · c: consola · setas: navegar",
             fonte("regular", 11), (74, 80, 88), larg)
    return rodape(img, "montagem a partir do tema real (theme.txt) — não é uma captura de ecrã")


# ------------------------------------------------------------------ Plymouth
def plymouth(assets: Path, frame: int = 8, larg=1280, alt=720) -> Image.Image:
    """Fiel: as posições são as calculadas pelo delonix.script."""
    img = Image.open(assets / "plymouth/themes/delonix/background.png").resize((larg, alt)).convert("RGB")

    logo = Image.open(assets / f"plymouth/themes/delonix/anim-{frame:02d}.png")
    lx = larg // 2 - logo.width // 2
    ly = alt // 2 - logo.height // 2 - 60
    img.paste(logo, (lx, ly), logo)

    word = Image.open(assets / "plymouth/themes/delonix/wordmark.png")
    img.paste(word, (larg // 2 - word.width // 2, ly + logo.height + 24), word)

    d = ImageDraw.Draw(img)
    bw, bh = larg // 4, 3
    bx, by = larg // 2 - bw // 2, alt * 3 // 4
    d.rectangle([bx, by, bx + bw, by + bh], fill=(60, 62, 66))
    d.rectangle([bx, by, bx + int(bw * 0.62), by + bh], fill=RED)
    return rodape(img, "montagem a partir do tema real (delonix.script, frame 8/24) — não é uma captura")


# ---------------------------------------------------------------------- SDDM
def sddm(assets: Path, larg=1280, alt=720) -> Image.Image:
    """Aproximado: os valores são os do Main.qml, o desenho final é do Qt."""
    img = Image.open(assets / "sddm/themes/delonix/background.png").resize((larg, alt)).convert("RGB")
    base = img.convert("RGBA")
    d = ImageDraw.Draw(base, "RGBA")

    # cartão: 420 de largura, cantos 14, fundo 92% opaco
    cw, ch = 420, 470
    cx, cy = (larg - cw) // 2, (alt - ch) // 2
    d.rounded_rectangle([cx, cy, cx + cw, cy + ch], radius=14,
                        fill=(22, 25, 30, 235), outline=BORDER, width=1)

    # marca com anéis (o QML anima-os; aqui um instante)
    logo = Image.open(assets / "sddm/themes/delonix/logo.png").resize((88, 88))
    mx, my = larg // 2, cy + 42 + 44
    for raio, alpha in ((58, 70), (48, 110)):
        d.ellipse([mx - raio, my - raio, mx + raio, my + raio], outline=RED + (alpha,), width=1)
    base.alpha_composite(logo, (mx - 44, my - 44))

    y = cy + 132
    y += centrado(d, y, "DelonixOS", fonte("bold", 30), FG, larg) + 14
    y += centrado(d, y, "DEVOPS · SRE · PLATFORM ENGINEERING", fonte("bold", 12), RED, larg) + 18
    d.rounded_rectangle([mx - 32, y, mx + 32, y + 2], radius=1, fill=RED)
    y += 26

    # campos: 44 de altura, cantos 8
    for texto, foco, cor_texto in (("delonix", False, FG), ("••••••••", True, FG)):
        d.rounded_rectangle([cx + 32, y, cx + cw - 32, y + 44], radius=8,
                            fill=SURFACE, outline=RED if foco else BORDER, width=2 if foco else 1)
        d.text((cx + 44, y + 13), texto, font=fonte("regular", 14), fill=cor_texto)
        y += 58

    # botão Entrar: 46 de altura
    d.rounded_rectangle([cx + 32, y, cx + cw - 32, y + 46], radius=8, fill=RED)
    caixa = d.textbbox((0, 0), "Entrar", font=fonte("bold", 14))
    d.text((mx - caixa[2] / 2, y + 14), "Entrar", font=fonte("bold", 14), fill=(255, 255, 255))
    y += 62

    d.text((cx + 32, y + 2), "Sessão", font=fonte("regular", 12), fill=MUTED)
    d.rounded_rectangle([cx + 96, y - 4, cx + cw - 32, y + 26], radius=8,
                        fill=SURFACE, outline=BORDER, width=1)
    d.text((cx + 108, y + 2), "Plasma (Wayland)", font=fonte("regular", 12), fill=FG)

    # canto superior esquerdo: nome da máquina; inferiores: relógio e energia
    d.text((24, 24), "delonix", font=fonte("regular", 13), fill=MUTED)
    d.text((24, alt - 40), "sexta-feira, 15 agosto 2026 — 09:12",
           font=fonte("regular", 13), fill=MUTED)
    x = larg - 24
    for rotulo in ("Desligar", "Reiniciar", "Suspender"):
        caixa = d.textbbox((0, 0), rotulo, font=fonte("regular", 12))
        x -= caixa[2]
        d.text((x, alt - 39), rotulo, font=fonte("regular", 12), fill=MUTED)
        x -= 18
    return rodape(base.convert("RGB"),
                  "montagem com os valores do Main.qml — o desenho final é do Qt, não é uma captura")


# ------------------------------------------------------------------- Desktop
def desktop(assets: Path, larg=1280, alt=720) -> Image.Image:
    """Aproximado: wallpaper real + painel com o layout que o look-and-feel define."""
    wall = sorted((assets / "wallpapers/Delonix/contents/images").glob("*.png"))[0]
    img = Image.open(wall).resize((larg, alt)).convert("RGB")
    d = ImageDraw.Draw(img, "RGBA")

    # painel: 44 px em baixo (org.kde.plasma.desktop-layout.js)
    ph = 44
    d.rectangle([0, alt - ph, larg, alt], fill=(18, 21, 26, 245))
    d.rectangle([0, alt - ph, larg, alt - ph + 1], fill=(38, 42, 49, 255))

    # kickoff com a marca
    logo = Image.open(assets / "plymouth/themes/delonix/logo.png").resize((26, 26))
    img.paste(logo, (10, alt - ph + 9), logo)

    # pager + lançadores (icontasks): dolphin, kitty, firefox, kate
    x = 50
    for i in range(4):
        cor = (255, 255, 255, 26) if i else (224, 32, 47, 60)
        d.rounded_rectangle([x, alt - ph + 7, x + 30, alt - 7], radius=6, fill=cor)
        x += 36

    # systemmonitor + bandeja + relógio com data ISO
    d.text((larg - 250, alt - ph + 14), "CPU ▁▃▅▂▁", font=fonte("mono", 12), fill=MUTED)
    d.text((larg - 150, alt - ph + 8), "2026-08-15", font=fonte("regular", 12), fill=FG)
    d.text((larg - 150, alt - ph + 24), "09:12", font=fonte("bold", 12), fill=FG)

    # uma janela de terminal, que é onde esta distro vive
    tw, th = 720, 380
    tx, ty = 90, 130
    d.rounded_rectangle([tx, ty, tx + tw, ty + th], radius=8, fill=(13, 15, 18, 246),
                        outline=(38, 42, 49, 255), width=1)
    d.rectangle([tx, ty, tx + tw, ty + 28], fill=(22, 25, 30, 255))
    d.rounded_rectangle([tx, ty, tx + 150, ty + 28], radius=6, fill=RED)
    d.text((tx + 14, ty + 7), "delonix: zsh", font=fonte("bold", 12), fill=(255, 255, 255))
    d.text((tx + 175, ty + 7), "2: k9s", font=fonte("regular", 12), fill=MUTED)

    fm = fonte("mono", 13)
    linhas = [
        (" ~/projectos/delonix-net", MUTED),
        (" main ✔  ☸ prod (delonix-system)", RED),
        ("❯ delonix-doctor", FG),
        ("  ✓ cgroup v2 unificado", (46, 178, 120)),
        ("  ✓ controlador delegado: cpu memory pids io", (46, 178, 120)),
        ("  ✓ subuid/subgid: delonix:100000:65536", (46, 178, 120)),
        ("  ✓ virtualização aninhada activa", (46, 178, 120)),
        ("  ✓ NPU visível", (46, 178, 120)),
        ("  ✓ rede: bbr + fq", (46, 178, 120)),
        ("  ✓ nvme0n1 usa none", (46, 178, 120)),
        ("  ! observability a correr (delonix-toolbox lab down)", (224, 164, 60)),
        ("", FG),
        ("❯ cargo build --release", FG),
        ("   Compiling delonix-net v0.48.0", MUTED),
        ("    Finished `release` profile [optimized] in 18.4s", (46, 178, 120)),
        ("❯ ", FG),
    ]
    y = ty + 44
    for texto, cor in linhas:
        d.text((tx + 16, y), texto, font=fm, fill=cor)
        y += 19

    return rodape(img, "montagem: wallpaper e marca reais, painel conforme o layout — não é uma captura")


def main() -> None:
    ap = argparse.ArgumentParser()
    raiz = Path(__file__).resolve().parent.parent
    ap.add_argument("--assets", default=str(raiz / "build/branding/usr/share"))
    ap.add_argument("--out", default=str(raiz / "build/preview"))
    args = ap.parse_args()

    assets, out = Path(args.assets), Path(args.out)
    if not (assets / "plymouth").is_dir():
        raise SystemExit("assets não encontrados — corre `make branding` primeiro")
    out.mkdir(parents=True, exist_ok=True)

    for nome, fn in (("1-grub", grub), ("2-plymouth", plymouth),
                     ("3-sddm", sddm), ("4-desktop", desktop)):
        img = fn(assets)
        destino = out / f"delonixos-{nome}.png"
        img.save(destino)
        print(f"  {destino.relative_to(raiz)}  ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
