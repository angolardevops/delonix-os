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
# Quatro composições do mesmo desktop, porque "como fica" depende do que estás
# a fazer: o terminal (onde esta distro vive), um cluster, uma VM, e o
# laboratório de observabilidade.

def _fundo(assets: Path, larg: int, alt: int) -> Image.Image:
    wall = sorted((assets / "wallpapers/Delonix/contents/images").glob("*.png"))[0]
    return Image.open(wall).resize((larg, alt)).convert("RGB")


def _painel(img: Image.Image, assets: Path, activo: int = 0) -> None:
    """Painel de 44 px em baixo, como o org.kde.plasma.desktop-layout.js define."""
    larg, alt = img.size
    d = ImageDraw.Draw(img, "RGBA")
    ph = 44
    d.rectangle([0, alt - ph, larg, alt], fill=(18, 21, 26, 245))
    d.rectangle([0, alt - ph, larg, alt - ph + 1], fill=(38, 42, 49, 255))

    logo = Image.open(assets / "plymouth/themes/delonix/logo.png").resize((26, 26))
    img.paste(logo, (10, alt - ph + 9), logo)

    x = 50
    for i in range(4):
        cor = (224, 32, 47, 70) if i == activo else (255, 255, 255, 26)
        d.rounded_rectangle([x, alt - ph + 7, x + 30, alt - 7], radius=6, fill=cor)
        x += 36

    d.text((larg - 250, alt - ph + 14), "CPU ▁▃▅▂▁", font=fonte("mono", 12), fill=MUTED)
    d.text((larg - 150, alt - ph + 8), "2026-08-15", font=fonte("regular", 12), fill=FG)
    d.text((larg - 150, alt - ph + 24), "09:12", font=fonte("bold", 12), fill=FG)


def _janela(img: Image.Image, caixa: tuple, titulo: str, abas: list[str] | None = None,
            fundo=(13, 15, 18, 246)) -> ImageDraw.ImageDraw:
    """Moldura de janela com a barra de título do Breeze e o acento Delonix."""
    x, y, w, h = caixa
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle([x, y, x + w, y + h], radius=8, fill=fundo,
                        outline=(38, 42, 49, 255), width=1)
    d.rectangle([x, y, x + w, y + 30], fill=(22, 25, 30, 255))
    d.rounded_rectangle([x, y, x + 160, y + 30], radius=6, fill=RED)
    d.text((x + 14, y + 8), titulo, font=fonte("bold", 12), fill=(255, 255, 255))
    if abas:
        tx = x + 176
        for aba in abas:
            d.text((tx, y + 8), aba, font=fonte("regular", 12), fill=MUTED)
            tx += len(aba) * 8 + 30
    # botões da direita (ButtonsOnRight=IAX no kwinrc)
    for i, cor in enumerate(((139, 144, 153), (139, 144, 153), (224, 32, 47))):
        d.ellipse([x + w - 26 - i * 22, y + 11, x + w - 18 - i * 22, y + 19], fill=cor)
    return d


def _linhas(d: ImageDraw.ImageDraw, x: int, y: int, linhas: list, f=None, passo: int = 19) -> int:
    f = f or fonte("mono", 13)
    for texto, cor in linhas:
        d.text((x, y), texto, font=f, fill=cor)
        y += passo
    return y


VERDE = (46, 178, 120)
AMBAR = (224, 164, 60)


def desktop(assets: Path, larg=1280, alt=720) -> Image.Image:
    """O terminal — é onde esta distro vive."""
    img = _fundo(assets, larg, alt)
    d = _janela(img, (90, 130, 720, 380), "delonix: zsh", ["2: k9s", "3: labs"])
    _linhas(d, 106, 174, [
        (" ~/projectos/delonix-net", MUTED),
        (" main ✔  ☸ prod (delonix-system)", RED),
        ("❯ delonix-doctor", FG),
        ("  ✓ cgroup v2 unificado", VERDE),
        ("  ✓ controlador delegado: cpu memory pids io", VERDE),
        ("  ✓ subuid/subgid: delonix:100000:65536", VERDE),
        ("  ✓ virtualização aninhada activa", VERDE),
        ("  ✓ NPU visível", VERDE),
        ("  ✓ rede: bbr + fq", VERDE),
        ("  ✓ nvme0n1 usa none", VERDE),
        ("  ! observability a correr (delonix-toolbox lab down)", AMBAR),
        ("", FG),
        ("❯ cargo build --release", FG),
        ("   Compiling delonix-net v0.48.0", MUTED),
        ("    Finished `release` profile [optimized] in 18.4s", VERDE),
        ("❯ ", FG),
    ])
    _painel(img, assets, activo=1)
    return rodape(img, "montagem: wallpaper e marca reais, painel conforme o layout — não é uma captura")


