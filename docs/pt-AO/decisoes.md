# DelonixOS — decisões e porquês


> 🇬🇧 [This page in English](../en/decisions.md)

As decisões que custam a reverter, com o raciocínio. Quem discordar daqui a seis
meses deve poder ver o que se sabia hoje.

## 1. Base: Manjaro, não Arch puro nem Debian

Manjaro dá três coisas de graça que valem meses de trabalho: `mhwd` (detecção e
instalação de drivers, incluindo NVIDIA), gestão de kernels múltiplos lado a
lado, e um atraso de ~2 semanas sobre o Arch que apanha as regressões piores.
Perde-se pureza; ganha-se uma distro que arranca em hardware real.

Arch puro exigiria manter nós próprios essa camada. Debian/Ubuntu davam
estabilidade mas pacotes velhos — inaceitável para ferramentas que se movem à
velocidade do `kubectl` e do `opentofu`.

## 2. Plasma mínimo, não o grupo `plasma`

Instalamos `plasma-desktop` + peças escolhidas, nunca os meta-pacotes. O grupo
`plasma` arrasta PIM, Discover, Bigscreen e o `baloo`. A regra é: cada pacote de
desktop na lista tem de ter um utilizador com nome — se ninguém o usa numa
semana normal de trabalho, sai.

## 3. Containers: rootless e sem daemon; Docker fica de fora

Coerente com a regra do workspace (`AGENTS.md`): o runtime da casa não depende de
sockets globais nem de root. Isto não é só ideologia — é o que permite delegar
cgroups à sessão do utilizador e conter o raio de dano de um container
comprometido. `podman/buildah/skopeo` entram como rede de segurança para imagens
OCI de terceiros; `docker` fica disponível mas fora da imagem.

Consequência assumida: quem chega do Docker vai estranhar. O alias `d=delonix` e
o `DOCKER_HOST` a apontar para o socket do podman rootless reduzem o atrito.

## 4. Runtimes e CLIs de cloud fora da ISO

Go + Rust + Node + Java + AWS + GCP + Azure são ~3,5 GB. Numa ISO, isso é o
dobro do tamanho para servir metade das pessoas. O `delonix-toolbox` instala por
perfis em segundos, com rede — e um posto de engenharia tem rede.

Contra-argumento legítimo: ambientes air-gapped. Se isso passar a ser requisito,
faz-se uma edição `-offline` com tudo dentro, em vez de engordar a principal.

## 5. Branding gerado por código, não binários no repositório

`branding/gen-assets.py` desenha tudo com Pillow. Mudar a paleta é mudar três
constantes; um PR de branding é legível em diff. Também evita ter PNG de 4K a
inchar o histórico do git. Custo: não há liberdade de designer sem tocar em
código — aceitável enquanto a marca for geométrica.

## 6. Afinação de kernel com sintoma associado

Cada linha de `99-delonix.conf` tem, em comentário, o sintoma que resolve.
"Tuning" sem sintoma é superstição e não entra. É também o que permite reverter
com confiança quando um valor deixar de fazer sentido.

## 7. Portas privilegiadas continuam fechadas

Baixar `ip_unprivileged_port_start` para 80 é conveniente e é o que muitos guias
de rootless mandam fazer. Também permite que qualquer processo do utilizador se
faça passar por um serviço de sistema. Fica em opt-in explícito
(`delonix-toolbox unprivileged-ports on`), com o compromisso escrito no ficheiro.

## 8. Pacotes, não overlay — e a fronteira entre os dois

Um ficheiro copiado para dentro da imagem é escrito uma vez e nunca mais muda:
quem instalasse a v1.0 ficaria com esse tema e com essa afinação **para sempre**.
Por isso o que precisa de evoluir é distribuído como pacote pacman, no
repositório `[delonix]`:

| Pacote | O que leva | Porque tem de ser pacote |
|---|---|---|
| `delonix-os-branding` | temas (Plymouth, SDDM, GRUB, Plasma), wallpapers | um logótipo mal desenhado corrige-se para toda a gente |
| `delonix-os-settings` | sysctl, limites, cgroups, KVM, initramfs, tuned | um limite que hoje chega, amanhã não chega |
| `delonix-os-tools` | `delonix-doctor`, `delonix-toolbox` | é o que mais muda: cada ferramenta nova é uma linha |
| `delonix-os` | meta-pacote | dá um sítio único para acrescentar peças no futuro |

