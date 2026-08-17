# Exemplo — os resultados desta máquina

**Isto é exemplo, não receita.** Tudo aqui saiu de **uma** máquina (Ryzen 7 5700X + RX 9070 XT)
e serve para dois propósitos: mostrar **que formato de saída esperar** quando você rodar o
script, e servir de evidência do que está afirmado nos [docs](../docs/).

> ⚠️ **Não copie estes valores para a sua máquina.** O melhor núcleo para o driver gráfico muda
> de PC para PC — nesta o vencedor foi a CPU 1, na sua pode ser outro. Rode o
> [`LoLBoost.ps1`](../LoLBoost/) e use **os seus** números.

Nada foi arredondado para ficar bonito.

| Arquivo | O que é |
|---|---|
| `resultado-nucleos.csv` | Ranking dos 16 núcleos lógicos calculado a partir dos frametimes brutos do benchmark |
| `LoL_Investigacao_Profunda_RESULTADO.txt` | Resultado da investigação (6 agentes de pesquisa): baseline realista do 5700X, o que vale fazer, o que é placebo, o que dá ban |
| `Tuning_RAM_e_PBO_MSI_B550.txt` | Guia passo a passo de BIOS para DDR4-3600 + FCLK 1800 e PBO/Curve Optimizer na MSI B550 |
| `GPU_Afinidade_CPU1_APLICAR.reg` | Fixa o driver gráfico na CPU 1 — **específico desta máquina** |
| `GPU_Afinidade_DESFAZER.reg` | Reverte o arquivo acima |

> ⚠️ Os dois `.reg` contêm o **Instance ID do dispositivo desta máquina**, que é único. Não
> importe em outro PC — não vai funcionar, e no melhor caso não faz nada. Use o `LoLBoost.ps1`,
> que descobre o ID da sua própria placa.

---

## Sobre o `resultado-nucleos.csv`

Origem: **AutoGpuAffinity**, 16 núcleos lógicos, 30 s por núcleo, ~66 mil frames cada
(1.058.139 frames no total). A coluna usada dos CSVs do PresentMon é `msBetweenPresents`.

Os valores estão em **FPS equivalente** (`1000 / frametime`), então **maior é melhor** em todas
as colunas:

| Coluna | Como é calculada |
|---|---|
| `Media` | `1000 /` média de todos os frametimes |
| `Low1` | `1000 /` percentil 99 dos frametimes |
| `Low01` | `1000 /` percentil 99,9 |
| `Low001` | `1000 /` percentil 99,99 |

**Critério de ranking: `Low01` (0.1% low), desempate no `Low1`.** A média é ignorada de
propósito — ela varia só 2,9% entre o melhor e o pior núcleo, o que é ruído. O sinal está nos
vales.

> **Nota de método:** os números de 1% low aqui **não são idênticos** aos que o AutoGpuAffinity
> mostra na tela dele. Ele usa a *média do 1% pior* dos frames; este CSV usa o *percentil 99*.
> São definições diferentes de "1% low" — o percentil é mais conservador. **O ranking dos
> núcleos é o mesmo nas duas contas**, o que é o que importa aqui.

Os CSVs brutos do PresentMon (**190 MB**, 16 arquivos) ficaram **fora do repositório** por
peso. Para regerar este resultado na sua máquina, rode o `LoLBoost.ps1` — ele faz exatamente
essa conta a partir dos seus próprios frametimes.