def desktop_k9s(assets: Path, larg=1280, alt=720) -> Image.Image:
    """Um cluster ao vivo — o ecrã de quem opera Kubernetes."""
    img = _fundo(assets, larg, alt)
    x, y, w, h = 70, 110, 900, 440
    d = _janela(img, (x, y, w, h), "delonix: k9s", ["1: zsh"])

    fm = fonte("mono", 12)
    # cabeçalho do k9s
    d.text((x + 16, y + 44), "Context: prod        Cluster: delonix-prod", font=fm, fill=RED)
    d.text((x + 16, y + 62), "User:    delonix     K9s Rev: v0.50.x", font=fm, fill=MUTED)
    d.text((x + 16, y + 80), "CPU:     34%         MEM: 61%", font=fm, fill=MUTED)
    d.text((x + 470, y + 44), "<0> all      <1> default", font=fm, fill=MUTED)
    d.text((x + 470, y + 62), "<d> describe <l> logs", font=fm, fill=MUTED)
    d.text((x + 470, y + 80), "<s> shell    <y> yaml", font=fm, fill=MUTED)

    d.rectangle([x + 12, y + 104, x + w - 12, y + 106], fill=(38, 42, 49, 255))
    d.text((x + 16, y + 114), " Pods(delonix-system)[7]", font=fonte("bold", 12), fill=FG)

    cab = "  NAME                              READY  STATUS     RESTARTS  CPU  MEM   AGE"
    d.text((x + 16, y + 138), cab, font=fm, fill=(120, 130, 145))
    pods = [
        ("  delonix-controller-7c9f4b8d5-2xk4p   1/1   Running          0   12   184   6d", VERDE),
        ("  delonix-net-agent-h9wqz              1/1   Running          0    8    96   6d", VERDE),
        ("  delonix-net-agent-p4tvm              1/1   Running          0    9   102   6d", VERDE),
        ("  ingress-nginx-controller-6b8f9-qq2   1/1   Running          2  145   312  21d", VERDE),
        ("  postgres-primary-0                   1/1   Running          0   88   974  14d", VERDE),
        ("  observability-grafana-5d7c8f-x8k2    1/1   Running          0   21   256   3h", VERDE),
        ("  backup-cron-29154720-mv7bd           0/1   Completed        0    0     0  47m", MUTED),
    ]
    yy = y + 158
    for i, (linha, cor) in enumerate(pods):
        if i == 0:
            d.rectangle([x + 12, yy - 3, x + w - 12, yy + 16], fill=(30, 34, 41, 255))
            d.rectangle([x + 12, yy - 3, x + 15, yy + 16], fill=RED)
        d.text((x + 16, yy), linha, font=fm, fill=FG if i == 0 else cor)
        yy += 19

    # rodapé de teclas do k9s
    d.rectangle([x + 12, y + h - 34, x + w - 12, y + h - 32], fill=(38, 42, 49, 255))
    d.text((x + 16, y + h - 26), "<ctrl-d> delete  <e> edit  <?> help  <:q> quit",
           font=fm, fill=MUTED)

    _painel(img, assets, activo=1)
    return rodape(img, "montagem (k9s ilustrativo) — o desenho final é do terminal, não é uma captura")


