# 02 — Caso League of Legends: do diagnóstico ao resultado

**Status: ✅ Resolvido — 90–120 fps com quedas para 60 → 200 fps no jogo normal, 240 cravado em ARAM**

---

## O problema

League of Legends não sustentava 240 fps num monitor de 240 Hz, e o FPS **caía conforme a
partida avançava**. Em teamfights de late game chegava a 110 fps.

Nas gravações das partidas o FPS ficava em **90–120 e caía para ~60 do nada**, no meio do jogo.
Essa instabilidade era o pior da experiência — mais incômoda que o número médio em si, porque
o frametime oscilava. É também o sintoma que aponta para o diagnóstico correto: quando o
problema está nos **vales** e não na média, o gargalo é de saturação momentânea, não de
capacidade bruta.

O que tornava o caso difícil:

- ✅ Hardware muito acima do necessário para o jogo
- ✅ Todas as configurações gráficas já no mínimo
- ✅ **O problema já existia com uma RTX 3090** (antes da 9070 XT)
- ✅ **Sobreviveu a uma formatação completa**
- ✅ Um jogo AAA pesado rodava liso em 4K na mesma máquina, com tudo no máximo

Os dois pontos do meio eliminavam GPU, driver e software instalado. O último parecia eliminar
a máquina inteira — e foi exatamente aí que o diagnóstico se perdeu por um bom tempo. Ver a
seção de erros abaixo.

---

## A evidência decisiva: log de partida completa

Capturado com **HWMonitor**, partida real de **29,6 minutos**, amostras a cada 0,5 s
(3.469 amostras). Análise comparando os primeiros 120 s contra os últimos 120 s:

| Métrica | Início | Fim | Conclusão |
|---|---|---|---|
| **Clock do CPU** | 4650 MHz | 4650 MHz | ❌ **Sem throttling** — boost máximo o tempo todo |
| **Temperatura do CPU** | 50 °C | 50 °C | ❌ **Não é temperatura** |
| **RAM livre** | 16,2 GB | 16,5 GB | ❌ **Sem memory leak** |
| **Uso da GPU** | 7% | 10% | ❌ **GPU ociosa** — não é a placa |
| **Clock da GPU** | 236 MHz | 326 MHz | Praticamente em idle |
| **Uso total do CPU** | 36,5% | **53,6%** | ⚠️ Sobe ao longo da partida |

### O dado que resolveu o caso

Uso de CPU **por núcleo lógico**, nos últimos 120 segundos:

```
#0:59%  #1:45%  #2:74%  #3:87%  #4:28%  #5:28%  #6:65%  #7:65%
#8:32%  #9:31%  #10:54% #11:53% #12:38% #13:37% #14:68%  #15:99%  ← SATURADA
```

**Um único núcleo lógico cravado em 99%**, enquanto a GPU bocejava a 10% e o uso total do
CPU era de apenas 53%.

Análise estendida do log:
- Pelo menos um núcleo acima de **90%** em **3.028 de 3.469 amostras (87% do tempo)**
- Núcleo mais frequentemente saturado: **CPU #15** (2.379 ocorrências), seguido de #3 (692), #2 (242), #14 (156)

**Diagnóstico:** gargalo clássico de engine pouco paralelizada. Conforme a partida avança
(mais campeões, minions, efeitos, pathfinding), a carga cresce até saturar, e o FPS despenca. A
GPU não pode ajudar porque o problema não é dela.

> ### O limite desta medição — onde ela é dado e onde é inferência
>
> O HWMonitor mede uso **por núcleo lógico do sistema**, não por thread de um processo. Então o
> que está **medido** é: um núcleo saturou enquanto a GPU ficou ociosa.
>
> O que é **inferência** é atribuir essa carga à thread principal do LoL. É a explicação mais
> provável — o jogo era o único processo pesado em execução, a Riot confirma a arquitetura
> single-thread, e o padrão bate com o sintoma (piora conforme a partida avança). Mas threads
> migram entre núcleos quando não há afinidade fixada, então "a CPU #15 é a thread do jogo" não
> é algo que este log possa provar.
>
> **Como fechar essa lacuna:** Process Explorer → `League of Legends.exe` → aba *Threads* durante
> uma teamfight, olhando o *Start Address* da thread mais quente. Se apontar para o executável do
> jogo, é lógica do jogo; se apontar para `amdxx64.dll`/`nvlddmkm`, seria driver. **Não foi
> feito** — fica registrado como pendência de método, não como conclusão.

---

## Confirmação externa (investigação com 6 agentes)

Uma investigação paralela varreu Reddit, GitHub, fóruns e benchmarks. **Cinco dos seis agentes
chegaram independentemente à mesma conclusão.**

### Confirmação arquitetural

