# `delonix-toolbox` — o painel de controlo do DelonixOS

A distro vem completa, mas não vem com tudo ligado. O `delonix-toolbox` é o
comando único para as decisões que ficaram deliberadamente por tomar: que
extras instalar, que bases de dados ligar, que laboratórios levantar, e quando
actualizar.

> 🇬🇧 [This page in English](../en/delonix-toolbox.md)

```bash
delonix-toolbox                 # ajuda + o que está instalado
delonix-toolbox list
```

---

## `install` / `remove` — extras a pedido

A ISO traz o que 90% das pessoas usa. O resto está aqui, agrupado por caso de
uso em vez de por pacote:

```bash
delonix-toolbox install lang-java k8s-extra
delonix-toolbox remove lang-java
```

| Perfil | Contém |
|---|---|
| `lang-java` | OpenJDK 21, Maven, Gradle |
| `lang-rust-multi` | rustup, para toolchains por projecto |
| `lang-node-extra` | yarn, deno, bun |
| `lang-python-data` | numpy, pandas, matplotlib, ipython |
| `k8s-extra` | flux, kubeseal, velero, popeye, kubent |
| `cloud-azure` | Azure CLI (AWS e GCP já vêm na ISO) |
| `gpu-amd` / `gpu-nvidia` | ROCm / CUDA (~2–3 GB) |
| `virt-extra` | firecracker, vagrant, virtctl |
| `ai` | Claude Code + Antigravity (reinstalar/actualizar) |
| `ai-local` | Ollama — modelos locais na GPU/NPU já activadas |
| `ide-extra` | VS Code, DBeaver, Postman |
| `observability` | k6, vector, prometheus (binários, não o laboratório) |
| `delonix` | Delonix Runtime + delonixctl |
| `printing` | CUPS e drivers |
| `office` | LibreOffice, Thunderbird |

O `list` marca com `✓` o que já está instalado.

---

## `db` — bases de dados, ligadas só quando fazem falta

PostgreSQL, Redis (valkey) e MongoDB **vêm instalados e parados**. Três
servidores a dormir custam ~600 MB de RAM que ninguém pediu.

```bash
delonix-toolbox db status                      # o que está a correr
delonix-toolbox db start postgres              # arranca agora (o initdb é feito por ti)
delonix-toolbox db enable postgres redis       # arranca agora E com o sistema
delonix-toolbox db stop postgres               # devolve a memória
delonix-toolbox db disable mongo
```

Sem argumento de base de dados, o comando aplica-se às três.

O `start` do Postgres trata do `initdb` na primeira vez. Sem isso, o serviço
falha com um erro que não diz a ninguém o que fazer — é o tipo de detalhe que
custa meia hora à primeira pessoa que passa por ele.

---

## `lab` — stacks locais que não vivem instaladas

Um laboratório é uma stack que se quer ligada algumas horas por semana. Corre
em containers, guarda os dados entre sessões, e não consome nada quando está em
baixo.

```bash
delonix-toolbox lab list
delonix-toolbox lab up observability
delonix-toolbox lab status
delonix-toolbox lab logs observability
delonix-toolbox lab down observability
```

**Motor**: por omissão o **Delonix Runtime** — é o motor da casa e um
laboratório é exactamente a carga para que foi feito. Para comparar
comportamentos, ou enquanto o runtime não estiver instalado:

```bash
delonix-toolbox lab up observability --target podman
delonix-toolbox lab up observability --target docker
```

O manifesto é `kind: Pod` — o mesmo formato que o `delonix pod create -f` e o
`podman kube play` consomem. No caso do docker, que não tem equivalente, o
toolbox traduz para `docker run`: o primeiro container publica as portas e os
restantes partilham a rede dele, que é o equivalente docker de um pod.

### `observability`

Prometheus + Grafana + Loki + node-exporter:

```
Grafana:    http://localhost:3000   (sem login — é local)
Prometheus: http://localhost:9090   (já a recolher métricas desta máquina)
Loki:       http://localhost:3100
```

O `node-exporter` vem com as métricas **PSI**, que são as que explicam o "está
lento" — saturação de CPU, memória e I/O, em vez de percentagens que não dizem
nada.

**As configurações são tuas.** À primeira utilização são copiadas para
`~/.local/share/delonix/labs/observability/config/` e **nunca mais são
sobrepostas**. Para o Prometheus recolher métricas do que estás a construir,
acrescenta o teu alvo ao `prometheus.yml` e volta a levantar o laboratório.

