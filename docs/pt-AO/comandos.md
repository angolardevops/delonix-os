# Referência de comandos

Cada comando `delonix-*`, para que serve, e o raciocínio por trás dos defaults.
Os comandos e as suas opções estão todos em inglês; os comentários no código
ficam em português, que é onde o raciocínio foi escrito.

> 🇬🇧 [This page in English](../en/commands.md)

| Comando | Uma linha |
|---|---|
| [`delonix-doctor`](#delonix-doctor) | esta máquina está mesmo pronta? |
| [`delonix-toolbox`](delonix-toolbox.md) | instalar extras, ligar bases de dados, correr laboratórios, **acrescentar kernels** |
| [`delonix update`](delonix-toolbox.md#update--sistema-e-motor-num-comando) | actualizar o sistema e o Delonix Runtime |
| [`delonix-load`](#delonix-load) | correr trabalho pesado sem perder a máquina |
| [`delonix-tune`](#delonix-tune) | afinar a máquina ao hardware que ela tem mesmo |
| [`delonix tunnel`](#delonix-tunnel) | pôr um serviço local numa URL pública |
| [`delonix-kernel`](kernel.md) | compilar, arrancar e instalar um kernel Linux |
| [`delonix-video`](#delonix-video) | levar gravações do OBS para o DaVinci Resolve |
| [`delonixos`](cli.md) | construir a ISO, ou a tua própria distro |

---

## `delonix-doctor`

```bash
delonix-doctor          # sai com 0 se passou tudo, 1 se algo falhou
```

Responde a uma pergunta — esta máquina consegue correr containers rootless,
clusters locais e ferramentas de plataforma? — e responde em verificações
accionáveis, não num muro de informação.

Verifica: cgroup v2 e que controladores estão **delegados** (sem `memory` e
`pids`, os containers rootless ignoram em silêncio os limites de recursos),
intervalos subuid/subgid, limites de inotify e descritores, `/dev/kvm` e se a
virtualização aninhada está ligada, GPU/NPU e OpenCL, o escalonador de I/O por
disco, BBR com `fq`, contabilidade de memória (sem ela todos os limites são
decoração), a área de transferência, laboratórios e bases de dados a correr,
sistema de ficheiros e instantâneos, e o locale.

Como sai com código diferente de zero quando falha, serve de porta em CI de
imagem — não apenas de relatório para ler.

## `delonix-load`

```bash
delonix-load cargo build --release
delonix-load --cpu 30 --mem 50% podman build .
delonix-load --status
```

O `ananicy-cpp` já baixa a prioridade dos compiladores automaticamente. Isto é o
passo seguinte: põe o comando num cgroup próprio, com peso de CPU e de I/O
reduzidos e um tecto de memória.

A diferença prática: só com `nice`, um build de 32 threads continua a poder
encher a memória e a fila do disco — e o desktop engasga na mesma. Com um
cgroup, não pode. O build fica alguns por cento mais lento e tu continuas a
trabalhar, que era a troca que querias.

## `delonix-tune`

```bash
delonix-tune                    # que hardware é este, e está afinado para ele
delonix-tune apply              # detectar e aplicar (corre no primeiro arranque)
delonix-tune profile quiet      # lab | balanced | quiet
delonix-tune thermal            # temperatura, frequência e limitação em directo
```

A mesma ISO arranca num portátil AMD Ryzen com gráficos híbridos e numa
secretária Intel vPro. O que faz uma voar faz a outra ferver — por isso nada
disto se decide quando a imagem é construída. Decide-se na máquina, a partir do
fabricante do CPU, do chassis e das GPUs presentes.

O que muda, em concreto:

| Detectado | Consequência |
|---|---|
| Tem bateria | perfil `delonix-lab-mobile` — estados de repouso profundos mantidos, EPP `balance_performance` |
| Sem bateria | perfil `delonix-lab` — repouso profundo desligado, EPP `performance` |
| CPU Intel | `thermald` ligado (é código exclusivamente Intel) |
| CPU AMD | `thermald` desligado, `k10temp` carregado — sem ele não há leitura de temperatura nenhuma |
| Duas ou mais GPUs | `switcheroo-control` ligado; `prime-run` disponível |

### Porque é que o perfil de portátil não é o perfil lento

Num portátil, `governor=performance` não é mais rápido — é mais quente. Com
`amd_pstate=active` ou `intel_pstate=active`, a decisão de frequência passa para
o próprio processador (CPPC/HWP), que chega à frequência máxima em
microssegundos quando aparece trabalho. O governor `performance` não levanta
esse tecto; só impede o processador de descer quando não há nada a fazer.

E o custo é real: um processador mantido quente em repouso começa cada
compilação já encostado ao limite térmico e limita-se mais cedo. Manter núcleos
em repouso profundo liberta orçamento térmico que os núcleos activos gastam em
turbo. Sob carga sustentada — que é o que uma compilação é — o perfil de
portátil é o mais rápido dos dois.

Se discordares para a tua máquina, `delonix-tune profile lab` força o perfil de
secretária e fica assim até mandares o contrário.

### `delonix-tune power` — para onde vai a energia

```bash
delonix-tune power
```

Num portátil híbrido há três consumidores que ninguém vê, e este comando
aponta-os. Corrido no ROG onde isto foi escrito:

```
✗ GPU NVIDIA active — 10 a 25 W, e a ventoinha a tirar esse calor
!   RTD3 não configurado
! PCIe ASPM: default — sem poupança nas ligações
! 23 dispositivos PCI sempre acordados
! sem zram — sob carga, a máquina congela em vez de comprimir
```

**A dGPU acordada é o maior de todos.** Num híbrido, com a placa integrada a
fazer o trabalho, uma NVIDIA que ninguém está a usar custa entre 10 e 25 W — a
diferença entre quatro horas de bateria e duas e meia. E é também a razão de a
ventoinha nunca parar: o calor tem de sair de algum lado.

O DelonixOS trata dos três: `NVreg_DynamicPowerManagement=0x02` liga o RTD3
(o driver desliga a placa quando o último cliente sai), as regras udev põem os
dispositivos PCI e USB em `auto`, e o ASPM comuta com a alimentação.

### A ventoinha não se controla por software

Em portáteis modernos quem manda na curva é o firmware, pelo `platform_profile`
— `asus-nb-wmi` no ROG, `hp-wmi` nos EliteBook, e equivalentes na Dell e na
Lenovo. É uma interface do kernel, igual em todos, e por isso não há código por
fabricante:

| Alimentação | Perfil | Porquê |
|---|---|---|
| corrente | `balanced` | não `performance`: manteria a ventoinha alta o dia todo por um ganho que só se vê em carga sustentada |
| bateria | `quiet` / `low-power` | tecto de potência mais baixo, ventoinha calma |

Para carga sustentada de propósito: `delonix-tune profile lab`.

## `delonix tunnel`

```bash
delonix tunnel 8080                        # provedor por omissão (pinggy)
delonix tunnel --provider cloudflare 3000
delonix tunnel --provider ngrok 8080
delonix tunnel --list                      # o que está exposto agora
delonix tunnel --stop                      # fechar
```

Um webhook do Stripe ou do GitHub tem de chegar a um serviço que corre neste
portátil, ou um colega precisa de ver uma demonstração antes de ir para
produção. O trabalho é sempre o mesmo; o que muda é o provedor, e cada um tem as
suas opções e a sua maneira de imprimir a URL.

| Provedor | Conta | Instalado como | Melhor para |
|---|---|---|---|
| **pinggy** *(omissão)* | nenhuma | nada — é SSH puro | máquina acabada de instalar; expira aos 60 min |
| **cloudflare** | nenhuma para `try-cloudflare` | `cloudflared` (repos) | demonstração que tem de aguentar a tarde |
| **ngrok** | obrigatória, mesmo grátis | `ngrok` (AUR) | quando precisas de *ver* o corpo do pedido, em `localhost:4040` |

O pinggy é o padrão por ser o único que não precisa de nada: é reencaminhamento
remoto de porta por SSH (`ssh -p 443 -R0:localhost:8080 a.pinggy.io`) e o
`openssh` já cá está. Não há binário do pinggy na ISO porque não há binário do
pinggy para instalar.

### Recusa algumas portas de propósito

Expor um serviço local significa que qualquer pessoa com a URL lhe chega — é
esse o objectivo, e é também o risco. Os serviços de desenvolvimento costumam
assumir que só tu lhes chegas, por isso as portas que quase nunca se querem
públicas (PostgreSQL, Redis, MongoDB, etcd, a API do Kubernetes…) são recusadas
sem um `--force`.

Confirma também que há mesmo alguma coisa à escuta. Um túnel para uma porta sem
nada por trás devolve 502, e isso custa dez minutos a perceber.

A URL é capturada, não apenas impressa: o `--list` mostra o que está exposto
neste momento, e a URL vai para a área de transferência quando há `wl-copy`.

> O `delonix` é o binário do runtime e não tem subcomando `tunnel`. O `.zshrc`
> intercepta a forma e delega — e deixa de o fazer no dia em que o runtime
> ganhar o seu. Fora do zsh, usa `delonix-tunnel`.

## `delonix-video`

```bash
delonix-video info aula.mkv            # avisa se o ficheiro não vai importar
delonix-video to-davinci aula.mkv      # converter para DNxHR
delonix-video publish editado.mov      # comprimir para publicar
```

Existe porque a versão **gratuita** do DaVinci Resolve para Linux não
descodifica H.264/H.265. Uma gravação do OBS simplesmente não aparece na
timeline e o erro não explica porquê — a armadilha que custa a primeira tarde a
toda a gente.

DNxHR em vez de ProRes: descodifica mais depressa em x86 e o Resolve lê-o
nativamente em Linux. O original nunca é apagado.

## Convenções comuns a todos

- **Os códigos de saída querem dizer alguma coisa.** 0 é sucesso, diferente de
  zero é falha. Qualquer um destes serve num script.
- **Nada destrutivo sem o dizer.** O `delonix-kernel install` acrescenta uma
  entrada de arranque em vez de substituir; o `delonix-video` nunca apaga a
  origem; o `delonix-toolbox install zfs` explica o risco e pergunta.
- **Uma falha explica o passo seguinte.** O `delonix-doctor` a reportar um
  controlador não delegado diz-te em que ficheiro olhar.
- **`--help` em todos**, e as primeiras linhas de cada script são a sua
  documentação — `head -20 $(which delonix-load)` é uma forma válida de a ler.