- A **própria Riot confirmou** que a jogabilidade central roda majoritariamente em **uma thread**
- A simulação de partículas **já roda em thread separada** (post de engenharia "Random Acts of
  Optimization") — não há o que "ligar"
- **Não há renderizador alternativo:** o caminho DX9 foi removido na V14.9; DX11 é o único
- **Não existem flags de linha de comando** de gráficos ou threading para `League of Legends.exe`
- A reescrita do engine ("League Next" / Hextech Engine) está prevista apenas para **2027**

### Baseline realista

| CPU | FPS médio em LoL 1080p low |
|---|---|
| Ryzen 7 5800X | ~315 |
| **Ryzen 7 5700X** (extrapolado, −5~8% de clock) | **~290–305** |
| Ryzen 7 5800X3D | ~397 (+26%) |

Em LoL, o 1% low / teamfight late game fica tipicamente em **45–55% da média** → o esperado
para um 5700X é **~130–170 fps em teamfight**.

**Ou seja: 110–157 fps em teamfight é a faixa normal deste processador.** Não era defeito.

⚠️ *Ressalva de confiabilidade:* as buscas retornaram pouco conteúdo indexado do Reddit. O
baseline vem de agregadores de benchmark (HowManyFPS, TechSpot), não de relatos diretos de
usuários com 5700X. Tratar a faixa 130–170 como **estimativa derivada**.

---

## As soluções aplicadas

### 1. Process Lasso — subiu a média (120 → 200 fps, +66%)

> ⚠️ **Correção de atribuição.** A primeira versão deste documento chamava esta etapa de "o maior
> ganho". Segundo o relato de quem operou a máquina, **o que cravou os 200 fps estáveis foi a
> afinidade do driver gráfico** (etapa 2, abaixo) — esta etapa levantou a **média**, mas o FPS
> continuava oscilando. São efeitos diferentes: um move o número médio, o outro remove a oscilação.
>
> A distinção importa para além desta máquina: a penalidade do ProBalance só existe em quem tem o
> Process Lasso mal configurado — **uma minoria**. A disputa de núcleo entre driver e jogo é o
> comportamento **padrão** do Windows, e portanto atinge praticamente todo mundo. Tratar o caso raro
> como mecanismo principal foi um erro de enquadramento que se propagou para o README.

Três ajustes no processo `League of Legends.exe`:

| Ajuste | Valor |
|---|---|
| Classe de prioridade | **Alta** (Always) |
| Afinidade de CPU | **Apenas núcleos físicos** — `2;4;6;8;10;12;14` |
| ProBalance | **Excluído** |

#### ⚠️ O detalhe crítico: o ProBalance estava sabotando o jogo

O ProBalance é o recurso do Process Lasso que rebaixa automaticamente a prioridade de
processos que consomem muita CPU, para manter o sistema responsivo.

**Como um jogo consome muita CPU por natureza, o ProBalance rebaixava o próprio jogo.**

Sintomas visíveis na interface:
- Coluna *Status*: **"Restringido"**
- Classe de prioridade: **`Alto(a)-`** (com traço no fim)

Definir a prioridade como Alta **não é suficiente** — o ProBalance vence e puxa de volta. É
preciso **excluir explicitamente** o processo.

Isso significa que parte do +66% de média **não foi otimização, foi remoção de uma penalidade que
já estava sendo aplicada**. Guias públicos tratam o ProBalance apenas como recurso positivo;
nenhum consultado avisa deste efeito — o que faz dele um achado que vale documentar, mesmo não
sendo o mecanismo principal do resultado.

#### Onde as regras ficam salvas

`C:\ProgramData\ProcessLasso\config\prolasso.ini`

```ini
[OutOfControlProcessRestraint]
OocExclusions=league of legends.exe

[ProcessDefaults]
DefaultPriorities=league of legends.exe,high
DefaultGPUPriorities=league of legends.exe,4
DefaultAffinitiesEx=league of legends.exe,0,2;4;6;8;10;12;14
```

> As seções não são decorativas: cada chave só vale dentro da sua. E cada uma delas é uma **lista
> de vários processos** separada por vírgula — se você já tem regras para outros programas, elas
> ficam na mesma linha, e sobrescrever a linha apaga tudo. Detalhe em
> [03-COMO-FUNCIONA-O-LOLBOOST.md](03-COMO-FUNCIONA-O-LOLBOOST.md).

**Consequência prática importante:** essas quatro linhas podem ser escritas **antes** do jogo
rodar pela primeira vez — o que torna a configuração automatizável (ver
[03-COMO-FUNCIONA-O-LOLBOOST.md](03-COMO-FUNCIONA-O-LOLBOOST.md)).

> ⚠️ O Process Lasso **precisa estar rodando** para as regras valerem. Se o FPS cair do nada
> um dia, é a primeira coisa a verificar. Confirmado que ele inicia com o Windows via duas
> tarefas agendadas.

---

### 2. Afinidade do driver gráfico

Ferramenta: [AutoGpuAffinity](https://github.com/valleyofdoom/AutoGpuAffinity) (valleyofdoom,
GPL-3.0). Ela fixa o driver de vídeo em cada núcleo, reinicia o driver e mede o frametime.

**Resultado do benchmark nesta máquina** (16 núcleos lógicos, 30 s cada, 1.058.139 frames no
total). Números recalculados a partir dos frametimes brutos do PresentMon, ordenados por 0.1% low
— a planilha completa está em [`exemplo/resultado-nucleos.csv`](../exemplo/resultado-nucleos.csv):

| CPU | Amostras | Média | 1% low | 0.1% low | 0.01% low | Avaliação |
|---|---|---|---|---|---|---|
| **1** | 66.557 | 2219,30 | 1776,83 | **1509,66** | **1276,49** | 🟢 **melhor** |
| 9 | 66.001 | 2200,22 | 1754,69 | 1484,56 | 1142,73 | bom |
| 6 | 66.011 | 2201,11 | 1764,29 | 1473,41 | 1019,16 | bom |
| 4 | 66.651 | 2221,92 | 1774,31 | 1462,20 | 1054,07 | bom |
| 5 | 66.603 | 2221,51 | 1769,60 | 1458,36 | 1112,35 | bom |
| 7 | 66.794 | 2226,28 | 1779,04 | 1454,33 | 1048,66 | bom |
| 11 | 65.333 | 2178,17 | 1749,78 | 1453,91 | 1130,71 | |
| 13 | 66.341 | 2210,03 | 1775,57 | 1452,64 | 1000,80 | |
| 8 | 66.062 | 2202,44 | 1764,60 | 1452,22 | 929,45 | |
| 10 | 66.072 | 2201,89 | 1755,00 | 1450,96 | 1217,43 | |
| 14 | 65.775 | 2192,39 | 1736,11 | 1448,44 | 1194,60 | |
| 3 | 66.236 | 2206,59 | 1717,92 | 1413,43 | 960,15 | |
| 12 | 66.833 | **2228,69** | **1799,53** | 1369,86 | 941,18 | melhor média e 1%, fraco nos vales |
| 2 | 65.447 | 2182,24 | 1686,91 | 1293,33 | 682,45 | fraco |
| 0 | 66.452 | 2214,87 | 1692,05 | 1290,66 | 857,12 | fraco |
| **15** | 64.971 | 2165,76 | 1662,51 | **1189,20** | **448,81** | 🔴 **péssimo** |

> **Por que estes números não batem com os que o AutoGpuAffinity mostra na tela dele:** ele
> calcula 1% low como a *média do 1% pior* dos frames; a tabela acima usa *percentil*. São
> definições diferentes do mesmo nome. **O ranking dos núcleos é o mesmo nas duas contas** — o que
> importa aqui — mas os valores absolutos divergem, e por isso a tabela foi regerada a partir dos
> dados brutos em vez de copiada da tela.

**Interpretação:**

- **Na média não muda nada** — variação de 2,9% entre o melhor e o pior.
- **Nos vales o sinal é forte.** A CPU 15 tem 0.01% low de **448** contra **1276** da CPU 1 —
  quase 3× pior.
- A **CPU 1 ganhou tanto no 0.1% quanto no 0.01% low**, e a CPU 12 mostra por que a média engana:
  é a melhor de todas em média e 1% low, e cai para o quarto pior nos vales.

> ⚠️ **Ressalva estatística que o projeto se cobra:** isto é **uma única passada** de 30 s por
> núcleo. O 0.01% low de ~66 mil frames representa uns 7 frames — a cauda de uma passada só é
> frágil. E "2,9% de variação na média é ruído" é uma leitura razoável, não um teste de
> significância. Vencer em várias colunas **não** é confirmação independente: os percentis vêm da
> mesma amostra e são correlacionados. O jeito certo de fechar isso é rodar 2–3 passadas e ver se
> o ranking se mantém (o AutoGpuAffinity aceita `custom_cpus` para repetir só os candidatos).
> Fica como pendência.

**A coincidência que fecha a história:** no log original, o núcleo saturado em 99% era
justamente a **CPU #15** — o pior núcleo da máquina. Quando o Process Lasso restringiu o jogo
aos núcleos pares, ele saiu de cima da 15. Isso provavelmente explica parte do ganho de +66%.

#### Aplicação

Chave de registro (específica por máquina — o Instance ID do dispositivo é único):

```
HKLM\SYSTEM\CurrentControlSet\Enum\PCI\VEN_1002&DEV_7550&SUBSYS_54171849&REV_C0\
  6&37B354B&0&00000019\Device Parameters\Interrupt Management\Affinity Policy

DevicePolicy          (DWORD)   = 4      ; usar núcleos específicos
AssignmentSetOverride (BINARY)  = 02     ; máscara de bits: CPU 1
```

Máscara de bits por núcleo (hexadecimal):
`CPU0=01 · CPU1=02 · CPU2=04 · CPU3=08 · CPU4=10 · CPU5=20 · CPU6=40 · CPU7=80`

Verificado após reinício: `DevicePolicy = 4`, `AssignmentSetOverride = 2`. ✅

#### O arranjo final de núcleos

A CPU 1 é a irmã SMT da CPU 0 — as duas dividem o **núcleo físico 0**. Por isso a afinidade do
LoL foi ajustada para **remover a CPU 0**:

```
Núcleo físico 0  (CPU 0 + CPU 1)  →  dedicado ao DRIVER GRÁFICO
Núcleos físicos 1–7               →  dedicados ao LOL (CPUs 2;4;6;8;10;12;14)
```

Resultado: o driver de vídeo não interrompe mais a thread principal do jogo no meio do frame.

---

### 3. Ajustes no game.cfg

Arquivo: `E:\Riot Games\League of Legends\Config\game.cfg`
Backups: `game.cfg.bak_pre_tune` e `game.cfg.bak_16ago`

```ini
[General]
EnableReplayApi=0      ; para de gravar o .rofl continuamente (CPU + disco)
ShowGodray=0
HideEyeCandy=1

[Performance]
EnableParticleOptimizations=1   ; adicionado — LOD/culling de partículas
EnableHUDAnimations=0
CharacterQuality=4              ; DEVOLVIDO de 1 para 4 — ver nota
```

> **Nota sobre o `CharacterQuality`:** o usuário havia baixado de 4 para 1 tentando ganhar FPS.
> Essa opção é **GPU-side**, e a GPU está a 10% de uso — ou seja, ele degradou a qualidade
> visual **sem ganhar nada**. Foi devolvido ao valor original.

> **Ressalva honesta:** a chave `EnableParticleOptimizations` veio de um repositório
> comunitário de configs, não é documentada pela Riot. Se não existir mais no engine atual, o
> jogo simplesmente ignora — não quebra nada, mas pode não ter efeito.

> ⚠️ O client reescreve o `game.cfg` ao fechar. **Sempre editar com o jogo e o Riot Client
> completamente fechados.**

---

### 4. GameDVR desativado

`HKCU:\System\GameConfigStore\GameDVR_Enabled = 0`

Elimina o overhead de gravação em segundo plano do Windows.

---

## Resultado final

| Momento | FPS |
|---|---|
| Antes de tudo | ~90–120, **com quedas repentinas para ~60** |
| Após Process Lasso | 200 |
| Após afinidade do driver + game.cfg | **200 no jogo normal · 240 cravado em ARAM** |
| Teamfight late game em Summoner's Rift | ainda o cenário mais pesado |

O ganho que mais se sente não é só o número subir: as **quedas para 60 saíram**. Era o
frametime oscilando por saturação de um núcleo, e é isso que a afinidade resolve.

O ARAM crava 240 por ser um mapa menor, com menos entidades e pathfinding que o Summoner's
Rift em late game.

---

## Erros cometidos durante o diagnóstico

Documentados porque fazem parte do método — e porque o usuário estava certo ao contestá-los.

| Hipótese errada | Por que caiu |
|---|---|
| Throttling térmico do CPU | O log provou: 4650 MHz e 50 °C a partida inteira |
| Memory leak no LoL | RAM estável em 16 GB durante 29 min |
| HDD lento / disco a 100% | O drive é NVMe SSD saudável |
| Shaders corrompidos | O reparo do client já tinha sido feito, sem efeito |
| HAGS | Já estava desativado desde a era da RTX 3090 |
| Fullscreen Optimizations | Já estavam desativadas |
| Regressão do KB5066835 | A máquina está no 25H2 build 26200.9168, updates de ago/2026 |
| "se fosse a máquina, o outro jogo também travaria" | Gargalos opostos — ver a lição de método abaixo |
| "valleyofdoom já documenta isso para LoL" | **Falso** — o guia dele não cita LoL, Process Lasso nem ProBalance |

O último foi uma afirmação feita sem verificação prévia. A verificação posterior mostrou que
o [PC-Tuning](https://github.com/valleyofdoom/PC-Tuning) cobre afinidade de processo apenas de
forma genérica (seção 11.44), sem mencionar o jogo nem as ferramentas citadas.

**A lição de método:** o argumento "se fosse a máquina, apareceria no outro jogo também"
parecia forte, mas era falho — um AAA em 4K é **GPU-bound** e o LoL é **CPU-bound
single-thread**. São gargalos opostos; um teste não prova nada sobre o outro. Só o log por
thread resolveu a questão.
