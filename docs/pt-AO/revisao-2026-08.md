# Revisão do DelonixOS — Agosto de 2026

Revisão completa a pedido: bugs, gaps e problemas de optimização. O que está
corrigido está marcado; o que não está, também — e diz porquê.

Método: varredura automática (shellcheck em tudo o que enviamos, mais as classes
de bug que já nos morderam), leitura do código que decide, e o que se viu a
arrancar a ISO. As três dão coisas diferentes, e a última deu as piores.

---

## O achado principal: as correcções não chegavam à imagem

**Gravidade: crítica. Corrigido.**

O `buildiso` guarda um marcador por fase e salta as que já estão feitas. Nós
construímos com `-c` para não pagar horas por tentativa. A consequência não me
ocorreu durante uma semana inteira:

| A alteração | Vive na fase | O que eu mandava limpar |
|---|---|---|
| `systemd.firstboot=off` | `make_grub` | `clean-live` |
| `os-release`, cores, GRUB | `make_image_desktop` | `clean-live` |
| Calamares, autologin | `make_image_live` | `clean-live` ✓ |

Ou seja: correcções escritas, build a passar, e ISOs testadas **sem elas
dentro**. Quatro tentativas ao mesmo ecrã de fuso horário perderam-se assim, e
a causa não era nenhuma das que investiguei — era o cache.

A correcção não é lembrar-me do mapeamento. Cada fase declara de que ficheiros
depende, e o build compara datas antes de construir, como o `make` faz:

```
→ a verificar que fases ficaram desactualizadas
  make_image_desktop: desktop-overlay/usr/lib/os-release mudou → vai repetir
  make_grub: profile.conf mudou → vai repetir
```

**Lição que fica escrita:** quando uma correcção "não funciona" três vezes, o
problema raramente está nos detalhes dela. Está numa camada que não se
questionou.

---

## Bugs

### 1. Os pacotes da casa nunca actualizam numa máquina instalada

**Gravidade: alta. Corrigido.**

`pkgver=1.0.0` e `pkgrel=1`, fixos nos quatro PKGBUILD. Numa máquina já
instalada, o `pacman -Syu` nunca vê nada mais recente — o branding, a afinação
e as ferramentas ficam congelados na versão que veio na ISO.

Isto anula a razão pela qual empacotámos estas coisas. Está escrito no nosso
próprio `Packages-Desktop`: «é a diferença entre uma ISO que envelhece e uma
distro que recebe actualizações». Com versão fixa, é a ISO que envelhece.

A versão passa a ser derivada do git — `1.0.0.r39.gaa90d23` — e cada commit
produz uma versão estritamente maior, que é o que o pacman compara.

### 2. Duas pastas de vídeos no home

**Gravidade: média. Corrigido.**

Via-se no `ls` do live: `… Templates  Videos  Vídeos`. O skel trazia uma pasta
`Vídeos` criada à mão e o `xdg-user-dirs-update` criava `Videos` no primeiro
login. Passa a haver um `user-dirs.dirs` como fonte única, com nomes em inglês —
são caminhos que aparecem em scripts e configurações, e um acento aí é uma fonte
de problemas que não paga o que dá.

### 3. O OBS gravava para uma pasta que não existe

**Gravidade: média. Corrigido.**

`RecFilePath=/home/delonix/Vídeos/DelonixOS` — o utilizador `delonix` em
código-fixo. Numa máquina instalada o utilizador tem outro nome, e a gravação
falhava. Passa a `~/Videos/DelonixOS`.

Varri o resto do projecto à procura da mesma classe: os outros `delonix` que
aparecem são nomes de tema, de perfil `tuned`, ou o serviço do live — onde o
utilizador é mesmo fixo por desenho.

### 4. O atuin gritava em cada shell nova

**Gravidade: baixa, mas é a primeira coisa que se vê. Corrigido.**

```
Error: could not load client settings
Caused by: failed to create directory `~/.local/share/atuin`
```

Um erro de Rust com localização de ficheiro-fonte, em cada terminal aberto. As
pastas passam a ser criadas antes, e a falha é silenciosa quando o home é só de
leitura: um histórico que não carrega não é motivo para encher o ecrã de quem só
quer um terminal.

### 5. O vermelho da marca usado como cor de interface

**Gravidade: baixa (UI/UX). Corrigido.**

O `#e0202f` aparecia 22 vezes no esquema de cores do Plasma, mais o fundo da
barra do tmux, a selecção do kitty, o cursor, o prompt e as cores do fzf. A 100%
de saturação é correcto num logótipo e cansativo como cor de interface,
sobretudo em fundos de selecção, que ocupam áreas grandes.

