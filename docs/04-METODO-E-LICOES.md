# 04 — Método de diagnóstico e lições

O que fez esses dois casos serem resolvidos, e o que foi descartado no caminho.

---

## O método

### 1. Medir antes de mudar

O ponto de virada do caso do LoL foi um **log de partida completa** (29 min, amostras a cada
0,5 s). Até esse momento, o diagnóstico foi uma sequência de hipóteses erradas — calor,
memory leak, disco, shaders. Nenhuma sobreviveu ao contato com os dados.

O log respondeu tudo de uma vez:
- Clock fixo em 4650 MHz → não é throttling
- 50 °C → não é temperatura
- RAM estável → não é leak
- GPU a 10% → não é a placa
- **Um núcleo lógico a 99%** → é isso

### 2. Eliminar com evidência, não com opinião

Cada hipótese descartada tinha uma prova associada:

| Descartado | Prova |
|---|---|
| GPU e driver de vídeo | O problema já existia com uma RTX 3090 |
| Software instalado, Windows | Sobreviveu a uma formatação completa |
| Plano de energia | `powercfg` mostrou "Desempenho Máximo" |
| Instabilidade elétrica | Zero eventos WHEA em 14 dias |
| Disco lento | `Get-PhysicalDisk` → NVMe SSD saudável |
| Peso gráfico | Config já estava toda no mínimo |

### 3. Entender por que o sintoma aparece em um lugar e não em outro

O argumento *"se fosse hardware, apareceria nos outros jogos também"* parecia decisivo — e era
falho:

- **AAA em 4K = GPU-bound.** Quem trabalha é a placa. O CPU fica ocioso.
- **LoL = CPU-bound single-thread.** A GPU fica ociosa. Um núcleo satura.

São gargalos **opostos**. Um teste não prova nada sobre o outro. Reconhecer isso foi o que
permitiu parar de procurar no lugar errado.

### 4. Ranquear pelo dado certo

No benchmark de núcleos, a **média** variou apenas 2,9%. O sinal estava nos **percentis baixos**:
a CPU 15 tinha **0.01% low de 448** contra **1276** da melhor — quase 3× pior — e no 0.1% low a
diferença era 1189 contra 1509. A CPU 12 é o contraexemplo perfeito: **melhor de todas em média e
em 1% low**, e quarta pior nos vales.

Escolher a métrica errada teria levado à conclusão de que "não faz diferença". Números completos
em [`exemplo/resultado-nucleos.csv`](../exemplo/resultado-nucleos.csv) e a leitura em
[02-CASO-LOL.md](02-CASO-LOL.md) — inclusive a ressalva de que é **uma única passada**, o que
torna a cauda frágil.

---

## O que se provou placebo

Analisado a partir de um pacote de "otimização" real distribuído comercialmente, mais os
achados da investigação.

| Item | Veredito |
|---|---|
| Tweaks de BCD (`useplatformtick`, `disabledynamictick`) | Sem efeito mensurável |
| `Win32PrioritySeparation=26` | Sem efeito mensurável |
| `PowerThrottlingOff`, `NetworkThrottlingIndex=255` | Sem efeito mensurável |
| Desativar telemetria (DiagTrack etc.) | Privacidade, não desempenho |
| Limpar temp / cache de update | Espaço em disco, não FPS |
| **UnparkCpu** | Placebo — o log provou os 8 núcleos a 4650 MHz, nenhum estacionado |
| **Mem Reduct** | Contraproducente com 32 GB — descarta cache útil e **causa** stutter |
| **ISLC** (limpar standby list) | Idem — pode forçar releitura de disco |
| Desativar mitigações Spectre/Meltdown | Placebo em AMD Zen 3 para jogos |
| ULPS | Irrelevante (é mecanismo de CrossFire) |
| Low Spec Mode do client | Atua só no launcher, não no jogo |
| Voltar do 24H2 para 23H2 | **Erro** — o 24H2 trouxe o fix de branch prediction que beneficia Zen 3 (+11% médio em 43 jogos) |
| Sites de "FPS boost tweaks" | Reciclam recomendações já aplicadas, sem medição controlada |

---

## O que é perigoso

### Risco de segurança

| Item | Problema |
|---|---|
| **Desativar o UAC** (`EnableLUA=0`) | Rebaixa a segurança do Windows inteiro. No pacote analisado, a função "Reverter" **não religava** |
| `Set-ExecutionPolicy Unrestricted` | Abre o PowerShell para qualquer script |
| `AutoEndTasks=1` + timeouts curtos | Windows mata programas sem avisar — risco de perda de dados |
| `del *.log /s` a partir de `C:\` | Apaga logs de todo o sistema, indiscriminadamente |

### Risco de banimento (Vanguard)

O LoL usa anti-cheat em kernel. Confirmado na investigação:

| Item | Risco |
|---|---|
| **DXVK / trocar DLLs D3D do jogo** | **Ban** — modificação de módulo do cliente. Já disparava o anti-cheat em 2018 |
| **Skin changers com injeção de memória** | **Ban confirmado**, ban waves documentadas |
| **cslol-manager / LTK Manager** | Risco real — usa injeção de DLL; o próprio dev admite gato-e-rato com o Vanguard |
| **Qualquer tentativa de matar o Vanguard** | **Ban de hardware** |
| Overlays que injetam (RTSS, Special-K) | Risco — usar PresentMon (ETW, sem hook) para medir |
| Repos de "FPS boost" sem código-fonte | Malware disfarçado |

**As ferramentas usadas neste projeto não injetam código no processo do jogo:** o
AutoGpuAffinity altera afinidade de dispositivo no registro; o Process Lasso usa APIs oficiais
do Windows de prioridade e afinidade.

---

## Erros cometidos e por que importam

Documentar os erros vale tanto quanto documentar os acertos.

1. **Insistir em throttling térmico** depois que o usuário já havia contestado. O log
   provou que ele estava certo — 50 °C e clock máximo.

2. **Afirmar sem verificar.** Foi dito que o guia do valleyofdoom já cobria essas técnicas
   para LoL. A verificação posterior mostrou que ele **não menciona** LoL, Process Lasso nem
   ProBalance. Uma busca de 30 segundos teria evitado a afirmação.

3. **Sugerir baixar `CharacterQuality`.** É uma opção GPU-side numa máquina com a GPU a 10%.
   O usuário havia baixado de 4 para 1 e perdeu qualidade visual sem ganhar FPS.

O padrão nos três: **conclusão antes da medição**. O método que funcionou foi o inverso.

---

## As três lições principais

### 1. "PC fraco" quase nunca é o diagnóstico

O hardware estava sobrando: GPU a 10%, CPU a 4650 MHz e 50 °C, RAM estável. O que segurava o
FPS era o software de otimização penalizando o jogo.

### 2. Otimizadores podem ser o problema

O Process Lasso — instalado para ganhar desempenho — estava **rebaixando o jogo** via
ProBalance. E o pacote de "otimização" comercial analisado desativava o UAC, com a função de
reverter que não o religava.

### 3. O gargalo define o que faz sentido testar

GPU a 10% e um núcleo lógico a 99% significa que **nenhum** ajuste de GPU, driver ou configuração
gráfica vai mudar o teto. É critério de parada: sabendo disso, para-se de caçar no lugar
errado e ataca-se o que importa — prioridade, afinidade, latência de memória ou, em último
caso, um CPU com mais cache.
