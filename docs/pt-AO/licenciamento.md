# Licenciamento do DelonixOS — modelos e consequências

Documento de decisão para o titular do projecto. **Não é aconselhamento
jurídico** — antes de valer perante terceiros, isto deve ser revisto por um
advogado de propriedade intelectual.

---

## Três factos que condicionam tudo o resto

### 1. Licenciar não é abdicar da propriedade

É a confusão mais comum, e vale a pena ser explícito: **o direito de autor nunca
é transferido por uma licença de código aberto**. Com a GPL-3.0 que já está no
repositório, Walter Angolar é e continua a ser o titular de todo o trabalho
original. Uma licença diz o que os outros podem fazer com o teu trabalho — não
deixa de ser teu.

Ou seja, "open source mas com direito de propriedade" **já é a situação
actual**. A pergunta verdadeira é outra: *que controlo queres exercer, e sobre
o quê?*

### 2. A ISO leva código que não é teu e não podes relicenciar

A imagem final inclui cerca de 1600 pacotes de terceiros — o kernel Linux
(GPL-2.0), o Plasma (GPL/LGPL), o Firefox (MPL), o Chrome e o Edge
(proprietários, redistribuíveis sob os termos deles). Nada disso passa a ser
teu por ir dentro da tua ISO, e nenhuma licença que escolhas pode impedir
alguém de redistribuir essas partes.

Isto tem uma consequência prática que é preciso encarar: **não existe nenhum
modelo em que o DelonixOS seja "fechado"**. A dúvida é só sobre o teu trabalho
original.

### 3. O que é teu, e é bastante

| Componente | Dimensão | Podes licenciar como quiseres |
|---|---:|:---:|
| Scripts de construção | 2 095 linhas | sim |
| CLI `delonixos` | 947 linhas | sim |
| Ferramentas `delonix-*` | 1 960 linhas | sim |
| Perfil da ISO (curadoria) | 899 linhas | sim |
| Configuração e overlays | 87 ficheiros | sim |
| Documentação | 3 850 linhas | sim |
| **Marca**: nome, logótipo, temas, splash | 42 imagens + temas | sim — e é o mais forte |

A curadoria também conta. As 479 linhas de `Packages-*`, com o «porquê» de cada
escolha, e a lista do que foi deliberadamente removido, são trabalho
intelectual teu — mesmo sendo uma lista de nomes de pacotes alheios.

---

## A marca é a alavanca mais forte, e quase toda a gente a ignora

O direito de autor protege o **código**. A marca protege o **nome e o
símbolo** — e são direitos separados, que vivem em leis diferentes.

Podes ter o código totalmente aberto e a marca totalmente fechada. Alguém pode
pegar no DelonixOS, alterá-lo e distribuí-lo — mas **não lhe pode chamar
DelonixOS nem usar o teu logótipo**. Tem de mudar o nome e a identidade.

Isto não é uma teoria: é exactamente o que fazem a Red Hat, a Mozilla e a
própria Manjaro. A GPL-3.0 prevê isto de forma expressa — a secção 7(e) permite
«recusar a concessão de direitos ao abrigo do direito das marcas» como termo
adicional compatível com a licença.

Na prática, protege-te de aquilo que realmente te faria mal:

- alguém vender «DelonixOS Pro» que não é teu;
- uma versão modificada com malware a circular com o teu nome;
- concorrentes a aproveitar a reputação que construíste.

E não te protege — nem deve — de alguém estudar, aprender e reutilizar o
código. Isso é o que faz um projecto crescer.

---

## Os três modelos

### A — GPL-3.0 + política de marca

**O que é:** o que já tens, tornado explícito. Código sob GPL-3.0, titularidade
declarada em teu nome, política de marca a proibir o uso de «Delonix», do
logótipo e dos temas em obras derivadas sem autorização escrita, e um CLA
(acordo de contribuição) para quem contribuir.

| | |
|---|---|
| **Permite** | usar, estudar, modificar, redistribuir, usar comercialmente |
| **Obriga** | quem distribuir um derivado publica o código sob GPL-3.0 |
| **Proíbe** | usar o nome e a identidade Delonix sem autorização |
| **É open source pela OSI?** | **Sim** |
| **Receita possível** | apoio profissional, formação, implementações, hardware pré-instalado, edição «Pro» com extras teus |
| **Quem faz assim** | Red Hat, Mozilla, Manjaro, Fedora |

**A favor:** máxima adopção e credibilidade. Entra em qualquer mirror, qualquer
repositório, qualquer comunidade. O copyleft da GPL já te protege do pior — quem
melhorar o DelonixOS e distribuir tem de publicar as melhorias.

**Contra:** não impede um concorrente de pegar no código, mudar o nome e vender.
Mas terá de publicar o que fizer, e não leva a tua marca — que é o que os
clientes reconhecem.

---

### B — Dupla licença: GPL + comercial

**O que é:** o modelo A, mais uma segunda via. Quem não quiser cumprir o
copyleft — tipicamente uma empresa que quer integrar o teu código num produto
fechado — compra-te uma licença comercial.