**O que fica no overlay, e porquê**: `/etc/skel` (só é lido ao criar um
utilizador — actualizá-lo depois não muda nada a quem já existe) e os dois
ficheiros que pertencem a outros pacotes, `/etc/default/grub` (do `grub`) e
`/etc/plymouth/plymouthd.conf` (do `plymouth`). Disputar a posse desses dois
faria o pacman recusar a instalação.

Para esses, a solução são **ganchos do pacman**: `95-delonix-plymouth.hook` e
`96-delonix-grub.hook` reaplicam a nossa escolha depois de qualquer
actualização do `plymouth` ou do `grub`. São idempotentes e respeitam quem
mudou o valor de propósito — só corrigem se estiver vazio ou a apontar para nós.
O `apply-plymouth` só reconstrói o initramfs quando o tema não está lá dentro,
para não pagar esse custo em cada actualização.

O que falta para fechar o ciclo é infraestrutura, não desenho: publicar o
repositório (`rsync` para um servidor) e assiná-lo. Até lá, o repositório é
construído localmente e consumido pela ISO — a imagem já sai coerente, e a
migração para actualizações a sério é só apontar o `Server =` para um URL.

## 9. Docker: o CLI entra, o daemon não

Pedido explícito para ter o CLI do docker. Instalá-lo não obriga a correr o
`dockerd` — o `DOCKER_HOST` aponta ao socket rootless do podman (pré-activado
no `/etc/skel`), por isso `docker ps`, `docker run` e `docker compose` funcionam
sem root e sem daemon. Mantém-se a regra da casa e ganha-se a compatibilidade de
comandos e de scripts que toda a gente já tem escritos.

Quem quiser mesmo o daemon: `sudo systemctl enable --now docker`. Fica registado
como decisão de quem administra, não como omissão da distro.

## 10. tmux como consola por omissão

Num posto que passa o dia com sessões remotas e processos longos, perder o
terminal é perder trabalho. O `.zshrc` faz `exec tmux new-session -A -s delonix`
em qualquer shell interactiva. `-A` significa "liga-te à que existe ou cria" —
nunca duplica sessões.

Custo: quem não conhece tmux estranha o prefixo e as divisões. Por isso há dois
escapes documentados (`DELONIX_NO_TMUX=1` e `~/.config/delonix/no-tmux`) e o
`.tmux.conf` usa `C-a`, que é o que a maioria já tem nos dedos.

## 11. Splash animado com frames, não desenhado em run-time

O Plymouth corre antes de haver GPU acelerada e com um interpretador muito
limitado. Desenhar os anéis em cada frame seria lento e frágil; 24 PNG
pré-renderizados trocados a ~25 fps custam praticamente nada. O número de frames
é **fixo no script** — descobri-lo em run-time obrigaria a chamar `Image()` sobre
ficheiros que podem não existir, e isso aborta o splash inteiro. O
`verify-profile.sh` garante que o número de ficheiros e o número no script não
divergem.

No KSplash (já com Plasma e GPU) o mesmo movimento é feito em QML, que fica
nítido em qualquer DPI.

## 12. AUR compilado no build, não instalado depois

`claude-code`, `antigravity`, `cloud-hypervisor` e o `gcloud` só existem no AUR,
e o `pacman` do `buildiso` não sabe o que é o AUR. Em vez de deixar a instalação
para depois do primeiro arranque (o pedido era "pronto a usar"), o build compila
estes pacotes num repositório local `[delonix-aur]`.

O `user-repos.conf` do manjaro-tools recusa repositórios `file://` de propósito,
por isso a secção é acrescentada directamente à configuração de `pacman` que o
`buildiso` usa. Se um pacote não compilar, a ISO sai na mesma sem ele — nunca um
build de uma hora a morrer por causa de um `PKGBUILD` partido a montante.

## 13. Um gestor de energia, não três

A primeira tentativa de build morreu com `tuned-2.27.0 and tlp-1.10.1 are in
conflict`. A causa não foi o conflito em si — foi a lista ter **três** gestores
de energia ao mesmo tempo: `tlp`, `power-profiles-daemon` e `tuned`. Mesmo que
o pacman os aceitasse, ficariam a disputar o mesmo governador de CPU, e o
resultado seria pior do que não ter nenhum.

