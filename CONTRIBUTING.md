# Contributing / Contribuir

🇬🇧 **English** — Two rules make reviewing easy:

1. **Every package needs a reason.** If you add something to `Packages-*`, put
   the "why" in the comment next to it. "It's useful" is not a reason; "SREs use
   this during incidents to answer X" is.
2. **Run `make check` before opening a PR.** It validates every package against
   the Arch/AUR repositories and detects declared conflicts — the kind of problem
   that otherwise aborts a 40-minute build.

The most valuable contributions right now are **hardware reports**: does the NPU
appear in `delonix-doctor`? Does nested virtualization work on your CPU? Does the
Plymouth splash animate on your GPU?

Code comments are written in Portuguese — that is where the reasoning lives.
Documentation is bilingual (EN / pt-AO); if you change one, change the other.

---

🇦🇴 **Português de Angola** — Duas regras tornam a revisão fácil:

1. **Cada pacote precisa de um motivo.** Se acrescentares algo a `Packages-*`,
   escreve o "porquê" no comentário ao lado. "É útil" não é motivo; "os SRE usam
   isto em incidentes para responder a X" é.
2. **Corre `make check` antes de abrir um PR.** Valida cada pacote contra os
   repositórios Arch/AUR e detecta conflitos declarados — o tipo de problema que
   de outra forma aborta um build de 40 minutos.

As contribuições mais valiosas neste momento são **relatos de hardware**: a NPU
aparece no `delonix-doctor`? A virtualização aninhada funciona no teu CPU? O
splash do Plymouth anima na tua GPU?

Os comentários no código estão em português — é onde vive o raciocínio. A
documentação é bilingue (EN / pt-AO); se mudares uma, muda a outra.
