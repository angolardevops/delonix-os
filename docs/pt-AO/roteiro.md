# DelonixOS — roteiro


> 🇬🇧 [This page in English](../en/roadmap.md)

Estado a 2026-08-14. Ordem pensada como fundação: cada ponto desbloqueia o
seguinte. Não saltar.

## Feito

- [x] Perfil `manjaro-tools` completo (`delonix/devops`) com Plasma mínimo
- [x] Curadoria de pacotes: −3,5 GB de bloat, +kit de plataforma, com blocklist
      aplicada automaticamente no build
- [x] Branding gerado por código a partir da marca oficial (globo + anéis de
      sinal + antenas): GRUB, Plymouth **animado** (24 frames, com diálogo LUKS),
      SDDM, KSplash em QML, tema global, esquema de cores, wallpapers até 4K
- [x] Virtualização pronta a usar: KVM com *nested*, libvirt + rede default,
      virt-manager, qemu-full, cloud-hypervisor, perfil `tuned` delonix-lab
- [x] CLI do docker sem daemon (aponta ao podman rootless), tmux como consola
      por omissão, AWS + GCP, Claude Code e Antigravity
- [x] Repositório local `[delonix-aur]` compilado no build, com degradação
      controlada quando um pacote do AUR não compila
- [x] Branding, afinação e ferramentas empacotados (`delonix-os-*`) em vez de
      copiados para a imagem — é o que permite actualizá-los depois de instalada
- [x] Ganchos do pacman que reaplicam o splash e o tema do GRUB quando o
      `plymouth` ou o `grub` são actualizados
- [x] Afinação de host para trabalho de plataforma (cgroup delegation, subuid,
      inotify, zram, BBR, limites)
- [x] `delonix-doctor` (diagnóstico) e `delonix-toolbox` (perfis a pedido)
- [x] Pipeline de build em contentor + validação pré-build (`make verify/check`)

## A seguir — por ordem

### 1. Primeira ISO real
Correr `make iso` numa máquina com `sudo`, arrancar em QEMU (`make test`) e
percorrer a lista de [`docs/VALIDACAO.md`](validacao.md). Até isto estar feito,
tudo o resto é teoria.

### 2. Branding do Calamares
O instalador ainda é o da Manjaro. Falta o *slideshow* (QML), o logótipo, os
textos em português e o esquema de particionamento sugerido (Btrfs com
subvolumes + snapshots, que é o que faz sentido para quem experimenta muito).

### 3. Publicar o repositório `[delonix]`
Os pacotes **já existem** (`packaging/`): `delonix-os-branding`,
`delonix-os-settings`, `delonix-os-tools` e o meta `delonix-os`, construídos no
build para um repositório local que a ISO consome. Falta a parte de
infraestrutura: publicar (`rsync` para um servidor), assinar com a chave
`delonix.key`, e mudar o `Server =` de `file://` para o URL público. Só a partir
daí é que um `pacman -Syu` traz branding e afinação novos a quem já instalou.

Ainda por empacotar: `delonix-runtime` e `delonixctl` (hoje entram como binários
descarregados pelo `fetch-delonix-bins.sh`).

### 4. Assinatura e reprodutibilidade
Assinar a ISO (a chave `delonix.key` já existe no workspace), publicar
`SHA256SUMS` + assinatura, e fixar um snapshot de repositório por release para
que o mesmo commit gere a mesma imagem.

### 5. Actualizações do sistema instalado
Decidir o modelo: seguir a Manjaro stable (simples) ou congelar snapshots
próprios (previsível, mas exige infra). Recomendação: seguir a stable e publicar
só `delonix-os-*` no nosso repo.

### 6. Edições
- `delonix-os-server` — sem Plasma, para bastions e runners de CI
- `delonix-os-workstation` — esta, a de referência

### 7. Integração com a N'GolaCloud
`delonixctl` pré-configurado, perfis de acesso ao PaaS, e um atalho de primeira
utilização que liga o posto a um tenant.

## Deliberadamente fora

- **Docker/dockerd** — daemon com root; contraria a regra de casa (rootless e
  sem daemon). Quem precisar, instala à mão e assume.
- **Instalador gráfico próprio** — o Calamares chega e é mantido por outros.
- **Ambiente de desktop próprio** — o Plasma faz o trabalho; nós só o vestimos.
