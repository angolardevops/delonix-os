# Sistema de ficheiros e layout de disco

O instalador sugere **Btrfs** com um layout de subvolumes pensado para quem
corre VMs, clusters locais e builds. Esta página explica a escolha — e quando
escolher outra coisa.

> 🇬🇧 [This page in English](../en/filesystems.md)

## A recomendação, em uma linha

| Perfil | Recomendação |
|---|---|
| Posto de trabalho (o caso normal) | **Btrfs** com os subvolumes abaixo |
| Máquina que só quer arrancar e não falhar | **ext4** |
| Disco separado só para imagens de VM | **XFS** |
| Servidor de armazenamento com discos a sobrar | **ZFS**, e não como raiz |

## Porquê Btrfs por omissão

Três razões concretas, não ideológicas:

**Instantâneos antes de cada actualização.** A distro traz `snapper` +
`snap-pac`: cada `pacman -Syu` tira um instantâneo antes de mexer no sistema.
Numa distro *rolling*, isto é a diferença entre um susto de dois minutos e um
fim-de-semana a reinstalar. Sem Btrfs (ou ZFS), esta rede de segurança não
existe.

**Compressão que torna o disco mais rápido.** `compress=zstd:1` não está lá para
poupar espaço — está para **ler menos bytes**. Num NVMe, descomprimir custa menos
do que ler os bytes a mais, por isso o sistema fica simultaneamente mais rápido e
mais pequeno. O nível 1 é o ponto em que isso ainda é verdade; níveis altos
poupam mais espaço e começam a custar CPU.

**Subvolumes em vez de partições.** Num posto que corre VMs e clusters locais,
o espaço nunca está onde se previu. Com partições fixas, `/var` enche enquanto
`/home` tem 200 GB livres. Com subvolumes, partilham o mesmo espaço e continuam
a poder ter políticas diferentes.

## O layout, e o porquê de cada peça

```
/boot/efi   1 GiB    FAT32     (DELONIX_EFI)
/           Btrfs
├── @              →  /
├── @home          →  /home
├── @cache         →  /var/cache
├── @log           →  /var/log
├── @libvirt       →  /var/lib/libvirt
├── @delonix       →  /var/lib/delonix
└── @snapshots     →  /.snapshots
swap        pequena, só para hibernar
```

| Subvolume | Motivo |
|---|---|
| `@home` fora do `@` | um *rollback* do sistema não pode levar o teu trabalho atrás |
| `@cache` e `@log` | restaurar logs e caches antigos é pior do que perdê-los; ficam fora dos instantâneos |
| `@libvirt` | uma imagem de VM tem dezenas de GB. Dentro dos instantâneos, cada actualização "guardaria" esses GB — e os instantâneos passariam a ser impraticáveis |
| `@delonix` | o mesmo raciocínio para as imagens de container do Delonix Runtime |
| `@snapshots` | onde o `snapper` guarda o que tira |

**Swap pequena, de propósito.** A troca de páginas é feita em RAM pelo `zram`
(metade da RAM, comprimida com zstd), que é ordens de grandeza mais rápido do que
o disco. A partição de swap existe só para **hibernar** — precisa de caber a RAM
toda, e é a única razão para ela ser maior.

## Quando NÃO usar Btrfs

**ext4** — quando o critério é "tem de arrancar sempre e ser reparável em
qualquer lado". Sem instantâneos e sem compressão, mas qualquer live-CD do mundo
o repara, e nunca ninguém precisou de ler um manual para o fazer. Se a máquina é
crítica e não é tua, é uma escolha defensável.

**XFS** — para um disco separado só com imagens de VM ou dados grandes. Aguenta
melhor escrita paralela em ficheiros enormes e não fragmenta como o Btrfs com
ficheiros de acesso aleatório. Numa raiz, perde-se o que interessa (instantâneos)
sem ganhar o suficiente. Montado em `/var/lib/libvirt`, faz sentido.

> Se puseres imagens de VM em Btrfs — que é o que acontece por omissão — o
> subvolume `@libvirt` já é criado, mas vale a pena desligar *copy-on-write* nessa
> pasta: `chattr +C /var/lib/libvirt/images` (num directório vazio). Sem isso,
> uma imagem de disco de acesso aleatório fragmenta-se com o tempo.

**ZFS** — o melhor sistema de ficheiros desta lista em quase tudo: checksums de
ponta a ponta, compressão, instantâneos, *send/receive* para backup. E mesmo
assim **não vem por omissão**, por uma razão prática: o módulo é externo ao
kernel (licença incompatível), por isso cada actualização de kernel pode deixar a
máquina sem arrancar até o módulo ser recompilado. Numa distro *rolling*, isso
acontece com frequência.

Faz sentido num servidor de armazenamento com kernel fixo, ou como *pool* de
dados separado da raiz — não como raiz de um posto de trabalho que actualiza
todas as semanas.

## Verificar depois de instalar

```bash
findmnt -t btrfs -o TARGET,SOURCE,OPTIONS      # subvolumes e opções
btrfs filesystem usage /                        # espaço real (≠ df)
compsize /                                      # quanto a compressão está a poupar
snapper -c root list                            # os instantâneos existem?
sudo btrfs filesystem defragment -r -czstd /var/log   # se os logs incharem
```

Um detalhe que confunde toda a gente: o `df` **mente** em Btrfs. Um sistema com
compressão e subvolumes reporta números que não batem certo. O
`btrfs filesystem usage` é a fonte de verdade.
