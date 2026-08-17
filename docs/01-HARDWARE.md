# 01 — Hardware e Medições

Tudo que foi verificado na máquina, com o método usado para verificar. Nenhum item aqui é
suposição — cada número foi lido do sistema.

---

## Especificações

| Componente | Modelo | Observações |
|---|---|---|
| **CPU** | AMD Ryzen 7 5700X | 8 núcleos / 16 threads, Zen 3, **sem 3D V-Cache** |
| **GPU** | AMD Radeon RX 9070 XT | RDNA4 — folgada demais para o LoL, e é justamente esse o ponto |
| **RAM** | 2×16 GB = 32 GB | Módulos marca "CUSU", **chip SK Hynix** (P/N `KSD2432U16BKR2032E`), fab. semana 12/2025 |
| **Placa-mãe** | MSI MPG B550 GAMING PLUS (MS-7C56) | Socket AM4 — aceita 5700X3D/5800X3D |
| **Fonte** | MSI 650W | Modelo exato não confirmado |
| **SO** | Windows 11 Pro 25H2, build 26200.9168 | Updates de agosto/2026 |

### Armazenamento

| Disco | Tipo | Uso |
|---|---|---|
| Kingston SNV3S2000G | NVMe SSD | — |
| YSSDHB-2TN7000 | NVMe SSD | **Drive E:** — onde o League of Legends está instalado |
| WDC WD20PURX-64P6ZY0 | HDD SATA | — |

Todos com `HealthStatus: Healthy`. O `YSSDHB-2TN7000` é um NVMe genérico sem DRAM — pode ter
picos de latência sob carga sustentada, mas foi **descartado como causa** dos problemas
investigados.

### Telas

- Monitor 240 Hz @ 1080p — usado para League of Legends
- TV 4K @ 60 Hz — segunda saída da máquina

⚠️ **Nunca foi possível confirmar** se o Windows está de fato em 240 Hz no monitor. Todas as
verificações pegaram a máquina na TV (4K60). **Item pendente** — ver [05-PENDENCIAS.md](05-PENDENCIAS.md).

---

## Estado da memória RAM

Lido via CPU-Z (abas Memory e SPD):

```
Frequência efetiva ...... DDR4-3200 (1600 MHz real)
Timings ................. 16-20-20-40, CR 1T
Voltagem ................ 1.35 V (perfil XMP)
Canais .................. Dual channel (Canal A + Canal B, slots #2 e #4)
Ranks ................... 2 (dual rank)
FCLK .................... 1600 MHz (proporção 1:1 com a memória)
```

**Conclusão:** o XMP está ativo e a memória roda na velocidade nominal. Não está capada.
Como o chip é **SK Hynix**, existe margem real para 3600 MHz com FCLK 1800 — ver
[05-PENDENCIAS.md](05-PENDENCIAS.md).

---

## Verificações de saúde do sistema

Todas realizadas para **eliminar hipóteses**, não para confirmá-las.

| Verificação | Método | Resultado |
|---|---|---|
| Plano de energia | `powercfg /getactivescheme` | **Desempenho Máximo** — não é economia de energia |
| Erros de hardware | Log de eventos, provider `WHEA-Logger`, 14 dias | **Zero eventos** — plataforma eletricamente estável |
| Throttling térmico | Log HWMonitor de partida completa | **Não ocorre** — CPU a 4650 MHz e ~50 °C o tempo todo |
| Memory leak (LoL) | Log HWMonitor, 29 min | **Não existe** — RAM estável em ~16 GB usados |
| Canais de memória | `Win32_PhysicalMemory` → BankLabel | Dual channel confirmado |
| VBS / HVCI | `Win32_DeviceGuard` | **LIGADO** — `SecurityServicesRunning: 2` |
| Vanguard | `Get-Service vgk` | Rodando em kernel (obrigatório no LoL) |
| Otimizações de tela cheia | Registro `AppCompatFlags\Layers` | Já estavam desativadas |
| Tipo de disco | `Get-PhysicalDisk` | NVMe SSD, saudável — teoria de "HDD lento" descartada |

### Nota sobre o HVCI

O **HVCI (Integridade de Memória / Isolamento de Núcleo)** está ativo e é o maior overhead
oculto identificado. Custo medido pela ComputerBase num Ryzen 5800X (mesma arquitetura Zen 3,
teste a 720p para forçar CPU-bound):

- **−6%** de FPS médio
- **+8%** de frametime
- **Pior caso:** −12% de FPS e +30% de frametime

Confirmação independente do Tom's Hardware: média de 5–10% em 15 jogos, com a perda sendo de
CPU/memória (aparece até com RTX 4090).

**Não foi desativado** — é uma proteção real do Windows contra drivers maliciosos, e a
decisão é do usuário. Ver [05-PENDENCIAS.md](05-PENDENCIAS.md).

---

## Histórico relevante

- O problema do LoL **já existia com uma RTX 3090** antes desta 9070 XT.
- O problema **sobreviveu a uma formatação completa**.

Esses dois fatos foram decisivos: eliminaram GPU, driver de vídeo e qualquer software
instalado como causa raiz, e apontaram o diagnóstico para a plataforma (CPU/arquitetura) e
para configurações que voltam ao padrão após formatar.
