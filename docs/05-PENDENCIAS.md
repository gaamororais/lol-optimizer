# 05 — Pendências

O que ainda não foi feito, em ordem de impacto, com o ganho esperado de cada item.

---

## 1. Confirmar a taxa do monitor ⚠️ maior ganho potencial, custo zero

**Nunca foi possível verificar** se o Windows está de fato em 240 Hz no monitor. Toda
verificação pegou a máquina na TV (4K @ 60 Hz).

Se o Windows estiver em 60 ou 120 Hz, **nada mais importa** — seria o maior ganho disponível
e o mais fácil de corrigir.

**Como verificar:** Configurações → Sistema → Tela → Configurações de vídeo avançadas → 240 Hz.
Aproveitar para confirmar o FreeSync ativo.

---

## 2. HVCI / Integridade de Memória — decisão do usuário

**Status atual: LIGADO** (`VirtualizationBasedSecurityStatus: 2`, `SecurityServicesRunning: 2`)

### Ganho esperado

Medição da ComputerBase num Ryzen 5800X (mesma arquitetura Zen 3), teste a 720p para forçar
CPU-bound:

| Métrica | Impacto |
|---|---|
| FPS médio | **−6%** |
| Frametime | **+8%** |
| Pior caso (Diablo 2 Resurrected) | −12% de FPS, +30% de frametime |

Confirmação independente do Tom's Hardware: 5–10% em 15 jogos.

Aplicado à faixa atual de teamfight (110–157 fps): estimativa de **+7 a +18 fps nos vales**.

### Como fazer

Configurações → Privacidade e segurança → Segurança do Windows → Segurança do dispositivo →
Isolamento de núcleo → **Integridade de memória = Desligado** → **reiniciar**.

Confirmar de fato no `msinfo32`: "Segurança baseada em virtualização" deve dizer
**"Não habilitada"**.

### ⚠️ Contradição não resolvida