Os dados (séries temporais, dashboards, logs) ficam em `.../labs/<nome>/dados/`
e sobrevivem ao `lab down`.

---

## `update` — sistema e motor, num comando

```bash
delonix update                  # ou: delonix-toolbox update
delonix update --check          # o que mudaria, sem instalar
delonix update --delonix-only   # só o Delonix Runtime
```

Trata das três origens que compõem esta distro, que de outra forma exigiriam
três comandos diferentes:

1. os repositórios (Manjaro + `[delonix]`) e o AUR — via `yay`/`pacman`;
2. o **Delonix Runtime**, que vem dos artefactos publicados e não de
   repositório nenhum;
3. avisa quando o kernel mudou e é preciso reiniciar para o usar.

No fim mostra as versões de tudo.

> **Nota sobre o `delonix update`**: o `delonix` é o binário do runtime e não
> tem um subcomando `update`. O `.zshrc` da distro intercepta essa forma e
> delega no toolbox — e a função **desaparece sozinha** no dia em que o runtime
> ganhar o seu próprio `update`, para não esconder nada. Fora do zsh, usa
> `delonix-update` ou `delonix-toolbox update`.

---

## `eyecandy` — animações do desktop

Por omissão o KDE vem sem animações, sem blur e sem indexação de ficheiros: são
GPU, memória e latência gastas em decoração.

```bash
delonix-toolbox eyecandy on     # repõe animações, blur, transições
delonix-toolbox eyecandy off    # volta ao default do DelonixOS
```

---

## `unprivileged-ports` — publicar :80 sem root

```bash
delonix-toolbox unprivileged-ports on
delonix-toolbox unprivileged-ports off
```

Baixa o `net.ipv4.ip_unprivileged_port_start` para 80, o que permite a um
container rootless publicar as portas 80/443. É conveniente **e** é um
compromisso: qualquer processo do teu utilizador passa a poder fazer-se passar
por um serviço de sistema. Por isso não vem ligado.

---

## Ver também

- [`delonix-doctor`](ferramentas-por-perfil.md) — diagnóstico da máquina
  (rootless, cgroups, KVM/NPU, I/O, rede, laboratórios a correr)
- [`delonixos`](cli.md) — construir a ISO, ou a tua própria distro

## `add kernel` — outro kernel, com os drivers atrás

```bash
delonix-toolbox add kernel --list              # o que existe
delonix-toolbox add kernel --version 7.2       # instala, com os extramódulos
delonix-toolbox add kernel --version 7.3 --compile
```

Um comando: instala a versão pedida, traz os módulos que o teu kernel actual
tem — NVIDIA incluído — e acrescenta uma entrada nova no arranque. **Não
substitui o kernel em uso**; se o novo correr mal, reinicias e escolhes o
antigo no menu do GRUB.

### Porque é que isto não compila sempre

Compilar um kernel para o hardware da máquina soa melhor do que é. Os
repositórios trazem 6.6, 6.12, 6.18, 7.1 e 7.2 já compilados, assinados, com
actualizações de segurança automáticas e — o que mais custa a reproduzir — com
os **extramódulos** a acompanhar: `nvidia`, `nvidia-open`, `r8168`, `vhba`,
`virtualbox-host-modules`, um conjunto por versão.

Um kernel compilado à mão perde tudo isso. Os módulos proprietários passam a
depender do DKMS, que os reconstrói a cada actualização e falha quando o
fabricante ainda não suporta a versão. Numa máquina de trabalho, isso é ficar
sem ambiente gráfico numa segunda-feira de manhã.

Por isso a ordem é: **se existir pacote, instala-se o pacote**. Compila-se
quando não existe — uma versão upstream mais recente, ou um kernel com
patches — e aí o `delonix-kernel` faz o trabalho com `localmodconfig`, que gera
uma configuração só com os módulos que *esta* máquina tem carregados. É a
optimização que conta: corta o tempo de compilação para uma fracção e dá um
initramfs muito menor.

O `--compile` força a compilação mesmo havendo pacote, para quem sabe porquê —
e avisa do que está a trocar antes de começar.

### A NVIDIA, nos dois caminhos

| Caminho | Como o módulo é construído |
|---|---|
| Pacote (`--version 7.2`) | `linux72-nvidia`, já compilado e testado com esse kernel |
| Compilado (`--compile`) | `nvidia-dkms`, reconstruído a cada actualização |

Nos dois casos o comando detecta se há mesmo uma GPU NVIDIA antes de instalar
seja o que for.
