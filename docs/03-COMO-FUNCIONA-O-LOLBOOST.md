# 03 — LoLBoost: documentação técnica

Ferramenta que automatiza o processo descrito em [02-CASO-LOL.md](02-CASO-LOL.md).

```
LoLBoost/
├── LoLBoost.bat        ← ponto de entrada (auto-eleva para admin)
├── LoLBoost.ps1        ← script principal
├── DESFAZER.ps1        ← gerado na execução, reverte tudo (regravado a cada alteração)
└── LoLBoost.log        ← gerado na execução
```

Instruções de uso ficam no [README da raiz](../README.md).

---

## Princípios de projeto

Quatro regras que definiram o que o script faz e o que ele se recusa a fazer.

### 1. Medir, nunca assumir

O melhor núcleo para o driver gráfico **varia por máquina**. O script roda o benchmark, lê os
frametimes brutos e calcula — não copia o resultado de outra pessoa.

### 2. Nunca mexer em segurança automaticamente

**HVCI, UAC e Secure Boot ficam de fora.** O script apenas **detecta e informa**. Desativar
proteção do sistema operacional é decisão consciente de quem usa a máquina, não efeito
colateral de um script de FPS.

Isso é o oposto do que fazem os "otimizadores" distribuídos por aí — o pacote analisado neste
projeto desativava o UAC (`EnableLUA=0`) e, pior, **a função de reverter não o religava**.

### 3. Tudo reversível

Todo arquivo alterado ganha backup. Toda mudança de registro entra numa lista que gera o
`DESFAZER.ps1` — e ele é **regravado a cada alteração**, não no fim. Com
`$ErrorActionPreference = 'Stop'`, qualquer falha no meio abortaria o script depois de já ter
mexido no registro, no plano de energia e no `game.cfg`; gerar o arquivo só no fim significaria
deixar a máquina alterada **sem reversão**.

### 4. Reversível **mesmo rodando duas vezes**

Esta é a parte que quebrou primeiro e não é óbvia. Rodar o script duas vezes fazia ele capturar
como "valor anterior" o que **ele mesmo** tinha escrito na primeira rodada: o GameDVR lia 0, o
plano lia Alto Desempenho, a afinidade lia a que ele gravou. O DESFAZER então "restaurava" o
estado já modificado — e reportava sucesso. Os arquivos editados escapavam porque o backup só é
criado se ainda não existir; os valores de registro não tinham proteção equivalente.

Duas defesas:

- **`LoLBoost.original.json`**, com os valores originais, escrito **uma única vez**. Ele fica em
  `%LOCALAPPDATA%\LoLBoost` e **não** na pasta do script, de propósito: se morasse junto, quem
  apaga a pasta e baixa de novo perderia o registro — e a execução seguinte voltaria a capturar
  como "original" o que a primeira já tinha modificado, em silêncio. No `%LOCALAPPDATA%` ele
  também é o mesmo arquivo se a pessoa rodar pelo ZIP numa vez e por `irm | iex` na outra.
- **O DESFAZER não encolhe.** Se uma etapa foi aplicada numa rodada anterior e é pulada nesta (o
  LoL estava aberto, ou a pessoa respondeu N no Process Lasso), a linha de restauração daquela
  etapa continua sendo escrita — a alteração segue aplicada na máquina, então o undo precisa
  cobri-la. A existência do `.bak` é o que sinaliza isso.

---

## Fluxo de execução

### Etapa 1 — Detecção de hardware

```powershell
function EhCpuHibrida($nome, $cores, $threads) {
    $smt       = ($threads -eq $cores * 2)
    $intelNova = ([string]$nome -match '1[2-9]th Gen|Core\(TM\)\s*Ultra|Core\s*Ultra')
    return ((-not $smt) -and ($threads -ne $cores)) -or $intelNova
}
```

**A detecção de CPU híbrida é a proteção mais importante do script.** Copiar a máscara
`2;4;6;8;10;12;14` numa CPU híbrida pode prender o jogo nos **E-cores** (os lentos) e **derrubar
o FPS pela metade**.

