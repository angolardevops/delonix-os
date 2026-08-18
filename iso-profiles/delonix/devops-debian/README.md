# DelonixOS — edição Debian/Ubuntu

Segunda edição, a par da Manjaro. **Ainda não constrói** — esta pasta é a
fundação, e o que falta está escrito no fim.

## Porque Ubuntu 24.04 e não a ISO do Zorin

O pedido foi «construir baseado no ZorinOS». Três factos mudaram o desenho:

1. **O Zorin já é um derivado do Ubuntu.** O que ele acrescenta — tema, layouts
   de ambiente, algumas aplicações — é exactamente a camada que substituiríamos
   pela identidade Delonix. Herdá-la para a remover não paga o que custa.

2. **A marca.** Remasterizar e redistribuir a ISO deles obriga ao mesmo trabalho
   de *rebranding* que acabámos de fazer com a Manjaro — e o Zorin, ao contrário
   da Manjaro, vive de uma edição Pro paga. É terreno onde não vale a pena pisar
   sem necessidade.

3. **A ligação.** A ISO do Zorin são ~4 GB. A 190 KB/s medidos nesta máquina,
   são cerca de seis horas só para começar.

A base real do Zorin 18 é o **Ubuntu 24.04 LTS**, e é sobre ela que construímos —
como a nossa própria CLI já declarava:

```python
"zorin": { "base": "ubuntu", "18": {"base_version": "24.04"} }
```

Quem quiser a *aparência* do Zorin tem-na como escolha de tema, não como
dependência da distribuição.

## O que se transfere da edição Manjaro, e o que não

| | |
|---|---|
| **Transfere-se** | a curadoria (o porquê de cada pacote), a marca e os assets, a documentação, as ferramentas `delonix-*`, a afinação de sistema (sysctl, udev, cgroups, tuned) |
| **Muda** | `manjaro-tools` → `live-build`; `pacman` → `apt`; `.pkg.tar.zst` → `.deb`; `mhwd` → `ubuntu-drivers`; Calamares mantém-se, com módulos diferentes |
| **Números** | 444 pacotes explícitos a mapear; ~35 têm o mesmo nome em apt |

## Estado

- [x] Decisão de base tomada e justificada
- [x] **Preflight** (`make preflight-debian`) — resolve a transação a seco
- [x] `Packages` inicial: 132 nomes, transação resolve com 1629 pacotes
- [ ] `Packages` completo (faltam as ferramentas que só existem como binário)
- [~] `scripts/build-debian.sh` — rootfs e squashfs provados; falta a ISO
- [ ] Pacotes `.deb` para branding/settings/tools
- [ ] Calamares para a família Debian

### O preflight veio primeiro, de propósito

Na edição Manjaro só o escrevi depois de perder quatro builds. Aqui foi a
primeira coisa — e valeu logo à primeira execução, com dois nomes errados
apanhados em dois minutos em vez de quarenta:

```
✗ não existe no Ubuntu 24.04: dive        → é binário do GitHub, vai para o toolbox
✗ não existe no Ubuntu 24.04: spectacle   → em apt chama-se kde-spectacle
```

Depois de corrigidos: **132 pacotes → 1629 com dependências, sem conflitos.**

### A mecânica está provada

Num contentor, com três pacotes da nossa lista, para não descarregar 4 GB:

```
mmdebstrap 1.4.3 · success in 70.9 seconds
rootfs 360 MB   →  squashfs zstd-19: 107 MB
PRETTY_NAME="Ubuntu 24.04 LTS"  ·  zsh ✓  ·  rg ✓
```

### Porque não `live-build`

É a ferramenta clássica do Debian e faz isto tudo. Não a usamos por uma razão
que esta semana tornou clara: o valor está em conseguir **depurar**. O
live-build esconde as fases atrás de configuração própria, e quando falha a meio
é preciso aprender as convenções dele para descobrir onde.

O `build-debian.sh` são cinco passos legíveis — sistema base, pacotes, overlay,
squashfs, ISO — cada um com o seu marcador. Falha, vê-se onde, repete-se só
esse. E não corre dentro de um contentor: o `mmdebstrap` constrói um sistema
Debian a partir de qualquer host, o que nos poupa a camada que mais problemas
deu na edição Manjaro.

## Como construir para outro alvo

```bash
make preflight-debian                 # Ubuntu 24.04 (por omissão)
make preflight-debian ALVO=bookworm   # Debian 12
./scripts/build-debian.sh bookworm    # o build para o mesmo alvo
```

| Alvo | Família | O que é |
|---|---|---|
| `noble` | ubuntu | Ubuntu 24.04 LTS — **a base do Zorin 18** |
| `jammy` | ubuntu | Ubuntu 22.04 LTS — a base do Zorin 17 |
| `bookworm` | debian | Debian 12 |
| `trixie` | debian | Debian 13 |

| `zorin18` | zorin | Ubuntu 24.04 + repositórios Zorin — ver abaixo |

### O que descobri sobre os repositórios do Zorin

Pediste que cada distro assentasse na sua própria base, e fui verificar se o
Zorin tinha repositórios seus. **Têm**, e respondem — `stable`, `patches`,
`apps`. Ia dar isso por assente. O índice está vazio:

```
.../stable/dists/noble/main/binary-amd64/Packages   0 bytes
SHA256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        ← este é o SHA256 do ficheiro vazio
```

O mesmo em `jammy` (Zorin 17). Os pacotes próprios do Zorin vêm **dentro da ISO
deles**, não de um repositório público.

Portanto: `make iso zorinos` constrói sobre **Ubuntu 24.04**, que é a base real
do Zorin 18, com os repositórios dele já configurados para quando passarem a
publicar. Não é o mesmo que a ISO do Zorin, e não vale a pena fingir que é.

### Uma lista, vários alvos

Os nomes divergem, e não pouco. Medido, não suposto:

```
noble     132 pacotes → 1629 com dependências
bookworm  127 pacotes → 1579 com dependências
```

O preflight em Debian apanhou cinco que eu tinha escrito a pensar em Ubuntu:
`ubuntu-minimal`, `calamares-settings-ubuntu-common`, `git-delta`,
`linux-tools-generic` e `rustup`. Nenhum foi removido — cada um ganhou o
equivalente Debian ou uma condição:

```
>ubuntu linux-tools-generic     # o `perf`
>debian linux-perf              # o mesmo binário, outro nome
```

A sintaxe é a do `manjaro-tools`, que já conhecemos: `>ubuntu`, `>bookworm`,
`>!debian` para excluir. E o `lib-debian.sh` é partilhado pelo preflight e pelo
build **de propósito** — na edição Manjaro os dois divergiram, e isso deixou
passar uma versão de 2024 que custou três builds.

### A regra desta edição

Nenhum nome entra nesta lista sem passar pelo preflight. É barato e é o que
distingue uma lista que parece certa de uma que resolve.

O `preflight` é o que mais falta e o que mais vale: a lição desta semana foi que
resolver a transação a seco, antes de construir, poupa horas. Em apt isso é
`apt-get install --simulate`, e deve entrar antes de qualquer outra coisa.