Ficou o `tuned`, por cobrir os dois casos deste posto: perfis de bateria para
quem trabalha num portátil, e o `delonix-lab` (throughput, latência baixa,
THP em `madvise`) para quem está a correr VMs. O `tuned-ppd` completa a escolha
— fala a API D-Bus do `power-profiles-daemon`, por isso o seletor de energia do
Plasma continua a funcionar, servido pelo tuned por baixo.

Os dois removidos estão na `blocklist.txt`, com o motivo escrito: o build volta
a falhar se alguém os reintroduzir por distracção.

## 14. De "magra" para "completa" — e o que isso custou

A primeira versão desta distro deixava de fora runtimes de linguagem e CLIs de
cloud, com um argumento defensável: +3,5 GB para ferramentas que metade das
pessoas não usa. O pedido mudou o critério — o alvo passou a ser **abrir o
portátil e construir um projecto real sem voltas**.

O que mudou com isso:

- **Linguagens instaladas E configuradas.** Instalar o `rust` é metade do
  trabalho; a outra metade é o `~/.cargo/config.toml` com `mold` e `sccache`,
  o `GOTOOLCHAIN=auto`, o `uv` a gerir Pythons. Sem isso, cada pessoa
  redescobre a mesma configuração — e a maioria não a descobre de todo.
- **`rust` dos repositórios, não `rustup`.** O rustup precisa de rede para ter
  um compilador; o pacote funciona no primeiro arranque, offline. Quem precisa
  de várias toolchains instala o rustup a pedido. É a escolha que serve os 90%.
- **Bases de dados instaladas, mas paradas.** "Vem instalado" não pode
  significar "consome RAM desde o arranque": PostgreSQL + Redis + MongoDB a
  dormir são ~600 MB. Ficam desactivadas, e o `delonix-toolbox db start` trata
  do arranque — incluindo o `initdb` do Postgres, que de outra forma dá um erro
  que ninguém percebe à primeira.
- **Custo assumido**: a ISO passa de ~2,5 GB para ~5 GB e a instalação de ~9
  para ~18 GB. É o preço de não ter de instalar nada no primeiro dia, e está
  escrito nos alvos de `docs/VALIDACAO.md` para que ninguém o descubra por
  acidente.

O que **não** mudou foi o critério de fundo: nada entra sem função. Continuam
fora o office, o PIM, os jogos, a indexação — e agora também as animações do
desktop, que são GPU e memória a troco de decoração.

## 15. Validar contra a Manjaro, não contra o Arch

Durante semanas o `make check` confirmou os pacotes no **archlinux.org**. Parecia
razoável — a Manjaro é derivada do Arch. Custou um build de 40 minutos a provar
que não é a mesma coisa: o `kind` e o `intel-npu-driver` existem no Arch e ainda
não chegaram à Manjaro **stable**, que é o ramo onde construímos. O `buildiso`
só o disse no fim, com um `target not found`.

O verificador passou a ir buscar a verdade à fonte certa: as bases de dados da
própria Manjaro (`core.db`, `extra.db`, `multilib.db`) do ramo configurado,
com o AUR como segunda hipótese e cache local de 12 horas.

Dois efeitos:

- **Correcção**: valida contra o que o `pacman` vai mesmo encontrar. Também lê o
  campo `%PROVIDES%`, porque é assim que um pedido por `redis` é satisfeito pelo
  `valkey` — sem isso, o verificador reprovava nomes perfeitamente instaláveis.
- **Velocidade**: de ~12 minutos (uma chamada HTTP por pacote) para **10
  segundos** (três ficheiros, uma vez por dia). Uma verificação que demora doze
  minutos não é corrida antes de cada mudança; uma que demora dez segundos é.

Os dois pacotes em falta passaram para as variantes `-bin` do AUR
(`kind-bin`, `intel-npu-driver-bin`), com um comentário a dizer que se troca
pelo pacote do repositório quando a Manjaro os sincronizar.

## 16. Validação antes do build

`verify-profile.sh` corre em segundos e apanha o que de outra forma só rebentava
aos 20 minutos de `buildiso`: nome de pacote errado, tema referenciado que não
existe, script com erro de sintaxe, bloat que voltou pela porta das traseiras.
O `--online` confirma cada pacote contra os repositórios Arch/AUR.