def desktop_virt(assets: Path, larg=1280, alt=720) -> Image.Image:
    """Uma VM a correr — KVM/libvirt com nested activo."""
    img = _fundo(assets, larg, alt)

    # virt-manager: lista de VMs
    x, y, w, h = 60, 120, 470, 330
    d = _janela(img, (x, y, w, h), "Gestor de VMs", None, fundo=(22, 25, 30, 250))
    d.text((x + 16, y + 44), "QEMU/KVM — qemu:///system", font=fonte("bold", 12), fill=FG)
    d.text((x + 16, y + 64), "NOME                 ESTADO      CPU     MEMÓRIA",
           font=fonte("mono", 11), fill=(120, 130, 145))
    vms = [
        ("dks-control-plane    A correr    18%     4,0 GiB", VERDE, True),
        ("dks-worker-1         A correr     7%     2,0 GiB", VERDE, False),
        ("dks-worker-2         A correr     9%     2,0 GiB", VERDE, False),
        ("win11-atestacao      Suspensa     0%     8,0 GiB", AMBAR, False),
        ("ubuntu-24.04-base    Desligada    —      2,0 GiB", MUTED, False),
    ]
    yy = y + 88
    for texto, cor, sel in vms:
        if sel:
            d.rectangle([x + 12, yy - 4, x + w - 12, yy + 16], fill=(30, 34, 41, 255))
            d.rectangle([x + 12, yy - 4, x + 15, yy + 16], fill=RED)
        d.ellipse([x + 22, yy + 4, x + 30, yy + 12], fill=cor)
        d.text((x + 38, yy), texto, font=fonte("mono", 11), fill=FG if sel else MUTED)
        yy += 26
    d.text((x + 16, y + h - 40), "nested: Y   ·   /dev/kvm: ok   ·   rede default: activa",
           font=fonte("mono", 11), fill=VERDE)

    # consola da VM seleccionada
    cx, cy, cw, ch = 560, 150, 640, 380
    d2 = _janela(img, (cx, cy, cw, ch), "dks-control-plane", ["consola"])
    _linhas(d2, cx + 16, cy + 48, [
        ("Ubuntu 24.04.3 LTS dks-control-plane tty1", MUTED),
        ("", FG),
        ("delonix@dks-control-plane:~$ kubectl get nodes", FG),
        ("NAME                STATUS   ROLES           AGE   VERSION", (120, 130, 145)),
        ("dks-control-plane   Ready    control-plane   9m    v1.34.1", VERDE),
        ("dks-worker-1        Ready    <none>          7m    v1.34.1", VERDE),
        ("dks-worker-2        Ready    <none>          7m    v1.34.1", VERDE),
        ("", FG),
        ("delonix@dks-control-plane:~$ lscpu | grep -i hypervisor", FG),
        ("Hypervisor vendor:      KVM", VERDE),
        ("", FG),
        ("delonix@dks-control-plane:~$ ls /dev/kvm", FG),
        ("/dev/kvm", VERDE),
        ("", FG),
        ("delonix@dks-control-plane:~$ ", FG),
    ], f=fonte("mono", 12), passo=20)

    _painel(img, assets, activo=3)
    return rodape(img, "montagem (virt-manager ilustrativo) — não é uma captura de ecrã")