A primeira parte da conta pega o caso comum: num i5-12600K (6P + 4E = 10 núcleos, 16 threads),
`2 × 10 = 20 ≠ 16` → híbrido, porque os E-cores não têm Hyper-Threading.

**Mas essa conta sozinha tem um furo grave:** ela não pega híbrida **sem** Hyper-Threading. Um
Core Ultra 9 285K é **24C/24T** (8P + 16E) — threads **igual** a núcleos, então passaria como CPU
uniforme e a afinidade seria aplicada, podendo prender o jogo nos E-cores. O mesmo vale para
qualquer 12ª–14ª geração com HT desligado na BIOS.

Daí o segundo termo: **Intel de 12ª geração em diante entra na guarda por precaução.** Separar
P-core de E-core de verdade exigiria `GetSystemCpuSetInformation` (está no roadmap). Sem isso, o
script erra para o lado seguro — numa 12ª geração sem E-cores (um i3-12100) ele deixa de aplicar
algo que funcionaria: você deixa de ganhar, mas não perde.

**A afinidade é a única parte pulada.** Prioridade Alta e exclusão do ProBalance continuam sendo
aplicadas — não dependem de afinidade. (Antes, CPU
híbrida pulava a etapa 5 inteira e jogava as duas fora.)

> No caso do i5-10400F (10ª geração, 6C/12T, não híbrido), o layout é uniforme e a regra dos
> pares se aplica normalmente: núcleos físicos = CPUs 0, 2, 4, 6, 8, 10.

> ⚠️ **Limitação conhecida — híbridas AMD.** Os núcleos compactos da AMD (Zen 4c / Zen 5c, como
> no Ryzen 5 8540U e na linha Ryzen AI) **têm** SMT, então `threads = 2 × núcleos` e eles passam
> como uniformes: a afinidade é aplicada sobre os c-cores. O dano é menor que no caso Intel (mesma
> arquitetura e IPC, só clock menor, ao contrário dos E-cores que são outra microarquitetura), mas
> não é ideal. **Não coberto** — fica registrado.

### Etapa 2 — Ajustes seguros

| Ação | Reversível via |
|---|---|
| GameDVR desativado (HKCU + política HKLM) | valor anterior salvo |
| Plano de energia → Alto Desempenho | GUID do plano anterior salvo |
| `game.cfg` ajustado | backup `.LoLBoost.bak` |

O `game.cfg` é localizado **varrendo todos os drives** — não assume `C:`, porque nesta máquina
ele está em `E:`:

```powershell
foreach ($d in (Get-PSDrive -PSProvider FileSystem).Name) {
    $p = "${d}:\Riot Games\League of Legends\Config\game.cfg"
    if (Test-Path $p) { $cfg = $p; break }
}
```

O script **aborta esta etapa** se detectar qualquer processo da Riot rodando — o client
sobrescreveria a edição ao fechar.

### Etapa 3 — Separar o driver do núcleo do jogo

