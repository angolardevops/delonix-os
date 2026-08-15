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

.PHONY: all branding preview packages verify check preflight iso shell test qemu-cmd cli-test distro-test clean help

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