Três papéis, três tons do mesmo matiz: realce `#b03a44`, selecção com fundo
escuro `#4a2228` e texto claro (em vez do inverso), erro `#e88a8e`. O vermelho
vivo fica para o logótipo — e para o `error_symbol` do prompt, onde vermelho é
semântica e não decoração.

---

## Gaps

### O que nunca foi exercitado a sério

Estas partes existem, passam nas verificações estáticas, e **nunca correram
contra o que prometem**:

| Componente | O que falta provar |
|---|---|
| `delonix-toolbox install <perfil>` | nenhum perfil foi instalado numa máquina real |
| `delonix-toolbox db start` | as três bases de dados nunca arrancaram |
| `delonix-toolbox add kernel` | testada a listagem e os erros; a instalação e a compilação, não |
| `delonix-toolbox lab up` | os laboratórios nunca subiram |
| `delonixos --build-from` | verificado em contentores para Ubuntu/Debian/Zorin/Arch; Fedora nunca (largura de banda) |
| Instalação a sério | o Calamares abre; as páginas de partição, utilizador e resumo estão por ver |

Não é dívida escondida — é o que distingue «implementado» de «provado», e o
projecto diz que a diferença importa.

### A ISO ainda são ~5 GB

Depois de tirar 2,67 GB do que se instala num comando, o que resta grande é o
que a distro **é**: `rust` 320 MB, `clang` 267, `gcc` 232, `go` 226, `trivy`
249, `firefox` 304, mais o kernel e os drivers. Cortar aí seria cortar a razão
de existir.

Para descer aos 4 GB seria preciso uma **edição** sem as toolchains de
compilação — e isso é um produto novo, não uma limpeza.

---

## Optimização

### O que já está feito e medido

- Fases invalidadas por dependência: deixa de haver builds inúteis e deixa de
  haver correcções que não chegam.
- Mirrors escolhidos por alcançabilidade **e** débito medidos daqui, não pela
  API de terceiros — que escolheu servidores que esta rede nem resolve.
- `DisableDownloadTimeout` e `ParallelDownloads = 2`: numa ligação a ~120 KB/s,
  o pacman abortava a transação inteira quando um ficheiro estagnava.
- `iso-profiles` em cache: uma avaria do GitLab deixa de parar o build.
- 16 → 11 pacotes do AUR compilados: menos vinte minutos por tentativa.

### O que ainda custa e não tem correcção fácil

**A ligação.** Medido: todos os mirrors dão entre 60 e 194 KB/s a partir desta
máquina. Não é problema de mirror nenhum. Um build completo descarrega ~4 GB, o
que dá cinco a nove horas. O que ajuda é o que já está: a cache de pacotes
sobrevive entre tentativas e o timeout está desligado, por isso uma interrupção
deixa de perder o que já veio.

---

## As três verificações que este projecto ganhou por ter falhado

Cada uma nasceu de um build perdido, e cada uma foi testada ao contrário —
partindo de propósito o que ela deve apanhar:

1. **`(( n++ ))` em scripts com `set -e`** — o pós-incremento devolve o valor
   antigo; um 0 é estado 1 e mata o processo. Invisível ao `bash -n`; o
   shellcheck só o classifica como *info*.
2. **Crases dentro de aspas duplas** — a substituição de comando só é analisada
   em execução, por isso o script passa no `bash -n` e falha em produção.
3. **Marca do Calamares** — `settings.conf` `branding:` == nome da pasta ==
   `componentName:` interno. Divergirem dá um «Cowardly refusing to continue»
   que só se vê a correr o binário à mão no live.

---

## O que eu faria a seguir, por ordem

1. **Arrancar a ISO deste build.** É a primeira que leva de facto todas as
   correcções, e há três coisas por confirmar que só se vêem no ecrã: o fuso
   deixar de travar, o `os-release` com DelonixOS, e o wallpaper estável.
2. **Instalar a sério**, com um disco virtual, e percorrer o instalador até ao
   fim. É onde está o texto que ainda não vimos.
3. **Exercitar o `delonix-toolbox`** numa máquina instalada — os perfis, as
   bases de dados e os laboratórios, por esta ordem.
4. **Decidir a licença** ([licenciamento.md](licenciamento.md)) — o CLA é a
   única decisão irreversível, e fecha-se sozinha na primeira contribuição
   externa.

---

> Autor: **Walter Angolar** ·
> [LinkedIn](https://www.linkedin.com/in/walter-angolar-02a96b24/) ·
> [GitHub](https://github.com/angolardevops)