**Esta etapa foi reescrita depois de dois incidentes em campo.** Ver
[a seção sobre eles](#o-que-dois-incidentes-em-campo-mudaram) no fim deste documento.

A separação em duas coisas distintas é a mudança mais importante do projeto até agora:

| | O que é | Risco |
|---|---|---|
| **Separar** | Escrever no registro em qual núcleo o driver de vídeo deve rodar. **Não reinicia driver nenhum** — só passa a valer no boot seguinte | Nenhum |
| **Medir** | Descobrir qual núcleo é o melhor. Exige **reiniciar o driver uma vez por núcleo** | Tela preta se o driver não voltar |

Antes as duas estavam amarradas numa pergunta sim/não. Quem recusava o benchmark — a escolha
sensata em máquina que não pode ficar fora do ar — perdia **também** a separação, que é de onde
vem o ganho principal. Era o pior enquadramento possível: o risco e o benefício no mesmo botão.

Agora são três opções, e a **segura é a recomendada e o default** de resposta não reconhecida:

```
[1] SEPARAR SEM MEDIR  - recomendado. Sem risco, a tela nao pisca.
[2] MEDIR E SEPARAR    - o ideal, se voce topa o risco.
[3] NAO FAZER NADA AQUI
```

Na opção 1 o driver vai para a CPU 1 (ou 0 sem SMT) e o jogo sai de cima dela. O script diz na
tela que **não sabe** se aquele é o melhor núcleo da máquina — para isso só medindo — mas que ele
deixa de disputar com o jogo, que é o que resolve.

#### Quando a opção 2 é escolhida

Baixa o AutoGpuAffinity direto da **API oficial de releases do GitHub** (não de mirror), roda
o benchmark e analisa os resultados.

O AutoGpuAffinity salva frametimes brutos do PresentMon em
`captures/<sessão>/CSVs/CPU-N.csv`. A coluna relevante é `msBetweenPresents`.

```powershell
$ft = Import-Csv $csv | ForEach-Object { [double]$_.msBetweenPresents } |
      Where-Object { $_ -gt 0 } | Sort-Object

$p99  = $ft[[int][Math]::Floor($ft.Count * 0.99)]    # 1% piores frames
$p999 = $ft[[int][Math]::Floor($ft.Count * 0.999)]   # 0.1% piores frames

Low1  = 1000 / $p99     # FPS equivalente
Low01 = 1000 / $p999
```

**Critério de ranking:** ordena por **0.1% low** (consistência) e desempata pelo **1% low**.

A média é deliberadamente ignorada como critério — no caso real ela variou apenas 2,9% entre
o melhor e o pior núcleo, o que é ruído estatístico.

#### Recuperação automática de driver travado

Duas camadas, porque uma sozinha não cobre o pior caso.

**Camada 1 — vigia por progresso durante a medição.** O AutoGpuAffinity grava um CSV por núcleo
testado. Se esses arquivos param de aparecer, ele empacou — quase sempre porque o driver de vídeo
travou. O gatilho é **150 s sem nenhum progresso** (com 90 s de carência inicial, porque o primeiro
CSV demora), mais um limite total de `threads × 60 + 300` segundos como rede.

Vigiar progresso é melhor que vigiar tempo total: detecta em ~2 minutos em vez de esperar os 17
minutos do limite. Quando dispara:

1. Consulta o **evento 4101** do log do Windows (*"o driver de vídeo parou de responder"*) desde o
   início da medição, e informa se foi isso mesmo ou se apenas parou de progredir
2. Encerra o AutoGpuAffinity
3. **Limpa a configuração que ele deixou na placa**
4. Tenta trazer o vídeo de volta com `pnputil /restart-device`
5. Reporta o `Status` dos dispositivos de vídeo depois da tentativa
6. **Segue pelo caminho seguro** (separar sem medir), em vez de abortar

**Camada 2 — marcador em disco.** Se o driver travar de um jeito que impeça qualquer recuperação, a
camada 1 morre junto com a sessão: não existe software que sobreviva a um desligamento no botão. Por
isso o script grava `medicao-em-andamento.txt` em `%LOCALAPPDATA%\LoLBoost` **antes** de medir e o
apaga quando termina.

Se esse arquivo existir na execução seguinte, a medição anterior não terminou. O script então
**limpa a placa automaticamente, sem perguntar nada**, e explica o que aconteceu e por quê.

É a camada 2 que resolve o caso real: numa máquina de teste o driver travou, o PC foi desligado no
botão, e a placa ficou presa num núcleo **sem ninguém saber** — só foi descoberto porque alguém
pensou em conferir. Agora a própria ferramenta detecta e conserta na próxima abertura.

> **Por que `pnputil /restart-device` e não `Restart-PnpDevice`:** o cmdlet `Restart-PnpDevice`
> **não existe no Windows 10** (verificado: ausente no build 19045). O `pnputil` existe do Windows 10
> 1903 em diante e no 11. Se essa parte tivesse sido escrita testando só em Windows 11, a recuperação
> automática falharia exatamente na máquina onde ela precisa funcionar.

### Etapa 4 — Colocar o driver de vídeo no núcleo escolhido

Descobre o Instance ID do dispositivo **daquela máquina** e monta a máscara de bits:

```powershell
function MascaraAfinidade($core) {
    $mask  = [uint64]1 -shl $core
    $bytes = [BitConverter]::GetBytes($mask)
    $len   = [Math]::Max(1, ([Math]::Floor($core / 8) + 1))
    return [byte[]]($bytes[0..($len-1)])
}

Set-ItemProperty -Path $k -Name DevicePolicy          -Value 4 -Type DWord
Set-ItemProperty -Path $k -Name AssignmentSetOverride -Value (MascaraAfinidade $melhorCore) -Type Binary
```

O comprimento variável (`$len`) importa: para núcleos acima de 7 a máscara precisa de mais de um
byte — CPU 15 vira `00 80`, CPU 23 vira `00 00 80` (little-endian). Coberto por teste.

> **Não usa `New-Item -Path $k -Force`.** Numa chave de registro que **já existe**, esse comando
> recria a chave e **apaga valores e subchaves** (testado). Quem já tinha afinidade de driver
> configurada — por já ter rodado o AutoGpuAffinity, por exemplo — perderia a configuração sem
> backup. O script cria a chave só se ela não existir, guarda `DevicePolicy` e
> `AssignmentSetOverride` anteriores, e o DESFAZER **restaura os valores** em vez de remover a
> chave.

### Etapa 5 — Process Lasso

Calcula a afinidade do jogo **excluindo o núcleo físico que ficou com o driver**:

```powershell
$coreDriverFisico = [math]::Floor($melhorCore / $(if ($smt) {2} else {1}))

for ($f = 0; $f -lt $cores; $f++) {
    if ($f -eq $coreDriverFisico) { continue }   # reservado ao driver
    $lista += ($f * $passo)
}
```

Exemplo no i5-10400F (6C/12T) com driver na CPU 1 (núcleo físico 0):
→ afinidade do LoL = `2;4;6;8;10`

Depois escreve diretamente no `prolasso.ini` — **o jogo não precisa nunca ter rodado**:

```ini
[OutOfControlProcessRestraint]
OocExclusions=league of legends.exe

[ProcessDefaults]
DefaultPriorities=league of legends.exe,high
DefaultGPUPriorities=league of legends.exe,4
DefaultAffinitiesEx=league of legends.exe,0,<afinidade calculada>
```

> As **seções importam**. A [documentação da Bitsum](https://bitsum.com/processlasso-docs/ini-config-file/)
> coloca `OocExclusions` em `[OutOfControlProcessRestraint]` e as `Default*` em `[ProcessDefaults]`.
> A primeira versão desta função acrescentava a chave no **fim do arquivo** quando ela não
> existia — o que jogaria a chave na seção errada. A escrita agora é ciente de seção.

#### Mesclar, nunca sobrescrever a linha

A mesma documentação define essas chaves como **uma lista separada por vírgula**, com um número
fixo de campos por processo:

| Chave | Campos por processo | Exemplo |
|---|---|---|
| `OocExclusions` | 1 | `notepad.exe,calc.exe` |
| `DefaultPriorities` | 2 | `obs64.exe,high,chrome.exe,below normal` |
| `DefaultGPUPriorities` | 2 | `jogo.exe,4` |
| `DefaultAffinitiesEx` | 3 | `jogo.exe,0,2;4;6` (a máscara usa `;` por isso) |

A versão anterior **substituía a linha inteira** — apagando, sem avisar, todas as regras que a
pessoa tivesse para outros programas. E isso pegaria em cheio exatamente quem o README chama pelo
nome: *"se você instalou o Process Lasso achando que ia ganhar FPS"*. Quem tem regras próprias é
quem mais tinha a perder.

Agora o script lê o valor atual, **remove só as entradas do `league of legends.exe`** (usando a
aridade certa de cada chave), **preserva todo o resto** e acrescenta as novas — e informa na tela
quantas regras suas foram mantidas.

#### Os testes

As afirmações acima são cobertas por [`testes/testar.ps1`](../testes/testar.ps1) — **79 casos**:

```bash
powershell -ExecutionPolicy Bypass -File testes/testar.ps1
```

Os testes **extraem as funções do `LoLBoost.ps1` publicado usando o parser do PowerShell (AST)** e
as executam de verdade — não são reimplementações paralelas, que poderiam continuar verdes depois
de o script mudar. Foi por isso que `GuidDoPlano`, `MascaraAfinidade` e `EhCpuHibrida` existem como
função em vez de expressões inline. Nada na máquina é alterado: tudo roda em memória ou em arquivo
temporário.

| Grupo | O que cobre |
|---|---|
| A | escrita ciente de seção: chave presente, ausente, seção ausente, seção no fim, **seções duplicadas** como no arquivo real, chave com espaços em volta do `=` |
| B | mesclagem preservando regras nas três aridades, substituição da nossa regra antiga, lista **malformada** sem perder dado do usuário, nome em maiúscula |
| C | leitura de valor na seção certa, incluindo chave na segunda seção duplicada e não-vazamento entre seções |
| D | máscara de bits da afinidade, inclusive acima de 8 e 16 núcleos |
| E | detecção de híbrida: uniforme AMD/Intel antigo, 12ª gen, Core Ultra 24C/24T, HT desligado, Xeon sem HT |
| F | GUID do plano de energia em pt-BR, en-US, es-ES, maiúscula e saída sem GUID |
| G | encoding: ida e volta em UTF-8 sem BOM, com BOM e ANSI, sem corromper acento nem inventar BOM |
| H | estado original entre execuções: não recaptura valor já modificado, lembra \
ull\ e \alse\ corretamente, sobrevive a recarregar do disco, e degrada como primeira execução se o JSON corromper |

#### O que a medição num Process Lasso recém-instalado mostrou

Aqui vale registrar a diferença entre o risco **presumido** e o risco **medido**, porque este
projeto se propõe a medir em vez de supor — e a primeira leitura estava errada.

Presumia-se que, numa instalação nova, as chaves não existiriam e a escrita cega de seção
falharia em silêncio. **Instalação nova, arquivo real inspecionado:** o `prolasso.ini` já nasce
com **180 linhas** e as quatro chaves **já presentes e vazias**:

```ini
[OutOfControlProcessRestraint]        # linha 4
OocExclusions=                        # linha 33

[ProcessDefaults]                     # linha 131
DefaultPriorities=                    # linha 133
DefaultGPUPriorities=                 # linha 135
DefaultAffinitiesEx=                  # linha 139
```

Ou seja: o caminho de código exercitado é sempre o de **substituir**, não o de acrescentar. A
escrita cega de seção não quebraria na prática. A correção continua valendo como defesa (e
porque estava conceitualmente errada), mas **não era o resgate crítico que parecia**.

Um detalhe que só apareceu no arquivo real: ele tem **seções duplicadas** — dois
`[ProcessDefaults]`, dois `[Performance]`, dois `[ProcessAllowances]`. A escrita ciente de seção
foi validada contra esse arquivo de 180 linhas: resultado com **180 linhas** (nada duplicado),
exatamente **4 linhas trocadas**, cada uma na seção correta.

#### O caminho do arquivo

A Bitsum documenta que o `prolasso.ini` é gerado *"per-user in the ProcessLasso subfolder of each
user's application data directory"* e que o administrador pode redefinir o caminho na instalação.

Na prática, **numa instalação padrão o arquivo fica em
`C:\ProgramData\ProcessLasso\config\prolasso.ini`** — exatamente o caminho que estava hardcodado.
A busca dinâmica que substituiu o valor fixo é defesa contra instalação com caminho customizado,
não correção de uma falha do caso comum. O script tenta os caminhos conhecidos, cai para busca
recursiva se não achar, e **imprime qual arquivo está usando**.

> **Detalhe de implementação:** é preciso encerrar o `ProcessGovernor` e o `ProcessLasso`
> antes de escrever, senão o serviço sobrescreve o arquivo ao sair. O serviço roda como
> **SYSTEM**, então isso exige privilégios de administrador.

#### A armadilha da instalação nova

O `prolasso.ini` **não nasce com o instalador** — quem cria é o próprio Process Lasso na
primeira execução. Numa instalação feita agora, o arquivo pode não existir ainda quando o
script chega na hora de escrever.

A primeira versão do script fazia `Start-Sleep 8` e seguia para um `if (Test-Path $plIni)`. Se
o arquivo não tivesse aparecido nesses 8 segundos, **a configuração inteira era pulada em
silêncio** — sem erro, sem aviso. O usuário
terminaria a execução achando que estava configurado.

Corrigido: o script espera até 60 s pelo arquivo, abre o Process Lasso uma vez no meio do
caminho para forçar a criação, e **se ainda assim não aparecer, avisa em vermelho** o que
faltou e manda rodar de novo (na segunda vez ele pula o download e vai direto configurar).

> O `DESFAZER.ps1` restaura o `prolasso.ini`, mas **não desinstala** o Process Lasso. Quando o
> script foi quem instalou, o DESFAZER passa a dizer isso explicitamente — prometer "reverte
> tudo" e deixar um programa instalado seria mentira.

### Etapa 6 — Gerar o DESFAZER

Toda ação reversível foi acumulada numa lista durante a execução. O script escreve um
`DESFAZER.ps1` autocontido, que já verifica se está rodando como admin.

---

## O que dois incidentes em campo mudaram

O projeto passou por três rodadas de revisão adversarial antes de ser publicado, e foi liberado com
veredito de "pode divulgar". Na **primeira máquina de teste real** — um i5-10400F com RTX 3060 no
Windows 10 — deu dois problemas seguidos. Vale registrar porque nenhum dos dois era desconhecido, e
os dois estavam em pontos que eu considerava testados.

### Incidente 1 — o driver de vídeo travou na primeira troca de núcleo

Tela preta, PC ligado, dono sem saber o que fazer. O risco estava documentado no README e o autor da
ferramenta de terceiro avisa dele. Mas duas coisas **não** estavam previstas:

1. **A placa ficou presa num núcleo.** O benchmark fixa o driver em cada núcleo para testar e
   restaura no fim; morrendo no meio, ele deixa a última configuração aplicada. E o `DESFAZER` **não
   cobria isso**, porque quem escreveu no registro foi a ferramenta de terceiro, não o script. Foi
   preciso um comando manual para descobrir e limpar. → Corrigido: a limpeza entrou no undo,
   registrada **antes** de a medição começar, e existe recuperação automática nas duas camadas
   descritas na Etapa 3.
2. **O aviso chegava tarde.** O texto dizia "se travar, reinicie o PC" — mas a pessoa lê isso
   **antes**, esquece, e quando precisa está de frente para uma tela preta. → Corrigido: o aviso
   agora **ensina o resgate** (`Win`+`Ctrl`+`Shift`+`B`, trocar o cabo de porta, e por último o
   power de 10 s) na tela, antes de começar, como passo numerado.

O aprendizado de enquadramento é o maior: o risco e o benefício estavam **no mesmo botão**. Separar
"medir" de "separar" fez o risco virar opcional, e o benefício principal continuar acessível a quem
não quer correr risco nenhum.

### Incidente 2 — o script travou para sempre em "Instalando..."

`Start-Process $inst -ArgumentList '/S' -Wait`. O instalador do Process Lasso em modo silencioso não
encerra de forma confiável: o programa instalou (aparecia no menu Iniciar) e o script ficou parado
indefinidamente esperando o processo sair.

**E eu tinha testado essa etapa.** Mas o teste que escrevi usava `Start-Process` **sem** `-Wait`, com
verificação por tempo — justamente para medir se a flag `/S` era silenciosa. O código publicado usava
`-Wait`. Ou seja: **o teste exercitou um caminho diferente do que o código fazia, e passou verde
enquanto o código real travava.**

→ Corrigido: o script espera pelo **resultado** (o executável aparecer em disco, com limite de 2 min)
em vez de confiar no encerramento do instalador. E não sobrou nenhum `-Wait` sem limite no script — o
do próprio benchmark também ganhou vigia, porque ele tinha o mesmo defeito latente.

### A lição que vale mais que as duas correções

É a mesma que a segunda revisão já havia apontado dentro dos testes automatizados — testes que
exercitavam reimplementações locais em vez das funções publicadas, e por isso continuariam verdes se
o script mudasse. Eu corrigi aquele caso e **cometi o mesmo erro no teste manual**, duas vezes.

**Teste que não roda o código real não é teste, é ensaio.** Vale para o arquivo de testes e vale para
o comando que se digita no PowerShell para "conferir se funciona".

---

## Limitações conhecidas

| Limitação | Situação |
|---|---|
| CPUs híbridas | Detectadas, mas a divisão de núcleos é pulada — exige trabalho manual |
| Híbridas AMD (Zen 4c/5c) | **Não** detectadas: têm SMT, então passam como uniformes |
| Benchmark GPU-bound | O AutoGpuAffinity usa liblava (Vulkan), não o LoL. Serve para **ranquear** núcleos, mas o valor absoluto não representa o jogo |
| Opção "separar sem medir" | Garante a separação, **não** a escolha ótima do núcleo |
| `EnableParticleOptimizations` | Chave não documentada pela Riot; pode ser ignorada pelo engine atual |
| Reinício do driver | Risco **confirmado em campo**, não apenas teórico. Mitigado pela recuperação em duas camadas, mas não eliminado |
| Process Lasso | Precisa continuar rodando para as regras valerem |
| Teste ponta a ponta | Nenhuma execução completou as 6 etapas ainda. Componentes validados individualmente |

---

## Roadmap sugerido

- [ ] Suporte real a CPUs híbridas (detectar P-cores via `GetSystemCpuSetInformation`)
- [ ] Modo "somente medir", sem aplicar nada
- [ ] Aplicar a exclusão do ProBalance a **outros jogos**, não só ao LoL
- [ ] Coleta opcional de antes/depois para validar o ganho de verdade
- [ ] Internacionalização (o script está em português)
- [ ] Medir os núcleos **sem reiniciar o driver** — se existir caminho técnico para isso, elimina o
      único risco relevante que sobrou no projeto

---

## Posicionamento honesto do projeto

**O que não é inédito:** afinidade de processo, afinidade de driver gráfico e uso do Process
Lasso para jogos são técnicas conhecidas e documentadas separadamente. O AutoGpuAffinity
existe exatamente para a segunda.

**O que não foi encontrado documentado:**
1. A combinação das três técnicas **aplicada especificamente ao LoL**, com medição
2. **O alerta sobre o ProBalance rebaixar o próprio jogo** — os guias públicos consultados
   tratam o recurso apenas como benéfico
3. Uma ferramenta que **automatize e meça** em vez de mandar copiar valores

**O gancho mais forte e mais defensável:** *"se você instalou o Process Lasso achando que ia
ganhar FPS, ele pode estar te fazendo perder"*. É específico, verificável na própria interface
(coluna Status = "Restringido") e contraria o senso comum.

⚠️ **Não anunciar o ganho desta máquina como resultado esperado, e não chamar a máquina de "mal
configurada".** Ela não estava — rodava AAA em 4K no ultra sem engasgar. O que existia era uma
**penalidade específica sobre o LoL**: o ProBalance rebaixando o processo, e o driver gráfico
dividindo núcleo com a thread que saturava.

Essa distinção importa para o enquadramento público:

- Quem **tem Process Lasso sem excluir o jogo do ProBalance** está no mesmo cenário e tende a
  ganhar muito.
- Quem **nunca usou Process Lasso** não tem essa penalidade para remover — o ganho vem da
  afinidade e aparece mais nos **vales** (menos queda súbita) do que na média.

O enquadramento honesto é *"o LoL é single-thread e talvez algo esteja atrapalhando esse núcleo;
veja como medir na sua máquina"* — não *"seu PC está mal configurado"*, que joga a culpa no
leitor e envelhece mal.
