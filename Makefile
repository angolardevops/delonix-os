# DelonixOS — atalhos de construção.
#
#   make branding   regenera os PNG da marca
#   make preview    monta as pré-visualizações dos ecrãs (docs/img)
#   make verify     valida o perfil (local)
#   make check      valida o perfil + confirma pacotes nos repos (rede)
#   make preflight  resolve a transação de pacotes com o pacman (~2 min)
#   make packages   compila os pacotes da casa (só em Arch/Manjaro)
#   make iso        constrói a ISO (contentor Manjaro privilegiado)
#   make shell      abre uma shell no contentor de build
#   make test       arranca a última ISO em QEMU (UEFI)
#   make qemu-cmd   imprime o comando QEMU da última ISO (para copiares)
#   make cli-test   testa o CLI delonixos (doctor, init, validate, render)
#   make distro-test  corre o CLI dentro de contentores de cada distro
#   make clean      apaga out/ e .cache/

SHELL      := /usr/bin/env bash
REPO_DIR   := $(shell pwd)
OUT_DIR    := $(REPO_DIR)/out
KERNEL     ?= linux612
# `find` em vez de glob: o buildiso aninha a ISO em out/<edição>/<perfil>/ e o
# `**` só funciona com globstar ligado.
ISO         = $(shell find $(OUT_DIR) -name '*.iso' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

.PHONY: all branding preview packages verify check preflight iso shell test qemu-cmd cli-test distro-test clean help clean-live lint clean-boot clean-desktop

all: verify

help:
	@sed -n '3,15p' $(MAKEFILE_LIST) | sed 's/^# \?//'

branding:
	@./scripts/stage-branding.sh

preview: branding
	@python3 branding/preview.py
	@cp build/preview/*.png docs/img/ 2>/dev/null || true

packages: branding
	@./scripts/build-os-packages.sh $(REPO_DIR)/build/repo

verify:
	@./scripts/verify-profile.sh

# O shellcheck apanha o que o `bash -n` não apanha (crases em texto, arrays,
# variáveis por definir). Corre num contentor para não obrigar ninguém a
# instalá-lo só para construir a ISO.
# A fase `live` do buildiso guarda um marcador; se ela falhou a meio, o chroot
# fica num estado que o build seguinte reaproveita — incluindo o que estava mal.
# Isto apaga SÓ essa fase (a `root` e a `desktop`, que demoram horas, ficam).
# QUE FASE É QUE A MINHA ALTERAÇÃO TOCA
#
# O buildiso guarda um marcador por fase e salta as que já estão feitas — é isso
# que torna as tentativas rápidas. O preço: uma alteração só chega à ISO se a
# fase respectiva voltar a correr. Isto custou-nos vários testes a imagens que
# não continham as correcções.
#
# O `make iso` já detecta isto sozinho (invalidar_fases no in-container-build.sh
# compara datas). Estes alvos ficam para forçar à mão:
#
#   Packages-Root, root-overlay/        → clean-root      (horas)
#   Packages-Desktop, desktop-overlay/  → clean-desktop   (a mais demorada)
#   packaging/*/payload                 → clean-desktop
#   Packages-Live, live-overlay/        → clean-live      (rápida)
#   profile.conf (custom_boot_args)     → clean-boot
#   tema do GRUB                        → clean-boot
CHROOTS = $(REPO_DIR)/.cache/chroots/buildiso/devops/x86_64

clean-boot:
	@echo "→ a apagar as fases de arranque (entradas do GRUB e initramfs)"
	@sudo rm -rf $(CHROOTS)/build.make_grub $(CHROOTS)/build.make_image_boot \
	             $(CHROOTS)/bootfs $(CHROOTS)/efiboot $(CHROOTS)/iso
	@echo "→ feito; o cmdline e o tema do GRUB voltam a ser gerados"

clean-desktop:
	@echo "→ a apagar a fase desktop (a mais demorada depois da root)"
	@sudo rm -rf $(CHROOTS)/desktopfs $(CHROOTS)/desktopfs.lock \
	             $(CHROOTS)/build.make_image_desktop
	@$(MAKE) --no-print-directory clean-live clean-boot

clean-live:
	@echo "→ a apagar a fase live do chroot (root e desktop mantêm-se)"
	@sudo rm -rf $(REPO_DIR)/.cache/chroots/buildiso/devops/x86_64/livefs \
	             $(REPO_DIR)/.cache/chroots/buildiso/devops/x86_64/livefs.lock \
	             $(REPO_DIR)/.cache/chroots/buildiso/devops/x86_64/build.make_image_live
	@echo "→ feito; 'make iso' reconstrói só a fase live"

lint:
	@podman run --rm -v "$(REPO_DIR):/w:ro" -w /w \
		docker.io/koalaman/shellcheck-alpine:stable sh -c \
		'for f in packaging/*/payload/usr/bin/delonix-* packaging/*/payload/usr/lib/delonix/* scripts/*.sh; do \
			[ -f "$$f" ] && shellcheck -S warning -f gcc "$$f"; done' || true

check:
	@./scripts/verify-profile.sh --online

preflight:
	@./scripts/preflight.sh

# O preflight corre ANTES: dois minutos a resolver a transação poupam quarenta
# a descobrir que um pacote não existe.
iso: branding verify preflight
	@./scripts/build.sh --kernel $(KERNEL)

shell:
	@./scripts/build.sh --shell

test:
	@test -n "$(ISO)" || { echo "sem ISO em $(OUT_DIR) — corre 'make iso'"; exit 1; }
	@./scripts/test-vm.sh "$(ISO)"

qemu-cmd:
	@./scripts/qemu-cmd.sh

cli-test:
	@./scripts/test-cli.sh

distro-test:
	@./scripts/test-distros.sh

clean:
	@rm -rf $(OUT_DIR) .cache build
	@echo "limpo."