def desktop_grafana(assets: Path, larg=1280, alt=720) -> Image.Image:
    """O laboratório de observabilidade, no browser."""
    img = _fundo(assets, larg, alt)
    x, y, w, h = 70, 100, 1000, 470
    d = _janela(img, (x, y, w, h), "Firefox", ["Grafana — DelonixOS"], fundo=(17, 18, 23, 250))

    # barra de endereço
    d.rounded_rectangle([x + 16, y + 40, x + w - 16, y + 66], radius=6,
                        fill=(13, 15, 18, 255), outline=(38, 42, 49, 255))
    d.text((x + 30, y + 47), "localhost:3000/d/delonix/posto-de-trabalho",
           font=fonte("mono", 12), fill=MUTED)

    d.text((x + 20, y + 82), "DelonixOS — posto de trabalho", font=fonte("bold", 14), fill=FG)
    d.text((x + w - 190, y + 84), "últimos 30 min  ·  ⟳ 10s", font=fonte("regular", 11), fill=MUTED)

    import math
    paineis = [
        ("CPU por núcleo", "34%", VERDE, 0.34),
        ("Memória", "61%  (19,4 / 31 GiB)", AMBAR, 0.61),
        ("Pressão de I/O (PSI)", "4,2%", VERDE, 0.12),
        ("Rede — eth0", "↓ 41 Mb/s  ↑ 6 Mb/s", VERDE, 0.42),
        ("Containers rootless", "11", VERDE, 0.3),
        ("Temperatura CPU", "58 °C", VERDE, 0.45),
    ]
    pw, ph = (w - 60) // 3, 150
    for i, (titulo, valor, cor, nivel) in enumerate(paineis):
        px = x + 20 + (i % 3) * (pw + 10)
        py = y + 108 + (i // 3) * (ph + 12)
        d.rounded_rectangle([px, py, px + pw, py + ph], radius=6,
                            fill=(24, 27, 31, 255), outline=(38, 42, 49, 255))
        d.text((px + 12, py + 10), titulo, font=fonte("regular", 11), fill=MUTED)
        d.text((px + 12, py + 30), valor, font=fonte("bold", 18), fill=FG)

        # sparkline: determinista, para a imagem ser reprodutível
        base_y = py + ph - 16
        altura = ph - 76
        pontos = []
        for k in range(0, pw - 24, 4):
            t = k / max(1, pw - 24)
            v = nivel + 0.16 * math.sin(t * 9 + i) + 0.06 * math.sin(t * 23 + i * 2)
            v = max(0.02, min(0.97, v))
            pontos.append((px + 12 + k, base_y - v * altura))
        d.line(pontos, fill=cor, width=2, joint="curve")
        d.line([(px + 12, base_y), (px + pw - 12, base_y)], fill=(38, 42, 49, 255))

    _painel(img, assets, activo=2)
    return rodape(img, "montagem (dashboard ilustrativa) — o Grafana real vem do `lab up observability`")


# ----------------------------------------------------------------- Instalador
def calamares(assets: Path, larg=1280, alt=720) -> Image.Image:
    """
    O primeiro ecrã que um utilizador novo vê — e o único que AINDA tem o
    branding da Manjaro. Esta montagem é o alvo, não o estado actual: serve
    para desenhar o branding do Calamares, que está no roteiro.
    """
    img = _fundo(assets, larg, alt)
    x, y, w, h = 190, 90, 900, 520
    d = _janela(img, (x, y, w, h), "Instalar o DelonixOS", None, fundo=(22, 25, 30, 252))

    # coluna de passos, à esquerda
    d.rectangle([x + 1, y + 31, x + 250, y + h - 1], fill=(18, 21, 26, 255))
    passos = [("Bem-vindo", "feito"), ("Localização", "feito"), ("Teclado", "feito"),
              ("Partições", "actual"), ("Utilizador", "por fazer"),
              ("Resumo", "por fazer"), ("Instalar", "por fazer")]
    yy = y + 60
    for nome, estado in passos:
        if estado == "actual":
            d.rectangle([x + 1, yy - 8, x + 250, yy + 22], fill=(30, 34, 41, 255))
            d.rectangle([x + 1, yy - 8, x + 4, yy + 22], fill=RED)
        cor_bola = VERDE if estado == "feito" else (RED if estado == "actual" else (70, 76, 84))
        d.ellipse([x + 22, yy + 2, x + 32, yy + 12], fill=cor_bola)
        d.text((x + 46, yy), nome, font=fonte("regular", 13),
               fill=FG if estado != "por fazer" else MUTED)
        yy += 34

    # painel principal
    logo = Image.open(assets / "plymouth/themes/delonix/logo.png").resize((56, 56))
    img.paste(logo, (x + 286, y + 56), logo)
    d.text((x + 356, y + 62), "DelonixOS 1.0", font=fonte("bold", 22), fill=FG)
    d.text((x + 356, y + 92), "DevOps · SRE · Platform Engineering",
           font=fonte("bold", 11), fill=RED)

    d.text((x + 286, y + 140), "Onde queres instalar?", font=fonte("bold", 15), fill=FG)
    opcoes = [
        ("Apagar o disco e instalar", "recomendado · Btrfs com instantâneos", True),
        ("Instalar ao lado do sistema actual", "mantém o que já está instalado", False),
        ("Particionamento manual", "para quem sabe o que quer", False),
    ]
    yy = y + 176
    for titulo, sub, sel in opcoes:
        d.rounded_rectangle([x + 286, yy, x + w - 40, yy + 62], radius=8,
                            fill=(30, 34, 41, 255) if sel else (24, 27, 31, 255),
                            outline=RED if sel else BORDER, width=2 if sel else 1)
        d.ellipse([x + 304, yy + 24, x + 318, yy + 38],
                  outline=RED if sel else (90, 96, 104), width=2,
                  fill=RED if sel else None)
        d.text((x + 334, yy + 14), titulo, font=fonte("bold", 13), fill=FG)
        d.text((x + 334, yy + 34), sub, font=fonte("regular", 11), fill=MUTED)
        yy += 74

    d.text((x + 286, yy + 8), "NVMe · Samsung SSD 990 PRO 2TB · 1,86 TiB livres",
           font=fonte("mono", 11), fill=MUTED)

    # botões
    d.rounded_rectangle([x + w - 300, y + h - 62, x + w - 190, y + h - 24],
                        radius=8, fill=(30, 34, 41, 255), outline=BORDER)
    d.text((x + w - 275, y + h - 51), "Anterior", font=fonte("regular", 13), fill=MUTED)
    d.rounded_rectangle([x + w - 170, y + h - 62, x + w - 40, y + h - 24], radius=8, fill=RED)
    d.text((x + w - 130, y + h - 51), "Seguinte", font=fonte("bold", 13), fill=(255, 255, 255))

    _painel(img, assets, activo=-1)
    return rodape(img, "montagem: é o ALVO do branding do Calamares, ainda por fazer — não é uma captura")


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
                     ("3-sddm", sddm), ("4-desktop", desktop),
                     ("5-k9s", desktop_k9s), ("6-vms", desktop_virt),
                     ("7-grafana", desktop_grafana), ("8-instalador", calamares)):
        img = fn(assets)
        destino = out / f"delonixos-{nome}.png"
        img.save(destino)
        print(f"  {destino.relative_to(raiz)}  ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
