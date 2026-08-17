# Documentação

O diagnóstico completo do caso, incluindo as hipóteses erradas e a evidência que derrubou cada uma.
Instruções de uso ficam no [README da raiz](../README.md).

| Documento | Do que trata |
|---|---|
| [01-HARDWARE.md](01-HARDWARE.md) | A máquina e tudo que foi medido nela — e o que cada medição **eliminou** como causa |
| [02-CASO-LOL.md](02-CASO-LOL.md) | O caso completo: log de partida de 29,6 min, o núcleo em 99%, benchmark dos 16 núcleos, baseline realista do 5700X |
| [03-COMO-FUNCIONA-O-LOLBOOST.md](03-COMO-FUNCIONA-O-LOLBOOST.md) | O script por dentro: as 6 etapas, as decisões de projeto e as armadilhas que apareceram medindo |
| [04-METODO-E-LICOES.md](04-METODO-E-LICOES.md) | O método de diagnóstico, o que se provou **placebo**, o que dá **ban**, e os erros cometidos no caminho |
| [05-PENDENCIAS.md](05-PENDENCIAS.md) | O que ainda não foi feito, com o ganho esperado de cada item — e o que é troca de segurança por desempenho |

Dados de apoio em [`../exemplo/`](../exemplo/): ranking dos núcleos derivado de 1.058.139 frames do
PresentMon, a investigação de baseline e um guia de tuning de RAM/PBO.

---

### Se você só quer entender a ideia central, leia nesta ordem

1. **[02-CASO-LOL.md](02-CASO-LOL.md)** → o log que resolveu o caso: um núcleo em 99% e a GPU em 10%
2. **[04-METODO-E-LICOES.md](04-METODO-E-LICOES.md)** → por que "PC fraco" quase nunca é o diagnóstico,
   e por que otimizadores podem ser o problema
3. **[03-COMO-FUNCIONA-O-LOLBOOST.md](03-COMO-FUNCIONA-O-LOLBOOST.md)** → como isso virou script

> Estes documentos registram os **erros** junto com os acertos, de propósito: hipóteses que caíram,
> afirmações feitas sem verificar, e correções que pareciam críticas e a medição mostrou que não
> eram. O método é o produto tanto quanto o script.