Dois agentes da investigação discordaram:
- Um afirmou que o Vanguard **exige** HVCI e o jogo não abriria
- Outro (com fonte melhor — Tom's Hardware sobre o Vanguard On-Demand) afirmou que desligar
  HVCI apenas tira o modo On-Demand, e o Vanguard volta ao modo always-on normalmente

**Resolução empírica:** desligar, reiniciar, tentar abrir o LoL. Se der erro VAN, religar.

### Ban não é o risco aqui

**Não há risco de banimento.** HVCI é uma configuração do **próprio Windows**, alterada pela
interface do sistema (ou pelo registro). Você não está modificando arquivo do jogo, não está
injetando código, e não está mexendo no Vanguard. Anti-cheat bane por manipulação do jogo ou do
próprio anti-cheat — não por configuração de sistema operacional que a Microsoft te dá um botão
para mudar.

**O risco real é o jogo não abrir**, o que é diferente e reversível em 2 minutos: religa e
reinicia. A dúvida que fica em aberto é só essa — se abre ou não — e a única forma de resolver é
testar.

> ⚠️ **Não confundir HVCI com Secure Boot e TPM 2.0.** Esses dois **são** exigência do Vanguard
> para o jogo iniciar no Windows 11, e desligá-los trava o acesso. HVCI (Integridade de Memória /
> Isolamento de Núcleo) é outra coisa, e desligar HVCI **não** desliga Secure Boot. Se você for
> mexer, mexa só no HVCI.

> Este item é uma **troca de segurança por desempenho**. O HVCI protege contra drivers
> maliciosos. Por isso não foi aplicado automaticamente nem incluído no script.

---

## 3. Tuning de RAM: DDR4-3600 + FCLK 1800

**Ganho esperado: +10 a 15%**, com melhora proporcionalmente maior nos 1% lows.

Guia completo, passo a passo de BIOS, em
[`exemplo/Tuning_RAM_e_PBO_MSI_B550.txt`](../exemplo/Tuning_RAM_e_PBO_MSI_B550.txt).

### Por que 3600 se a memória é 3200

O XMP-3200 é o perfil que o **montador do módulo** testou e garantiu — não é o limite físico
do chip. O chip real é **SK Hynix** (confirmado no CPU-Z), que na prática costuma alcançar
3600+. Fabricantes de kits baratos binam baixo porque testar é caro.

Além disso, **3600 com FCLK 1800 é o sweet spot do Ryzen 5000** — mantém a proporção 1:1 entre
a memória e o Infinity Fabric.

### Etapa 1 — frequência

BIOS → F7 (Advanced) → menu OC → OC Explore Mode = EXPERT

```
DRAM Frequency ....... DDR4-3600
FCLK Frequency ....... 1800 MHz      ← crítico, mantém 1:1
DRAM Voltage ......... 1.40 V
Command Rate ......... 1T (2T se não bootar)
Timings primários .... Auto (nesta etapa)

Tensões de suporte (dual rank + FCLK 1800):
SOC Voltage .......... 1.05 – 1.10 V
VDDG CCD ............. 950 mV
VDDG IOD ............. 950 – 1000 mV
```

Validar: **ZenTimings** (MCLK 1800 / FCLK 1800 / 1:1) + **TestMem5** perfil "Extreme @anta777",
1 ciclo, 0 erros.

### Etapa 2 — timings (só com a Etapa 1 estável)

```
Alvo A ...... tCL 16 / tRCD 19 / tRP 19 / tRAS 38 / tRC 58
Alvo B ...... tCL 16 / tRCD 20 / tRP 20 / tRAS 40 / tRC 60   (se o A falhar)
tRFC ........ 480      ← NÃO usar 416 (agressivo demais para Hynix CJR/DJR)
DRAM ........ 1.42 V
```

Chips Hynix CJR/DJR escalam bem em frequência mas **não aceitam `tRCD` apertado** — 19 é
realista, 16 não é.

### Plano B

Se 3600 não estabilizar: manter DDR4-3200 / FCLK 1600 e apertar os timings
(`16-18-18-36`, tRC 54, tRFC 480, 1.40 V). Ganha menos, mas ganha.

### Medição

AIDA64 → Cache & Memory Benchmark, anotando a **Latency em ns** antes e depois.
Esperado: de ~68–72 ns para ~60–63 ns.

---

## 4. PBO + Curve Optimizer

**Ganho esperado: pequeno.** O log mostra o CPU já quase sempre em 4650 MHz, sem throttling
térmico nem de potência — não há headroom de frequência livre. Ajuda mais a suavizar picos
que a elevar o teto.

```
BIOS → OC → AMD Overclocking → Precision Boost Overdrive
  Precision Boost Overdrive ..... Advanced
  PBO Limits .................... Motherboard
  Max CPU Boost Clock Override .. +100 MHz
  Curve Optimizer ............... All Cores / Negative / Magnitude 20
```

Validar com OCCT (CPU, Extreme, 30 min). Crash em idle ou carga leve → baixar a magnitude
(20 → 15).

---

## 5. Estender a exclusão do ProBalance a outros jogos

**Estado atual do `prolasso.ini`:**

```ini
OocExclusions=league of legends.exe
```

**Apenas o LoL está excluído.** Todos os outros jogos da máquina continuam sujeitos a serem
rebaixados pelo ProBalance, exatamente como o LoL estava.

Como remover essa penalidade levantou a média no LoL, é
provável que haja FPS preso nos demais jogos.

**Também notado:** `GamingModeEnabled=false` — o Gaming Mode do Process Lasso, que suspende o
ProBalance automaticamente durante jogos, está desligado.

### Como fazer

Pela interface (não requer editar arquivo): com o jogo aberto, localizar o processo no
Process Lasso → **botão direito → Excluir do ProBalance**. Fica salvo permanentemente.

> A edição direta do `prolasso.ini` exige admin — o `ProcessGovernor` roda como SYSTEM e
> mantém o arquivo bloqueado.

---

## 6. Upgrade de CPU — a solução definitiva para o LoL

Único caminho que muda o patamar em teamfight de late game.

| Opção | Observação |
|---|---|
| **5700X3D** | Melhor custo-benefício — entrega ~95% do 5800X3D |
| **5800X3D** | Referência (+26% de FPS médio em LoL sobre o 5800X) |

**Estimativa:** teamfights de 110–157 fps passariam para **~150–210 fps**.

**Vantagens:** drop-in no socket AM4, mantém a placa MSI B550, a RAM, a GPU e a fonte.

⚠️ **Atualizar a BIOS da B550 antes da troca** (requer AGESA 1.2.0.7+).

❌ **Não trocar por 5900X ou 5950X.** Mais núcleos não resolvem gargalo single-thread — o
ganho seria praticamente zero. Só o cache 3D importa aqui.

---

## Resumo priorizado

| # | Item | Custo | Ganho estimado |
|---|---|---|---|
| 1 | Confirmar 240 Hz no monitor | Zero | Potencialmente enorme |
| 2 | Estender ProBalance a outros jogos | 20 s por jogo | Desconhecido, possivelmente alto |
| 3 | HVCI desligado | Reiniciar + decisão de segurança | +6 a 12% |
| 4 | RAM 3600 + FCLK 1800 | Uma tarde + testes | +10 a 15% |
| 5 | PBO / Curve Optimizer | 1 h com testes | Pequeno |
| 6 | 5700X3D | Custo de hardware | +30 a 50% no LoL |