| | |
|---|---|
| **Permite** | tudo o que o modelo A permite, mais uma saída paga do copyleft |
| **Obriga** | **CLA obrigatório de todos os contribuidores**, sem excepção |
| **É open source pela OSI?** | **Sim** (a via GPL é que conta) |
| **Receita possível** | licenças comerciais, além de tudo o que o modelo A permite |
| **Quem faz assim** | Qt, MySQL (antes da Oracle), GitLab |

**O ponto crítico:** só podes vender uma licença comercial sobre código de que
detenhas **todos** os direitos. No dia em que aceitares uma contribuição de
alguém sem CLA assinado, essa parte deixa de ser tua para vender — e não há
volta a dar sem reescrever essa contribuição.

Se há hipótese de um dia quereres isto, **o CLA tem de existir desde a primeira
contribuição externa**. É a decisão mais irreversível de todo este documento.

---

### C — Source-available com restrição comercial

**O que é:** estilo BSL (Business Source License) ou Elastic License 2.0. O
código é visível e utilizável, mas com uma proibição expressa — normalmente
oferecer o produto como serviço, ou concorrer directamente contigo. A BSL
converte-se automaticamente em licença livre ao fim de um prazo, tipicamente
quatro anos.

| | |
|---|---|
| **Permite** | ver, usar internamente, modificar |
| **Proíbe** | oferecer como serviço, concorrer com o titular |
| **É open source pela OSI?** | **Não** |
| **Receita possível** | licença comercial para uso proibido |
| **Quem faz assim** | HashiCorp (Terraform), MariaDB, Sentry, Elastic |

**Três problemas concretos, para uma distribuição:**

1. **Não resolve o que te preocupa.** A restrição só se aplica ao teu código —
   os 1600 pacotes GPL da ISO continuam livres. Quem quiser copiar o DelonixOS
   copia o essencial na mesma; só teria de reescrever os teus scripts.

2. **Custa adopção.** Distribuições source-available não entram em mirrors
   comunitários, ficam de fora de listas e repositórios, e a comunidade
   DevOps — que é o teu público — reage mal. A HashiCorp mudou para BSL e
   nasceu um *fork* (OpenTofu) que hoje é o que muita gente usa. Aliás, é o
   `opentofu` que vem na tua própria ISO, e pelo motivo inverso: a licença do
   Terraform deixou de servir.

3. **Complica a GPL.** Alguns dos teus scripts interagem de perto com
   ferramentas GPL. Misturar licenças incompatíveis num mesmo projecto cria
   problemas jurídicos que só se descobrem tarde.

---

## O modelo que eu recomendo, e porquê

**Modelo A, com CLA desde já.**

O raciocínio em três passos:

1. **Já tens a propriedade.** A GPL-3.0 não ta tira. O que falta é dizê-lo em
   voz alta — titularidade explícita, cabeçalhos de direito de autor, e um
   `NOTICE` a separar o que é teu do que é de terceiros.

2. **O valor está na marca e na curadoria, não no segredo.** Os teus scripts
   não são o difícil de copiar — o difícil é a curadoria de 479 pacotes com
   justificação, a afinação que não trava a máquina, e a confiança de quem
   instala. Nada disso se protege escondendo código; protege-se com uma marca
   forte e com trabalho continuado.

3. **O CLA é a única decisão irreversível.** Custa quase nada agora e vale
   muito depois: mantém aberta a porta do modelo B, se um dia a quiseres.
   Sem ele, essa porta fecha-se na primeira contribuição externa.

### O paralelo mais útil: Zorin OS

Vale a pena olhar para o Zorin, que conheces. O Zorin OS é livre e aberto, e a
empresa vive do **Zorin OS Pro** — que não é código fechado, são disposições de
ambiente, arte, aplicações e apoio adicionais. Ninguém paga por acesso ao
código: paga pela curadoria, pela marca e pelo trabalho de os manter.

É exactamente a posição em que o DelonixOS está bem colocado: um «DelonixOS
Pro» com laboratórios prontos, integração com a plataforma N'GolaCloud, apoio e
formação. Nada disso exige fechar uma linha de código.

---

## O que fazer a seguir, conforme a decisão

**Se escolheres A** (recomendado) — escrevo, em EN e pt-AO:

- `LICENSE` mantém-se GPL-3.0, com aviso de titularidade
- `TRADEMARK.md` — política de marca: o que é permitido, o que exige
  autorização, como pedir, e o procedimento de *rebranding* para derivados
- `NOTICE` — o que é original, o que vem de terceiros e sob que licenças
- `CONTRIBUTING.md` + `CLA.md` — o acordo de contribuição
- Cabeçalhos de direito de autor nos ficheiros de origem
- Registo da marca: em Angola no IAPI, e ponderar internacionalmente

**Se escolheres B** — o mesmo, mais os termos da licença comercial e um CLA com
concessão expressa de relicenciamento (é isso que a torna vendável).

**Se escolheres C** — a BSL 1.1 com data de conversão e a concessão adicional
de uso, e uma separação clara de que ficheiros ficam sob que licença. Digo-te
com franqueza que desaconselho, pelas três razões acima — mas se for a tua
decisão, escrevo-a bem feita.

---

> Autor e titular: **Walter Angolar** ·
> [LinkedIn](https://www.linkedin.com/in/walter-angolar-02a96b24/) ·
> [GitHub](https://github.com/angolardevops)
