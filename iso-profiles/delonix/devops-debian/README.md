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
- [ ] `Packages` mapeado (444 nomes)
- [ ] `scripts/build-debian.sh` com live-build
- [ ] Pacotes `.deb` para branding/settings/tools
- [ ] Calamares para a família Debian
- [ ] Preflight equivalente (`apt-get --simulate`)

O `preflight` é o que mais falta e o que mais vale: a lição desta semana foi que
resolver a transação a seco, antes de construir, poupa horas. Em apt isso é
`apt-get install --simulate`, e deve entrar antes de qualquer outra coisa.
