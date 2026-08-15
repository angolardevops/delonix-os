# Contribuir para o kernel Linux

O DelonixOS traz as ferramentas e um comando que elimina a parte cerimonial do
trabalho no kernel: descobrir que pacotes faltam (um erro obscuro de cada vez),
repetir à mão os mesmos passos de instalação, e reiniciar a máquina para testar
uma alteração.

> 🇬🇧 [This page in English](../en/kernel.md)

## A versão curta

```bash
delonix-kernel setup                  # clonar a mainline, verificar o fluxo de patches
delonix-kernel config                 # partir da configuração do kernel que estás a correr
delonix-kernel build --install        # compilar e acrescentar como entrada SEPARADA no arranque
```

Reinicia e escolhe-o no GRUB. Se não arrancar, escolhes o kernel da distro no
mesmo menu — **nada foi substituído**.

## Porquê uma entrada de arranque separada

Cada passo do `delonix-kernel install` é aditivo: um `vmlinuz-<versão>` novo, um
initramfs novo, uma entrada nova no GRUB. O teu kernel de trabalho fica intacto.

Isto não é prudência por prudência. Um kernel que compilaste está, por
definição, em teste — e um kernel em teste que substituiu o único que funcionava
é como se acaba com um portátil, uma pen USB e uma noite estragada. A versão
leva o sufixo `-delonix` para ser óbvia no menu e no `uname -r`.

## O ciclo que torna isto suportável

A forma lenta é: compilar, instalar, reiniciar, ver o *oops*, reiniciar de volta,
corrigir, repetir. Vinte minutos por iteração, e cada erro custa-te a sessão.

```bash
delonix-kernel build && delonix-kernel boot
```

O `boot` arranca o kernel que acabaste de compilar **numa VM**, com o
`virtme-ng`: sem instalar, sem initramfs, sem reiniciar. O teu `/home` é montado
lá dentro em modo de leitura, por isso os teus scripts de teste já lá estão.
Tens uma shell em segundos, vês o *oops* no mesmo terminal, sais com Ctrl-D e
voltas a compilar.

É a diferença entre iterar quatro vezes por hora e quarenta.

## Os comandos

| Comando | O que faz |
|---|---|
| `delonix-kernel setup [url]` | clona a mainline (ou o URL que passares) para `~/src/linux`, verifica `b4`, `sparse`, `pahole`, `virtme-ng`, e diz-te o que falta no teu `git send-email` |
| `delonix-kernel config [--local]` | parte da configuração do kernel a correr (`/proc/config.gz`), responde às opções novas com o default, e liga símbolos de depuração, BTF, kprobes e ftrace. O `--local` reduz aos módulos carregados **neste momento** |
| `delonix-kernel build [--install] [--boot] [--llvm]` | compila com `nproc-2` tarefas, dentro de um cgroup de peso reduzido para o desktop continuar utilizável |
| `delonix-kernel boot` | arranca o kernel compilado numa VM (virtme-ng) |
| `delonix-kernel install` | instala como entrada separada: módulos, kernel, preset do initramfs, GRUB |
| `delonix-kernel remove <versão>` | remove um que instalaste (recusa-se a remover o que está a correr) |
| `delonix-kernel check` | corre o `sparse` sobre o que está a ser recompilado (`C=1`) |
| `delonix-kernel patches …` | `get` uma série da lore, `prep` a tua, `send` para revisão |
| `delonix-kernel status` | o que corre, o que está clonado, o que tens instalado |

Ambiente: `DELONIX_KERNEL_SRC` (por omissão `~/src/linux`),
`DELONIX_KERNEL_JOBS`, `DELONIX_KERNEL_SUFFIX`, `DELONIX_KERNEL_LLVM=1`.

## O que o `config` decide por ti, e porquê

**Partir da configuração a correr.** Um kernel `defconfig` normalmente não
arranca no teu portátil — sem driver para o NVMe, sem driver para o wifi. O
`/proc/config.gz` é a configuração que está demonstravelmente a funcionar neste
hardware, agora.

**`olddefconfig`, não `oldconfig`.** Entre duas versões do kernel há centenas de
símbolos novos. O `oldconfig` pergunta por cada um; o `olddefconfig` assume o
default. Um passo de cinco segundos em vez de uma hora a carregar em Enter.

**Símbolos de depuração e BTF ligados.** O `DEBUG_INFO_DWARF5` é o que transforma
um *stack trace* em números de linha; o `DEBUG_INFO_BTF` é o que faz o
`bpftrace` e o CO-RE funcionarem de todo. Custam tempo e disco — e são a razão
pela qual estás a compilar um kernel em vez de usar o da distro.

**`--local` quando queres velocidade.** O `make localmodconfig` mantém só os
módulos carregados naquele instante, o que costuma transformar 90 minutos de
compilação em 8. A armadilha é real e o comando avisa: liga primeiro tudo o que
usas — dock, webcam, adaptadores USB — porque o que não estiver carregado não
será compilado.

## O fluxo de patches

O kernel funciona por e-mail, e isso não vai mudar. O `b4` é o que torna isso
suportável:

```bash
delonix-kernel patches get https://lore.kernel.org/all/<message-id>/
#   obtém a série inteira, pela ordem certa, e aplica-a

delonix-kernel patches prep -n o-meu-tema
#   começa a tua série

delonix-kernel patches send *.patch
#   envia para revisão
```

O `git send-email` precisa de três módulos Perl de que ninguém se lembra
(`perl-authen-sasl`, `perl-net-smtp-ssl`, `perl-mime-tools`) — sem eles falha na
autenticação com um erro que não ajuda ninguém. Vêm instalados.

Antes do primeiro patch, lê o
`Documentation/process/submitting-patches.rst` na própria árvore. Não é longo, e
responde à maior parte do que um revisor teria de te dizer.

## Ferramentas que vêm para isto

| Ferramenta | Para quê |
|---|---|
| `b4` | obter, aplicar e responder a séries da lore.kernel.org |
| `virtme-ng` | arrancar o kernel acabado de compilar, em segundos, sem instalar |
| `sparse` | o verificador semântico do próprio kernel (`make C=1`) |
| `pahole` | gera o BTF — sem ele não há CO-RE nem bpftrace útil |
| `crash` | analisar um vmcore |
| `trace-cmd`, `bcc`, `bpftrace` | ftrace e eBPF com interface humana |
| `cscope`, `global` | navegar 30 milhões de linhas sem um IDE |
| `patchutils`, `quilt` | comparar duas versões de um patch, gerir uma pilha |
| `python-sphinx` | compilar a `Documentation/` localmente |

## Se a compilação falhar

```bash
delonix-kernel status              # o que está clonado, configurado, instalado
cd ~/src/linux && make -j1 2>&1 | tail -40   # compilação em série: erros legíveis
```

Uma compilação que falha com `-j32` e um erro ilegível é, quase sempre, um erro
real enterrado na saída paralela. Recompilar essa parte com `-j1` custa um
minuto e dá-te a mensagem verdadeira.
