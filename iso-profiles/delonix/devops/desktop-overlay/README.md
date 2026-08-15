# desktop-overlay

Ficheiros copiados para dentro da imagem instalada. **Só entra aqui o que não
ganha nada em ser actualizado depois** — tudo o resto é pacote (`packaging/`),
porque um ficheiro de overlay é escrito uma vez e nunca mais muda.

O que fica, e porquê:

| Ficheiro | Motivo |
|---|---|
| `etc/skel/**` | só é lido ao criar um utilizador; actualizá-lo depois não muda nada a quem já existe |
| `etc/default/grub` | pertence ao pacote `grub` — o pacman recusaria que outro pacote o reclamasse |
| `etc/plymouth/plymouthd.conf` | idem, pertence ao `plymouth` |
| `etc/motd` | pertence ao `filesystem` |

Os dois ficheiros de terceiros são mantidos coerentes por ganchos do pacman
(`packaging/delonix-os-branding/hooks/`), que reaplicam a nossa escolha sempre
que o `grub` ou o `plymouth` são actualizados.

**Antes de acrescentar aqui um ficheiro**, pergunta: se isto estiver errado na
v1.0, como é que o corrijo em máquinas já instaladas? Se a resposta não for
"com um `pacman -Syu`", o sítio certo é `packaging/`.
