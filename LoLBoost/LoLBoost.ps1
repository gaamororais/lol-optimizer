<#
    LoLBoost - otimizacao automatica de FPS para League of Legends
    ---------------------------------------------------------------
    O QUE FAZ:
      1. Detecta o hardware (e ABORTA a parte de afinidade se for CPU hibrida)
      2. Ajustes seguros: GameDVR, plano de energia, game.cfg
      3. SEPARA o driver de video do nucleo do jogo (achado principal), com
         medicao opcional pra descobrir QUAL nucleo e o melhor
      4. Fixa o driver grafico nesse nucleo (registro)
      5. Instala e configura o Process Lasso com a afinidade correta
      6. Gera um script de DESFAZER

    NAO FAZ (de proposito):
      - Nao mexe em HVCI / UAC / Secure Boot (seguranca)
      - Nao instala nada sem perguntar
      - Nao chuta afinidade em CPU hibrida (P-core/E-core)

    Licenca: use por sua conta e risco. Faz backup de tudo que altera.
#>

$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'LoLBoost'
# $PSScriptRoot e $MyInvocation.MyCommand.Path ficam VAZIOS quando o codigo vem
# por 'irm ... | iex' (nao existe arquivo em disco). Sem esse fallback o script
# morria aqui, na primeira linha, antes de fazer qualquer coisa.
$root = if ($PSScriptRoot) { $PSScriptRoot }
        elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path }
        else { Join-Path $env:LOCALAPPDATA 'LoLBoost' }
if (-not (Test-Path $root)) { New-Item -ItemType Directory -Force $root | Out-Null }

$undoFile   = Join-Path $root 'DESFAZER.ps1'
$logFile    = Join-Path $root 'LoLBoost.log'
$undo       = New-Object System.Collections.Generic.List[string]

# O estado original NAO mora na pasta do script de proposito. Se morasse, quem
# baixa o zip, roda, apaga a pasta e baixa de novo perderia o registro dos
# valores originais - e a proxima execucao capturaria como "original" o que a
# primeira ja tinha modificado, em silencio. Ancorado no LOCALAPPDATA, sobrevive
# a apagar a pasta e e o mesmo arquivo se a pessoa rodar pelo zip numa vez e por
# 'irm | iex' na outra.
$estadoDir  = Join-Path $env:LOCALAPPDATA 'LoLBoost'
if (-not (Test-Path $estadoDir)) { New-Item -ItemType Directory -Force $estadoDir | Out-Null }
$estadoFile = Join-Path $estadoDir 'LoLBoost.original.json'

# Estado ORIGINAL da maquina, gravado na PRIMEIRA execucao e nunca sobrescrito.
# Sem isso, rodar o script duas vezes fazia ele capturar como "valor anterior" o
# que ELE MESMO escreveu na primeira rodada: o DESFAZER passava a "restaurar" o
# estado ja modificado e ainda reportava sucesso. Os arquivos editados tinham essa
# protecao (backup .bak so se nao existir); os valores de registro e o plano de
# energia nao tinham.
$estado = @{}
if (Test-Path $estadoFile) {
    try {
        (Get-Content $estadoFile -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { $estado[$_.Name] = $_.Value }
    } catch { }
}
function LembraOriginal($nome, $valor) {
    if (-not $estado.ContainsKey($nome)) {
        $estado[$nome] = $valor
        try { ($estado | ConvertTo-Json -Compress) | Set-Content -Path $estadoFile -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
    }
    return $estado[$nome]
}

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color; Add-Content -Path $logFile -Value $msg -ErrorAction SilentlyContinue }
function Title($msg) { Write-Host ''; Write-Host ('=' * 68) -ForegroundColor DarkCyan; Write-Host "  $msg" -ForegroundColor Cyan; Write-Host ('=' * 68) -ForegroundColor DarkCyan }
# O log tem que guardar a RESPOSTA, nao so a pergunta. Sem isso, quando algo da
# errado nao ha como saber que caminho a pessoa escolheu - foi exatamente o que
# faltou pra diagnosticar o primeiro travamento em campo.
function Ask($msg) {
    Write-Host ''
    Write-Host "$msg [S/N] " -ForegroundColor Yellow -NoNewline
    $resp = Read-Host
    $sim  = ($resp -match '^[SsYy]')
    Add-Content -Path $logFile -Value ("PERGUNTA: $msg" + "   >>> RESPONDEU: '" + $resp + "' = " + $(if ($sim) { 'SIM' } else { 'NAO' })) -ErrorAction SilentlyContinue
    return $sim
}

# Menu de varias opcoes, com a resposta registrada no log do mesmo jeito.
function Escolha($msg, $valido, $padrao) {
    Write-Host ''
    Write-Host "$msg " -ForegroundColor Yellow -NoNewline
    $resp = Read-Host
    if ($valido -notcontains $resp) { $resp = $padrao }
    Add-Content -Path $logFile -Value ("MENU: $msg   >>> ESCOLHEU: $resp") -ErrorAction SilentlyContinue
    return $resp
}

# O DESFAZER precisa existir A PARTIR DA PRIMEIRA alteracao, nao no fim: com
# $ErrorActionPreference='Stop' qualquer falha no meio abortava o script depois
# de ja ter mexido no registro, no plano de energia e no game.cfg - e sem gerar
# o arquivo de reversao. Agora ele e regravado a cada mudanca.
$atalhoDesfazer = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DESFAZER LoLBoost.bat'

function GravaDesfazer {
    $txt = @(
        '# DESFAZER - reverte o que o LoLBoost alterou nesta maquina',
        '# Rode como Administrador. Gerado incrementalmente: se o LoLBoost parou',
        '# no meio, este arquivo cobre tudo o que ele alterou ate parar.',
        'if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Host "Rode como Admin"; pause; exit }',
        ''
    ) + $undo + @(
        '',
        'Write-Host "Revertido. Reinicie o PC." -ForegroundColor Green',
        # limpa o proprio atalho da area de trabalho: depois de reverter ele nao
        # serve mais pra nada, e deixar lixo na area de trabalho de quem acabou
        # de desfazer e falta de educacao
        ("Remove-Item '$atalhoDesfazer' -Force -ErrorAction SilentlyContinue"),
        'pause'
    )
    Set-Content -Path $undoFile -Value $txt -ErrorAction SilentlyContinue

    # Atalho na AREA DE TRABALHO. Quem precisa do desfazer costuma estar com
    # pressa e sem paciencia pra procurar pasta dentro do LOCALAPPDATA - e pode
    # justamente alguem cujo PC acabou de ficar pior. Um clique resolve.
    if (-not (Test-Path $atalhoDesfazer)) {
        $bat = @(
            '@echo off',
            'title DESFAZER LoLBoost',
            'echo.',
            'echo  Isto vai reverter tudo o que o LoLBoost alterou nesta maquina.',
            'echo.',
            'net session >nul 2>&1',
            'if %errorLevel% neq 0 (',
            "    powershell -NoProfile -Command ""Start-Process '%~f0' -Verb RunAs""",
            '    exit /b',
            ')',
            ("powershell -NoProfile -ExecutionPolicy Bypass -File ""$undoFile""")
        )
        Set-Content -Path $atalhoDesfazer -Value $bat -Encoding OEM -ErrorAction SilentlyContinue
    }
}

# Cria a chave SEM destruir o que ja existe nela. 'New-Item -Force' numa chave de
# registro EXISTENTE recria a chave e APAGA valores e subchaves (testado). Isso
# torrava o HKCU:\System\GameConfigStore inteiro - que guarda GameDVR_FSEBehavior,
# Win32_AutoGameModeDefaultProfile e configuracoes por jogo - sem backup.
function GaranteChave($caminho) {
    if (-not (Test-Path $caminho)) { New-Item -Path $caminho -Force | Out-Null; return $true }
    return $false   # ja existia, nao foi tocada
}

# Descobre o encoding do arquivo. LEITURA E ESCRITA PRECISAM USAR O MESMO: no
# Windows PowerShell 5.1, 'Get-Content' sem -Encoding le UTF-8 sem BOM como ANSI
# (testado: "aplicacao.exe" com cedilha volta como mojibake) e 'Set-Content' sem
# -Encoding grava ANSI. Detectar so na escrita nao resolve nada - grava o
# mojibake de volta como UTF-8 valido e a corrupcao fica permanente.
function DetectaEncoding($caminho) {
    try {
        $bytes = [IO.File]::ReadAllBytes($caminho)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            return (New-Object System.Text.UTF8Encoding($true))        # tem BOM
        }
        $temAlto = $false
        foreach ($b in $bytes) { if ($b -ge 0x80) { $temAlto = $true; break } }
        if (-not $temAlto) { return (New-Object System.Text.UTF8Encoding($false)) }   # ASCII puro
        try {
            $estrito = New-Object System.Text.UTF8Encoding($false, $true)
            $null = $estrito.GetString($bytes)
            return (New-Object System.Text.UTF8Encoding($false))       # UTF-8 valido sem BOM
        } catch {
            return [System.Text.Encoding]::Default                     # ANSI da maquina
        }
    } catch {
        return (New-Object System.Text.UTF8Encoding($false))
    }
}

function LeIni($caminho)          { return [IO.File]::ReadAllLines($caminho, (DetectaEncoding $caminho)) }
function EscreveIni($caminho, $linhas, $enc) {
    if (-not $enc) { $enc = DetectaEncoding $caminho }
    [IO.File]::WriteAllLines($caminho, [string[]]$linhas, $enc)
}

# ---------------------------------------------------------------------
# As tres funcoes abaixo existem como FUNCAO (e nao inline) para que os
# testes em testes/testar.ps1 exercitem o codigo publicado de verdade,
# em vez de uma reimplementacao paralela que pode divergir em silencio.
# ---------------------------------------------------------------------

# Extrai o GUID do plano de energia da saida do powercfg. Por posicao nao serve:
# em pt-BR a saida e "GUID do Esquema de Energia: <guid>" e o indice 3 cai em "de".
function GuidDoPlano($saida) {
    return [regex]::Match([string]$saida, '[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}', 'IgnoreCase').Value
}

# Mascara de bits do nucleo para AssignmentSetOverride: little-endian, com o menor
# numero de bytes que comporta o bit (nucleos acima de 7 precisam de 2+ bytes).
function MascaraAfinidade($core) {
    $mask  = [uint64]1 -shl $core
    $bytes = [BitConverter]::GetBytes($mask)
    $len   = [Math]::Max(1, ([Math]::Floor($core / 8) + 1))
    return [byte[]]($bytes[0..($len-1)])
}

# A conta classica ("sem SMT e threads != cores") NAO pega hibrida sem
# Hyper-Threading: num Core Ultra 200S (285K = 24C/24T, 8P+16E) threads == cores.
# Intel 12a geracao em diante entra por PRECAUCAO, porque separar P de E exigiria
# GetSystemCpuSetInformation. No pior caso pula afinidade numa CPU uniforme.
function EhCpuHibrida($nome, $cores, $threads) {
    $smt       = ($threads -eq $cores * 2)
    $intelNova = ([string]$nome -match '1[2-9]th Gen|Core\(TM\)\s*Ultra|Core\s*Ultra')
    return ((-not $smt) -and ($threads -ne $cores)) -or $intelNova
}

# ---------- admin ----------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Precisa rodar como Administrador. Use o LoLBoost.bat.' -ForegroundColor Red
    Read-Host 'Enter para sair'; exit 1
}

# APPEND, nao sobrescreve. O log e a unica evidencia de por que uma execucao
# falhou - e a reacao natural de quem viu dar errado e rodar de novo, o que
# apagaria justamente o registro do problema. Cada execucao entra como um bloco
# novo, com data.
Add-Content -Path $logFile -Value @(
    '',
    ('=' * 70),
    ("LoLBoost - execucao de " + (Get-Date -Format 'dd/MM/yyyy HH:mm:ss')),
    ('=' * 70)
) -ErrorAction SilentlyContinue

# Elevar pode TROCAR de usuario: em PC de familia, se quem joga esta numa conta
# padrao e o UAC pede a senha de uma conta de administrador, o script passa a
# rodar COMO o admin. Ai o HKCU (GameDVR) e o AppData que ele mexe sao do admin,
# e a conta de quem joga continua exatamente como estava.
$donoSessao = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
if ($donoSessao -and ($donoSessao -notmatch ('\\' + [regex]::Escape($env:USERNAME) + '$'))) {
    Say ''
    Say 'ATENCAO: voce elevou com uma conta DIFERENTE da que esta usando o Windows.' Yellow
    Say ("  sessao do Windows .. $donoSessao") Gray
    Say ("  rodando como ....... $env:USERNAME") Gray
    Say 'O ajuste de GameDVR e por USUARIO: ele vai valer para a conta que elevou,' Yellow
    Say 'nao para quem joga. O ideal e rodar logado na conta do jogador.' Yellow
    if (-not (Ask 'Continuar mesmo assim?')) { Say 'Encerrado sem alterar nada.' Gray; Read-Host 'Enter para sair'; exit 0 }
}

Title 'LoLBoost - otimizacao de FPS para League of Legends'
Say 'Ele faz copia de seguranca de tudo que altera, e cria um atalho' Gray
Say '"DESFAZER LoLBoost" na sua Area de Trabalho desde a PRIMEIRA mudanca -' Gray
Say 'entao mesmo se algo der errado no meio, voce tem um clique pra voltar.' Gray
Say ''
Say 'Com a SUA permissao, ele pode baixar duas ferramentas de terceiros:' Gray
Say '  - AutoGpuAffinity (github.com/valleyofdoom) - mede o melhor nucleo' Gray
Say '  - Process Lasso (bitsum.com) - so se ainda nao estiver instalado' Gray
Say 'Ele PERGUNTA antes de cada um. Respondendo N, o resto continua.' Gray

# =====================================================================
Title '1/6  DETECTANDO HARDWARE'
# =====================================================================
$cpu      = Get-CimInstance Win32_Processor | Select-Object -First 1
$cores    = [int]$cpu.NumberOfCores
$threads  = [int]$cpu.NumberOfLogicalProcessors
$smt      = ($threads -eq $cores * 2)

# A heuristica "sem SMT e threads != cores" NAO pega hibrida SEM Hyper-Threading:
# num Core Ultra 200S (ex: 285K = 24C/24T, 8P+16E) threads == cores, entao ele
# passava como "uniforme" e a afinidade RODAVA - podendo prender o jogo nos
# E-cores, exatamente o dano que essa guarda existe pra evitar. Mesmo caso de
# qualquer 12a-14a geracao com HT desligado na BIOS.
# Sem GetSystemCpuSetInformation nao da pra separar P de E aqui, entao Intel de
# 12a geracao em diante entra na guarda por PRECAUCAO: no pior caso a afinidade
# e pulada numa CPU que seria uniforme (um i3-12100 nao tem E-core) - deixa de
# ganhar, nao perde.
$intelNova = ([string]$cpu.Name -match '1[2-9]th Gen|Core\(TM\)\s*Ultra|Core\s*Ultra')
$hibrida   = EhCpuHibrida $cpu.Name $cores $threads

Say ("CPU ............ " + $cpu.Name) White
Say ("Nucleos ........ $cores fisicos / $threads logicos") White
$gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'B.sic|Remote|Mirror|Espelh' })
Say ("GPU ............ " + (($gpus | ForEach-Object { $_.Name }) -join ' + ')) White
if ($gpus.Count -gt 1) { Say '                 (mais de uma - vou perguntar qual na etapa 4)' Gray }

# Integrada ou dedicada? Detectar por nome e heuristica furada ("Radeon Graphics"
# pode ser APU ou placa dedicada), e a resposta muda o que faz sentido aplicar.
# A pessoa sabe responder isso melhor do que qualquer regex.
$integrada = $false
if ($gpus.Count -eq 1) {
    Say ''
    Say 'Uma pergunta que muda o que vale a pena fazer:' White
    Say '  DEDICADA = placa separada (GTX, RTX, RX, Arc)' Gray
    Say '  INTEGRADA = video do proprio processador (Intel UHD/Iris, Radeon Graphics de APU)' Gray
    $integrada = Ask 'A sua placa de video e a INTEGRADA do processador?'
}

if ($integrada) {
    Say ''
    Say '=== ATENCAO: GPU INTEGRADA - LEIA ANTES DE CONTINUAR ===' Yellow
    Say 'Este script resolve UM gargalo especifico: um nucleo do processador' Yellow
    Say 'saturado enquanto a placa de video fica ociosa. Com video integrado, e' Yellow
    Say 'bem possivel que o seu teto seja a PROPRIA GPU - e nesse caso NADA aqui' Yellow
    Say 'vai te dar FPS. Nao prometo numero pra esse cenario.' Yellow
    Say ''
    Say 'COMO DESCOBRIR (2 min, antes de mexer em nada):' White
    Say '  1. Abra o Gerenciador de Tarefas (Ctrl+Shift+Esc) > aba Desempenho' White
    Say '  2. Entre numa partida e jogue uma teamfight' White
    Say '  3. GPU em 95-100%%  -> o teto e a GPU. Este script nao resolve.' White
    Say '     GPU folgada + 1 nucleo estourado -> e o caso deste projeto.' White
    Say ''
    Say 'O que AINDA vale pra voce de qualquer forma: prioridade Alta e a' Green
    Say 'exclusao do ProBalance (etapa 5). Sao de graca e nao custam nucleo.' Green
    if (-not (Ask 'Quer continuar?')) {
        Say 'Encerrado sem alterar nada.' Gray
        Read-Host 'Enter para sair'; exit 0
    }
}

if ($hibrida) {
    Say ''
    Say 'ATENCAO: o seu processador mistura nucleos RAPIDOS com nucleos LENTOS' Yellow
    Say 'de economia, no mesmo chip. (Intel chama de P-core e E-core.)' Yellow
    if ($intelNova -and $threads -eq $cores) {
        Say 'No seu caso nao da pra distinguir um do outro so pela contagem, porque' Gray
        Say 'o Hyper-Threading esta desligado. Entao vou assumir que existem.' Gray
    }
    Say ''
    Say 'POR QUE ISSO IMPORTA: se eu mandasse o jogo para os nucleos LENTOS por' Yellow
    Say 'engano, o seu FPS cairia PELA METADE. Distinguir com seguranca exige uma' Yellow
    Say 'tecnica que ainda nao esta pronta aqui, entao NAO vou mexer nos nucleos.' Yellow
    Say 'Voce deixa de ganhar um pouco, mas nao corre esse risco.' Yellow
    Say ''
    Say 'O resto continua: prioridade do jogo e o ajuste do Process Lasso, que e' Green
    Say 'a parte que nao depende de nucleo nenhum.' Green
} elseif ($smt) {
    Say ("Seus $cores nucleos aparecem como $threads pra o Windows (cada nucleo faz duas") Gray
    Say 'filas de trabalho). Isso e normal e o script sabe lidar.' Gray
} else {
    Say ("Seus $cores nucleos aparecem como $threads pra o Windows: um pra um.") Gray
}

# =====================================================================
Title '2/6  AJUSTES SEGUROS'
# =====================================================================

# --- GameDVR ---
$chaveHkcu = 'HKCU:\System\GameConfigStore'
$chaveHklm = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'

# LembraOriginal: na 2a execucao devolve o valor da 1a, nao o que o script gravou
$gdvrOld  = LembraOriginal 'gdvr_hkcu'        ((Get-ItemProperty $chaveHkcu -Name GameDVR_Enabled -ErrorAction SilentlyContinue).GameDVR_Enabled)
$criouCu  = LembraOriginal 'gdvr_hkcu_criada' (GaranteChave $chaveHkcu)   # NAO usa New-Item -Force
Set-ItemProperty -Path $chaveHkcu -Name GameDVR_Enabled -Value 0 -Type DWord
if ($criouCu)                { $undo.Add("Remove-Item '$chaveHkcu' -Recurse -Force -EA SilentlyContinue") }
elseif ($null -ne $gdvrOld)  { $undo.Add("Set-ItemProperty '$chaveHkcu' GameDVR_Enabled $gdvrOld") }
else                         { $undo.Add("Remove-ItemProperty '$chaveHkcu' GameDVR_Enabled -EA SilentlyContinue") }

$allowOld = LembraOriginal 'gdvr_hklm'        ((Get-ItemProperty $chaveHklm -Name AllowGameDVR -ErrorAction SilentlyContinue).AllowGameDVR)
$criouLm  = LembraOriginal 'gdvr_hklm_criada' (GaranteChave $chaveHklm)
Set-ItemProperty -Path $chaveHklm -Name AllowGameDVR -Value 0 -Type DWord
# So remove a chave de politica se FOMOS NOS que a criamos. Se ela ja existia
# (politica corporativa/OEM), apagar recursivamente destruiria configuracao alheia.
if ($criouLm)                { $undo.Add("Remove-Item '$chaveHklm' -Recurse -Force -EA SilentlyContinue") }
elseif ($null -ne $allowOld) { $undo.Add("Set-ItemProperty '$chaveHklm' AllowGameDVR $allowOld") }
else                         { $undo.Add("Remove-ItemProperty '$chaveHklm' AllowGameDVR -EA SilentlyContinue") }
Say 'GameDVR ........ desativado' Green
GravaDesfazer

# --- plano de energia ---
# NAO usar ((powercfg /getactivescheme) -split ' ')[3]: a posicao do GUID muda
# com o idioma do Windows. Em pt-BR a saida e "GUID do Esquema de Energia: <guid>"
# e o indice 3 cai em "de", gerando um DESFAZER que NAO restaura o plano.
#
# E cuidado com stderr de comando nativo: no Windows PowerShell 5.1, com
# $ErrorActionPreference='Stop', "powercfg ... 2>$null" vira erro TERMINANTE e
# MATA o script. Muitos notebooks (Modern Standby) NAO tem o plano Alto
# Desempenho, e o script morria justamente ai - depois de ja ter mexido no
# registro. Por isso: EAP local em Continue, e checar $LASTEXITCODE.
$planoAlto = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$eapAntigo = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $planOld  = LembraOriginal 'plano' (GuidDoPlano (powercfg /getactivescheme 2>$null | Out-String))
    $temAlto  = (powercfg /list 2>$null | Out-String) -match [regex]::Escape($planoAlto)
    $trocou   = $false
    if ($temAlto) {
        powercfg /setactive $planoAlto 2>$null | Out-Null
        $trocou = ($LASTEXITCODE -eq 0)
    }
} finally {
    $ErrorActionPreference = $eapAntigo
}

if ($trocou) {
    Say 'Energia ........ Alto Desempenho' Green
    if ($planOld) {
        $undo.Add("powercfg /setactive $planOld")
    } else {
        Say 'AVISO: nao li o plano anterior - o DESFAZER nao vai restaura-lo.' Yellow
        $undo.Add("Write-Host 'OBS: o plano de energia anterior nao foi capturado. Ajuste em Configuracoes > Sistema > Energia.' -ForegroundColor Yellow")
    }
} elseif (-not $temAlto) {
    Say 'Energia ........ PULADO - esta maquina nao tem o plano Alto Desempenho' Yellow
    Say '                 (normal em notebook com Modern Standby). Nada foi alterado.' Gray
} else {
    Say 'Energia ........ PULADO - o powercfg recusou a troca. Nada foi alterado.' Yellow
}
GravaDesfazer

# --- game.cfg ---
# Procura o arquivo ANTES de decidir se edita: se uma execucao anterior ja editou
# e esta pulou (LoL aberto), a linha de restauracao tem que continuar no DESFAZER.
# Senao o DESFAZER "encolhe" na segunda rodada e deixa de reverter algo que ainda
# esta aplicado - e o README promete reverter tudo que foi alterado.
$cfg = $null
foreach ($d in (Get-PSDrive -PSProvider FileSystem).Name) {
    $p = "${d}:\Riot Games\League of Legends\Config\game.cfg"
    if (Test-Path $p) { $cfg = $p; break }
}
if ($cfg -and (Test-Path "$cfg.LoLBoost.bak")) {
    $undo.Add("Copy-Item '$cfg.LoLBoost.bak' '$cfg' -Force")
    GravaDesfazer
}

$riot = Get-Process -Name 'League of Legends','LeagueClient','LeagueClientUx','RiotClientServices' -ErrorAction SilentlyContinue
if ($riot) {
    Say 'game.cfg ....... PULADO (feche o LoL e o Riot Client e rode de novo)' Yellow
    if ($cfg -and (Test-Path "$cfg.LoLBoost.bak")) {
        Say '                 (uma execucao anterior ja editou; o DESFAZER continua' Gray
        Say '                  cobrindo essa alteracao)' Gray
    }
} else {
    if (-not $cfg) {
        Say 'game.cfg ....... nao encontrado (ajuste manual)' Yellow
    } else {
        $bak = "$cfg.LoLBoost.bak"
        $jaTinhaBak = Test-Path $bak
        if (-not $jaTinhaBak) { Copy-Item $cfg $bak -Force }
        $t = Get-Content $cfg
        $t = $t -replace '^EnableHUDAnimations=.*','EnableHUDAnimations=0'
        $t = $t -replace '^HideEyeCandy=.*','HideEyeCandy=1'
        $t = $t -replace '^ShowGodray=.*','ShowGodray=0'
        $t = $t -replace '^EnableReplayApi=.*','EnableReplayApi=0'
        if (-not ($t -match '^EnableParticleOptimizations=')) {
            $t = $t -replace '^\[Performance\]', "[Performance]`r`nEnableParticleOptimizations=1"
        }
        Set-Content -Path $cfg -Value $t
        Say "game.cfg ....... ajustado (backup: $bak)" Green
        Say '                 OBS: EnableReplayApi=0 DESLIGA a gravacao de replays' Yellow
        Say '                 (.rofl). Se voce usa replay, edite o game.cfg e volte' Yellow
        Say '                 essa chave para 1, ou rode o DESFAZER.' Yellow
        if (-not $jaTinhaBak) { $undo.Add("Copy-Item '$bak' '$cfg' -Force") }   # se ja tinha, foi adicionada acima
        GravaDesfazer
    }
}

# =====================================================================
Title '3/6  SEPARAR O DRIVER DE VIDEO DO NUCLEO DO JOGO'
# =====================================================================

$melhorCore      = $null
$plEstavaRodando = $false
$separarSemMedir = $false

if ($hibrida) {
        Say 'Pulado (nucleos rapidos e lentos misturados - motivo na etapa 1).' Yellow
} else {
    Say 'Aqui esta o achado principal deste projeto: a placa de video TAMBEM da'
    Say 'trabalho ao processador, e o Windows por padrao deixa esse trabalho cair'
    Say 'em qualquer nucleo - inclusive no mesmo que o jogo esta lotando.'
    Say ''
    Say 'Tirar o driver de cima do nucleo do jogo e o que resolve. Sao DUAS coisas'
    Say 'diferentes, e voce escolhe quanto quer:' White
    Say ''
    Say '  SEPARAR  = tirar o driver do nucleo do jogo. E de onde vem o ganho.' Green
    Say '  MEDIR    = descobrir QUAL nucleo e o melhor pro driver. Refinamento' Gray
    Say '             em cima da separacao - e e a parte que tem risco.' Gray
    Say ''
    Say '=== ATENCAO: O RISCO ESTA NA MEDICAO, NAO NA SEPARACAO ===' Yellow
    Say 'Pra medir, o driver de video precisa ser REINICIADO uma vez por nucleo' Yellow
    Say ("(no seu caso, $threads vezes). A tela pisca e fica preta por segundos.") Yellow
    Say 'Existe risco REAL do driver travar e nao voltar - ja aconteceu numa' Red
    Say 'maquina testada, e o dono ficou sem video ate reiniciar no botao.' Red
    Say ''
    Say 'SE A TELA FICAR PRETA E NAO VOLTAR, DECORE ISTO AGORA:' White
    Say '  1. Aperte  Win + Ctrl + Shift + B   (reinicia o driver de video)' Green
    Say '  2. Nao voltou? Troque o cabo de porta na placa (HDMI <-> DisplayPort)' Green
    Say '  3. Nao voltou? Segure o botao de power 10s, desligue e ligue de novo' Green
    Say '     Depois disso, rode o DESFAZER da Area de Trabalho.' Green
    Say ''
    if ($integrada) {
        Say 'AGRAVANTE no seu caso: video integrado costuma ser o UNICO adaptador' Red
        Say 'da maquina - nao existe placa de reserva se o driver travar.' Red
        Say ''
    }
    Say 'ESCOLHA:' White
    Say '  [1] SEPARAR SEM MEDIR  - recomendado. Sem risco, a tela nao pisca.' Green
    Say '      Poe o driver num nucleo que o jogo nao vai usar. Nao descobre se' Green
    Say '      e o MELHOR nucleo, mas garante que ele para de brigar com o jogo.' Green
    Say '  [2] MEDIR E SEPARAR    - o ideal, se voce topa o risco acima.' Yellow
    Say ("      Demora ~$([math]::Round($threads * 0.5)) minutos com a tela piscando.") Yellow
    Say '  [3] NAO FAZER NADA AQUI - a etapa 5 (prioridade) continua.' Gray
    $escolha = Escolha 'Numero [1/2/3]:' @('1','2','3') '1'
    if ($escolha -eq '2') { $medir = $true }
    elseif ($escolha -eq '3') { $medir = $false; Say 'OK - nada sera feito nesta etapa.' Gray }
    else { $medir = $false; $separarSemMedir = $true }

    if ($medir) {
        $agaDir = Join-Path $root 'AutoGpuAffinity'
        $agaExe = Join-Path $agaDir 'AutoGpuAffinity\AutoGpuAffinity.exe'
        if (-not (Test-Path $agaExe)) {
            Say 'Baixando do GitHub oficial (valleyofdoom/AutoGpuAffinity)...'
            $zip = Join-Path $root 'aga.zip'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $rel = Invoke-RestMethod 'https://api.github.com/repos/valleyofdoom/AutoGpuAffinity/releases/latest' -Headers @{'User-Agent'='LoLBoost'}
            $asset = $rel.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
            Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
            Expand-Archive $zip $agaDir -Force
            Remove-Item $zip -Force
            Say ("Baixado: " + $asset.name) Green
        }
        # o layout do zip pode mudar num release futuro; sem esta checagem o
        # Start-Process falharia e, com EAP=Stop, o script morreria aqui
        if (-not (Test-Path $agaExe)) {
            Say 'ATENCAO: nao achei o AutoGpuAffinity.exe onde ele deveria estar:' Yellow
            Say ("  $agaExe") Gray
            Say 'O layout do pacote deve ter mudado. Pulando o benchmark - as etapas' Yellow
            Say '4 e 5 continuam (a 5 e a que mais rende).' Yellow
            $agaExe = $null
        }
        if ($agaExe) {
        # Anota que o Process Lasso estava rodando ANTES de matar. Sem isso, quem ja
        # tinha o programa instalado, rodava o benchmark e depois recusava a
        # configuracao ficava com o Process Lasso morto ate o reboot - as regras
        # que ele ja tinha paravam de valer, em silencio.
        if (Get-Process -Name 'ProcessLasso','ProcessGovernor' -EA SilentlyContinue) { $plEstavaRodando = $true }
        Get-Process -Name 'ProcessLasso','ProcessGovernor' -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue

        # O AutoGpuAffinity vem com skip_confirmation=false e pede "press ENTER to
        # start" - o que contradiz o nosso "nao mexa no PC". Liga o inicio
        # automatico; se a chave nao existir na versao baixada, o aviso abaixo cobre.
        $agaCfg = Join-Path (Split-Path $agaExe) 'config.ini'
        if (Test-Path $agaCfg) {
            $cc = Get-Content $agaCfg
            if ($cc -match '^\s*skip_confirmation\s*=') {
                $cc = $cc -replace '^\s*skip_confirmation\s*=.*', 'skip_confirmation=true'
                Set-Content -Path $agaCfg -Value $cc
                Say 'AutoGpuAffinity: inicio automatico ligado (skip_confirmation=true)' Gray
            }
        }

        Say 'Rodando o benchmark... nao mexa no PC. A tela vai piscar.' Yellow
        Say 'SE ele pedir "press ENTER to start", aperte Enter uma vez - depois disso' Yellow
        Say 'nao toque mais em nada ate ele terminar.' Yellow
        Push-Location (Split-Path $agaExe)
        # -Wait puro nao serve: se o driver de video travar no meio da medicao, o
        # AutoGpuAffinity nunca encerra e o script fica preso pra sempre - foi o que
        # aconteceu numa maquina real. Limite generoso (1 min por nucleo + 5 min de
        # folga) e, se estourar, encerra e segue. A limpeza da afinidade da placa
        # ja esta registrada no DESFAZER desde antes de comecar.
        $limiteSeg = [int](($threads * 60) + 300)
        $procAga = Start-Process -FilePath $agaExe -PassThru -NoNewWindow
        if (-not $procAga.WaitForExit($limiteSeg * 1000)) {
            Say ''
            Say ("O benchmark passou de $([math]::Round($limiteSeg / 60)) minutos sem terminar.") Red
            Say 'Isso costuma significar que o driver de video travou. Vou encerrar e' Red
            Say 'seguir sem o resultado da medicao.' Red
            Say ''
            Say 'IMPORTANTE: rode o DESFAZER da Area de Trabalho e REINICIE - ele limpa' Yellow
            Say 'a configuracao que o benchmark deixou na sua placa de video.' Yellow
            try { $procAga.Kill() } catch { }
            Start-Sleep -Seconds 3
        }
        Pop-Location

        # ---- analisar os CSVs ----
        $cap = Get-ChildItem (Join-Path (Split-Path $agaExe) 'captures') -Directory -EA SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($cap) {
            $res = @()
            foreach ($csv in Get-ChildItem (Join-Path $cap.FullName 'CSVs') -Filter 'CPU-*.csv' -EA SilentlyContinue) {
                $n  = [int]($csv.BaseName -replace 'CPU-','')
                $ft = Import-Csv $csv.FullName | ForEach-Object { [double]$_.msBetweenPresents } | Where-Object { $_ -gt 0 } | Sort-Object
                if ($ft.Count -lt 100) { continue }
                # percentis altos de frametime = os piores frames
                $p99   = $ft[[int][Math]::Floor($ft.Count * 0.99)]
                $p999  = $ft[[int][Math]::Floor($ft.Count * 0.999)]
                $p9999 = $ft[[int][Math]::Floor($ft.Count * 0.9999)]
                $res += [pscustomobject]@{
                    CPU      = $n
                    Amostras = $ft.Count
                    Media    = [math]::Round(1000 / ($ft | Measure-Object -Average).Average, 2)
                    Low1     = [math]::Round(1000 / $p99, 2)
                    Low01    = [math]::Round(1000 / $p999, 2)
                    Low001   = [math]::Round(1000 / $p9999, 2)
                }
            }
            if ($res.Count -gt 0) {
                # ranking: prioriza 0.1% low (consistencia), desempata no 1% low
                $rank = $res | Sort-Object -Property @{E='Low01';D=$true}, @{E='Low1';D=$true}
                Say ''
                Say 'RESULTADO (ordenado do melhor para o pior):' Cyan
                $rank | Format-Table CPU, Amostras, Media, Low1, Low01, Low001 -AutoSize | Out-String | Write-Host
                $melhorCore = $rank[0].CPU
                Say ("MELHOR nucleo para o driver grafico: CPU $melhorCore") Green
                Say ("PIOR (evitar): CPU " + $rank[-1].CPU) Red
                $rank | Export-Csv (Join-Path $root 'resultado_nucleos.csv') -NoTypeInformation
            } else { Say 'Nao consegui ler os resultados do benchmark.' Yellow }
        } else { Say 'Pasta de resultados nao encontrada.' Yellow }
        }   # fecha o if ($agaExe) da checagem de layout do pacote
    }

    # O AutoGpuAffinity fixa o driver em cada nucleo pra testar e restaura no fim.
    # Se ele morrer no meio (driver travado), a placa fica PRESA no ultimo nucleo
    # testado - e o dono nao tem ideia disso. Nosso DESFAZER passa a limpar isso
    # tambem: se a gente chama a ferramenta, a gente e responsavel pelo que ela
    # deixa pra tras. Registrado ANTES de rodar o benchmark, de proposito.
    if ($medir) {
        foreach ($dsp in (Get-PnpDevice -Class Display -EA SilentlyContinue)) {
            $kd = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $dsp.InstanceId + "\Device Parameters\Interrupt Management\Affinity Policy"
            $undo.Add("Remove-Item '$kd' -Recurse -Force -EA SilentlyContinue")
        }
        GravaDesfazer
    }
}

# Escolha SEM medicao: qualquer nucleo livre resolve a briga com o jogo, e
# escrever a configuracao NAO reinicia driver nenhum - so passa a valer no boot.
# Todo o risco de tela preta estava na MEDICAO, nao aqui.
if ($separarSemMedir -and -not $hibrida) {
    $melhorCore = if ($smt) { 1 } else { 0 }
    Say ''
    Say ("Sem medir: vou colocar o driver de video na CPU $melhorCore, e tirar o jogo") Green
    Say 'de cima dela. Nao sei dizer se esse e o MELHOR nucleo da sua maquina -' Yellow
    Say 'pra saber isso so medindo - mas sei que ele deixa de brigar com o jogo,' Green
    Say 'que e de onde vem o ganho.' Green
    Say ''
    Say 'Nenhum driver vai ser reiniciado agora. A tela nao vai piscar.' Green
}

# =====================================================================
Title '4/6  COLOCAR O DRIVER DE VIDEO NO NUCLEO ESCOLHIDO'
# =====================================================================

$coreDriverFisico = $null
if ($null -ne $melhorCore) {
    # 'Select -First 1' era furado: numa maquina com integrada + dedicada (ex: i5
    # nao-F com a iGPU habilitada na BIOS + placa dedicada), a Intel costuma vir
    # primeiro na enumeracao e a afinidade acabava fixada na placa ERRADA - a
    # etapa toda sem efeito. O 'B.sic' do filtro pega 'Basic' e 'Basico' sem
    # depender de acento no arquivo.
    $devs = @(Get-PnpDevice -Class Display -EA SilentlyContinue |
              Where-Object { $_.Status -eq 'OK' -and $_.FriendlyName -notmatch 'B.sic|Remote|Mirror|Espelh' })

    $dev = $null
    if ($devs.Count -eq 1) {
        $dev = $devs[0]
    } elseif ($devs.Count -gt 1) {
        Say ''
        Say 'Mais de uma placa de video ativa nesta maquina:' Yellow
        for ($i = 0; $i -lt $devs.Count; $i++) { Say ("  [$i] " + $devs[$i].FriendlyName) White }
        Say 'Escolha a que voce USA PRA JOGAR (a dedicada, nao a integrada).' Yellow
        Write-Host ("Numero [0-" + ($devs.Count - 1) + "]: ") -ForegroundColor Yellow -NoNewline
        $resp = Read-Host
        $idx = 0
        if ([int]::TryParse($resp, [ref]$idx) -and $idx -ge 0 -and $idx -lt $devs.Count) {
            $dev = $devs[$idx]
        } else {
            # NAO cair no [0]: em notebook hibrido o [0] costuma ser a integrada,
            # que e exatamente o erro que esta escolha existe pra evitar.
            Say 'Resposta invalida. PULANDO esta etapa em vez de chutar a placa.' Yellow
            Say 'Rode o script de novo se quiser fixar o driver.' Yellow
        }
    }

    if ($dev) {
        $k = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($dev.InstanceId)\Device Parameters\Interrupt Management\Affinity Policy"
        Say ("Dispositivo: " + $dev.FriendlyName)
            $perg = if ($separarSemMedir) { "Colocar o driver de video na CPU $melhorCore (sem piscar a tela)?" } else { "Colocar o driver de video na CPU $melhorCore, que ganhou na medicao?" }
            if (Ask $perg) {
            # Guarda o que JA existia: quem ja rodou AutoGpuAffinity ou utilitario
            # de placa-mae pode ter DevicePolicy/AssignmentSetOverride configurados.
            # Antes o undo removia a chave inteira, jogando fora config alheia.
            $polLida = $null; $setLido = ''
            if (Test-Path $k) {
                $polLida = (Get-ItemProperty $k -Name DevicePolicy          -EA SilentlyContinue).DevicePolicy
                $b       = (Get-ItemProperty $k -Name AssignmentSetOverride -EA SilentlyContinue).AssignmentSetOverride
                if ($null -ne $b) { $setLido = (($b | ForEach-Object { $_.ToString() }) -join ',') }
            }
            # valores ORIGINAIS: na 2a execucao vem da 1a, nao do que o script gravou
            $polAntiga = LembraOriginal 'afin_pol'    $polLida
            $setAntigo = LembraOriginal 'afin_set'    $setLido
            $criouAfin = LembraOriginal 'afin_criada' (GaranteChave $k)   # NAO usa New-Item -Force

            Set-ItemProperty -Path $k -Name DevicePolicy -Value 4 -Type DWord
            Set-ItemProperty -Path $k -Name AssignmentSetOverride -Value (MascaraAfinidade $melhorCore) -Type Binary
            Say "Driver grafico fixado na CPU $melhorCore (reinicio necessario)" Green

            if ($criouAfin) {
                $undo.Add("Remove-Item '$k' -Recurse -Force -EA SilentlyContinue")
            } else {
                if ($null -ne $polAntiga) { $undo.Add("Set-ItemProperty '$k' DevicePolicy $polAntiga -Type DWord") }
                else                      { $undo.Add("Remove-ItemProperty '$k' DevicePolicy -EA SilentlyContinue") }
                if ($setAntigo) {
                    $undo.Add("Set-ItemProperty '$k' AssignmentSetOverride ([byte[]]@($setAntigo)) -Type Binary")
                } else {
                    $undo.Add("Remove-ItemProperty '$k' AssignmentSetOverride -EA SilentlyContinue")
                }
            }
            GravaDesfazer
            $coreDriverFisico = [math]::Floor($melhorCore / $(if ($smt) {2} else {1}))
        }
    } else { Say 'Placa de video nao encontrada.' Yellow }
} else { Say 'Pulado (sem resultado de benchmark).' Yellow }

# =====================================================================
Title '5/6  PRIORIDADE DO JOGO E DIVISAO DE NUCLEOS'
# =====================================================================

# Antes, CPU hibrida pulava a etapa 5 INTEIRA - jogando fora a prioridade Alta e
# a exclusao do ProBalance, que sao as que mais rendem, valem em qualquer CPU e
# nao dependem de afinidade nenhuma. Agora so a AFINIDADE e condicional.
$aplicarAfinidade = -not $hibrida
$afinidade = ''

Say 'Nesta etapa eu faco duas coisas, e vale saber o que cada uma e:' White
Say ''
Say '  PRIORIDADE = quanta atencao o Windows da pro jogo quando ele e a' Gray
Say '               concorrer com outros programas.' Gray
Say '  DIVISAO DE NUCLEOS = dizer ao Windows em QUAIS nucleos do processador' Gray
Say '               o jogo pode rodar. Serve pra ele nao dividir nucleo com o' Gray
Say '               driver de video, que e o achado principal deste projeto.' Gray
Say ''

if ($hibrida) {
    Say 'A divisao de nucleos vai ser PULADA aqui - motivo explicado na etapa 1' Yellow
    Say '(nucleos rapidos e lentos misturados). A prioridade continua sendo' Yellow
    Say 'aplicada normalmente.' Yellow
}

if ($aplicarAfinidade) {
    # PISO DE NUCLEOS. A estrategia (1 thread por nucleo fisico, menos um nucleo
    # pro driver) foi medida num 8C/16T e extrapolada pra baixo sem medicao. Num
    # 4C/8T o jogo ficaria com 3 CPUs logicas, e o LoL tem mais threads ativas do
    # que isso (render submit, audio, particulas em thread separada). Pode PIORAR.
    # Em maquina pequena: nao reserva nucleo pro driver e pergunta antes de
    # restringir, com N como default.
    $pouquiNucleos = ($cores -le 4)
    if ($pouquiNucleos) {
        Say ''
        Say ("Seu processador tem $cores nucleos - poucos para esta tecnica.") Yellow
        Say 'Ela foi medida num processador de 8. Limitar o jogo a menos nucleos aqui' Yellow
        Say 'pode PIORAR o seu FPS, porque o jogo precisa de mais do que sobraria.' Yellow
        if ($null -ne $coreDriverFisico) {
            # Precisao: o driver JA foi fixado no registro na etapa 4. O que muda
            # aqui e so nao TIRAR esse nucleo da afinidade do jogo. Dizer
            # "nao vou reservar nucleo pro driver" descreveria um estado que nao
            # e o real.
            Say ("O driver de video continua na CPU $melhorCore, como foi medido.") Gray
            Say 'Mas NAO vou proibir o jogo de usar esse nucleo: com poucos nucleos,' Yellow
            Say 'tirar um do jogo custa mais do que a separacao rende.' Yellow
            $coreDriverFisico = $null
        }
        if (-not (Ask 'Limitar os nucleos do jogo mesmo assim? (recomendado: N)')) {
            $aplicarAfinidade = $false
            Say 'OK - o jogo segue livre pra usar todos os nucleos. A prioridade continua' Green
            Say 'sendo aplicada.' Green
        }
    }

    # Em GPU integrada, reservar um nucleo fisico pro driver e troca duvidosa: a
    # iGPU divide chip, memoria e orcamento de energia com a CPU, entao "isolar o
    # driver da CPU" nao isola grande coisa - e o custo e alto (num CPU de 4
    # nucleos, 25% do processador). Default = nao reservar.
    if ($integrada -and $null -ne $coreDriverFisico) {
        Say ''
        Say 'Seu video e integrado: ele divide o mesmo chip e a mesma memoria com o' Yellow
        Say ("Reservar um nucleo so pro driver custaria " + [math]::Round(100/$cores) + '% do seu processador,') Yellow
        Say 'processador, e nesse cenario o ganho e duvidoso.' Yellow
        if (-not (Ask 'Mesmo assim, reservar um nucleo so pro driver? (recomendado: N)')) {
            $coreDriverFisico = $null
            Say 'OK - o jogo vai poder usar todos os nucleos.' Green
        }
    }

    if ($aplicarAfinidade) {
        # nucleos que o LoL vai usar: 1 thread por nucleo fisico,
        # excluindo o nucleo fisico que ficou com o driver grafico
        $passo   = if ($smt) { 2 } else { 1 }
        $lista   = @()
        for ($f = 0; $f -lt $cores; $f++) {
            if ($null -ne $coreDriverFisico -and $f -eq $coreDriverFisico) { continue }
            $lista += ($f * $passo)
        }
        $afinidade = ($lista -join ';')
        Say ("Nucleos que o jogo vai poder usar: $afinidade") White
        if ($null -ne $coreDriverFisico) { Say '(um nucleo ficou reservado para o driver de video)' Gray }
    }
}

# O bloco do Process Lasso roda em TODA maquina, com ou sem afinidade.
# (nao ha condicional aqui de proposito - prioridade e ProBalance valem sempre)

    # O caminho do prolasso.ini NAO e fixo. A doc da Bitsum diz que ele e gerado
    # "per-user in the ProcessLasso subfolder of each user's application data
    # directory", e o admin pode mudar o caminho na instalacao. Hardcodar o
    # ProgramData faz o script achar que o programa nao esta instalado, reinstalar,
    # esperar por um arquivo que nunca aparece naquele caminho e cair em loop.
    function Find-ProlassoIni {
        $cands = @(
            'C:\ProgramData\ProcessLasso\config\prolasso.ini',      # config compartilhada
            (Join-Path $env:ProgramData 'ProcessLasso\prolasso.ini'),
            (Join-Path $env:APPDATA     'ProcessLasso\prolasso.ini'),
            (Join-Path $env:LOCALAPPDATA 'ProcessLasso\prolasso.ini')
        )
        foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
        foreach ($base in @($env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA)) {
            if (-not $base) { continue }
            $hit = Get-ChildItem -Path $base -Filter 'prolasso.ini' -Recurse -Force -EA SilentlyContinue |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
        return $null
    }

    # Nao hardcodar o Program Files: em instalacao com caminho customizado, o
    # script nao achava o executavel, nao reabria o programa depois de mata-lo e
    # nao conseguia "abrir uma vez pra gerar a config".
    $plExe = 'C:\Program Files\Process Lasso\ProcessLasso.exe'
    if (-not (Test-Path $plExe)) {
        foreach ($rk in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
            $e = Get-ItemProperty $rk -EA SilentlyContinue |
                 Where-Object { $_.DisplayName -match 'Process Lasso' } | Select-Object -First 1
            if ($e -and $e.InstallLocation) {
                $cand = Join-Path $e.InstallLocation 'ProcessLasso.exe'
                if (Test-Path $cand) { $plExe = $cand; Say ("Process Lasso em: $plExe") Gray; break }
            }
        }
    }
    $plIni = Find-ProlassoIni
    $plInstaladoAgora = $false
    if ($plIni) { Say ("prolasso.ini ... $plIni") Gray }

    if (-not $plIni) {
        Say ''
        Say 'Process Lasso nao esta instalado. Ele cuida da prioridade do jogo.' Yellow
        Say 'Ele e da Bitsum (bitsum.com) e e um programa PAGO, mas a versao free' Gray
        Say 'cobre tudo que este script usa: prioridade, nucleos e o ProBalance.' Gray
        Say 'de prioridade e prioridade de GPU. (Uso comercial exige compra.)' Gray
        Say 'Sera baixado de dl.bitsum.com e instalado em modo SILENCIOSO (/S).' Gray
        if (Ask 'Baixar e instalar o Process Lasso (versao free) agora?') {
            $inst = Join-Path $root 'processlasso_setup.exe'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest 'https://dl.bitsum.com/files/processlassosetup64.exe' -OutFile $inst -UseBasicParsing

            # Vai rodar um executavel baixado da internet COMO ADMIN: confere a
            # assinatura digital antes. A Bitsum assina os instaladores dela.
            $sig = Get-AuthenticodeSignature $inst
            $assinante = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '(sem certificado)' }
            Say ("Assinatura do instalador: " + $sig.Status) $(if ($sig.Status -eq 'Valid') { 'Green' } else { 'Red' })
            Say ("Assinado por: $assinante") Gray
            $seguir = $true
            if ($sig.Status -ne 'Valid') {
                Say 'AVISO: o arquivo baixado NAO tem assinatura digital valida. Isso pode' Red
                Say 'ser download corrompido ou arquivo trocado no caminho.' Red
                $seguir = Ask 'Executar mesmo assim?'
            }
            if (-not $seguir) {
                Say 'Instalacao cancelada. Nada foi executado.' Yellow
                Say 'Sem o Process Lasso, a exclusao do ProBalance e a prioridade Alta NAO' Yellow
                Say 'sao aplicadas. Voce pode' Yellow
                Say 'instalar na mao pelo site oficial (bitsum.com) e rodar isto de novo.' Yellow
                Remove-Item $inst -Force -EA SilentlyContinue
            } else {
            Say 'Instalando (modo silencioso)...'
            # NAO usar -Wait aqui. O instalador da Bitsum em modo silencioso nao
            # encerra de forma confiavel: numa maquina real ele instalou o programa
            # (aparecia no menu Iniciar) e o processo continuou vivo, deixando o
            # script parado em "Instalando..." pra sempre. Em vez de confiar no
            # encerramento dele, espera pelo RESULTADO: o executavel aparecer em
            # disco. Isso e o que realmente indica que a instalacao terminou.
            Start-Process $inst -ArgumentList '/S'
            for ($i = 1; $i -le 24; $i++) {          # ate 2 minutos
                if (Test-Path $plExe) { break }
                Start-Sleep -Seconds 5
                if ($i -eq 6)  { Say '  ainda instalando... (normal, pode levar 1 min)' Gray }
                if ($i -eq 18) { Say '  demorando mais que o esperado. Se aparecer alguma janela de' Yellow
                                 Say '  instalacao atras desta, conclua ela.' Yellow }
            }
            if (Test-Path $plExe) {
                Say 'Process Lasso instalado.' Green
            } else {
                Say 'Nao consegui confirmar a instalacao em 2 minutos. Vou seguir e tentar' Yellow
                Say 'configurar de qualquer forma - se falhar, instale pelo site da Bitsum' Yellow
                Say 'e rode este script de novo (ele pula o download se ja estiver la).' Yellow
            }
            # o instalador pode ter ficado vivo mesmo tendo terminado o servico;
            # nao deixa processo orfao segurando o arquivo baixado
            Get-Process -Name 'processlasso_setup' -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
            $plInstaladoAgora = $true

            # O prolasso.ini NAO nasce com o instalador - quem cria e o proprio
            # Process Lasso na primeira execucao. Sem esperar por ele, o bloco de
            # configuracao abaixo seria pulado EM SILENCIO, e e justamente a etapa
            # de prioridade e ProBalance.
            Say 'Esperando o Process Lasso criar o arquivo de configuracao dele...' Gray
            for ($i = 1; $i -le 12; $i++) {
                $plIni = Find-ProlassoIni      # procura de novo a cada volta
                if ($plIni) { break }
                if ($i -eq 3 -and (Test-Path $plExe)) {
                    Say 'Abrindo o Process Lasso uma vez para ele gerar a config...' Gray
                    Start-Process $plExe
                }
                Start-Sleep -Seconds 5
            }

            if ($plIni) {
                Say ("Configuracao encontrada: $plIni") Green
            } else {
                Say ''
                Say 'ATENCAO: o Process Lasso foi instalado, mas o arquivo de configuracao' Red
                Say 'dele nao apareceu - entao isto NAO foi aplicado:' Red
                Say '  prioridade do jogo + divisao de nucleos + ajuste do ProBalance' Red
                Say ''
                Say 'O QUE FAZER: abra o Process Lasso, feche, e rode o LoLBoost de novo.' Yellow
                Say 'Na segunda vez ele pula o download e vai direto pra configuracao.' Yellow
            }
            }   # fecha o else da verificacao de assinatura
        } else {
            Say ''
            Say 'Pulado. Sem o Process Lasso, a prioridade do jogo e a divisao de' Yellow
            Say 'jogo NAO sao aplicadas.' Yellow
        }
    }

    if ($plIni -and (Test-Path $plIni)) {
        # A etapa 5 mexe na config de um programa que o usuario talvez use com
        # regras proprias, e (quando o PL ja estava instalado) nao havia NENHUMA
        # pergunta antes de reescrever o arquivo e matar o processo.
        Say ''
        Say 'Vou aplicar no Process Lasso, para o League of Legends:' White
        Say '  - classe de prioridade: Alta' White
        Say '  - exclusao do ProBalance (senao ele REBAIXA o jogo sozinho)' White
        Say ("  - nucleos que o jogo vai usar: " + $(if ($afinidade) { $afinidade } else { '(nao vou mexer)' })) White
        if ($null -eq $melhorCore -and $afinidade) {
            Say 'ATENCAO: voce pulou a medicao, entao essa divisao NAO foi medida' Yellow
            Say 'nesta maquina - e o palpite padrao.' Yellow
        }
        Say 'O Process Lasso vai ser fechado e reaberto (o servico sobrescreve o' Gray
        Say 'arquivo ao sair, entao nao da pra editar com ele rodando).' Gray
        if (-not (Ask 'Aplicar essas 3 coisas no Process Lasso?')) {
            Say 'Pulado - nada foi alterado no Process Lasso agora.' Yellow
            # Se uma execucao ANTERIOR ja aplicou, a restauracao tem que continuar
            # no DESFAZER: senao ele encolhe e deixa de reverter algo que segue
            # aplicado na maquina.
            if (Test-Path "$plIni.LoLBoost.bak") {
                Say '(uma execucao anterior ja aplicou; o DESFAZER continua cobrindo isso)' Gray
                $undo.Add("Get-Process ProcessLasso,ProcessGovernor -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue")
                $undo.Add("Start-Sleep -Seconds 3")
                $undo.Add("Copy-Item '$plIni.LoLBoost.bak' '$plIni' -Force -EA SilentlyContinue")
                $undo.Add("if (Test-Path '$plExe') { Start-Process '$plExe' }")
                GravaDesfazer
            }
            $plIni = $null
        }
    }

    if ($plIni -and (Test-Path $plIni)) {
        # Guarda do backup: sem ela, rodar duas vezes fazia o "backup" ser a versao
        # JA modificada, e o DESFAZER passava a restaurar o estado alterado.
        # (O game.cfg ja tinha essa guarda; aqui faltava.)
        $plBak = "$plIni.LoLBoost.bak"
        if (-not (Test-Path $plBak)) {
            Copy-Item $plIni $plBak -Force -EA SilentlyContinue
            Say ("copia de seguranca da configuracao: $plBak") Gray
        } else {
            Say ("copia de seguranca ja existia - preservada: $plBak") Gray
        }
        # O undo TEM que parar o Process Lasso antes de restaurar: o governor
        # sobrescreve o ini ao sair, o que anularia a restauracao.
        $undo.Add("Get-Process ProcessLasso,ProcessGovernor -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue")
        $undo.Add("Start-Sleep -Seconds 3")
        $undo.Add("Copy-Item '$plBak' '$plIni' -Force -EA SilentlyContinue")
        $undo.Add("if (Test-Path '$plExe') { Start-Process '$plExe' }")
        GravaDesfazer

        Get-Process -Name 'ProcessLasso','ProcessGovernor' -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
        Start-Sleep -Seconds 2

        # O prolasso.ini E seccionado (doc da Bitsum): OocExclusions vive em
        # [OutOfControlProcessRestraint] e os Default* em [ProcessDefaults].
        # A versao antiga desta funcao acrescentava a chave no FIM do arquivo
        # quando ela nao existia - o que numa instalacao nova joga a chave na
        # secao errada e o Process Lasso ignora SEM AVISAR.
        function SetIni($linhas, $secao, $chave, $valor) {
            $out    = New-Object System.Collections.Generic.List[string]
            $atual  = ''
            $feito  = $false
            $achou  = $false
            foreach ($l in $linhas) {
                if ($l -match '^\s*\[(.+)\]\s*$') {
                    if ($atual -eq $secao -and -not $feito) { $out.Add("$chave=$valor"); $feito = $true }
                    $atual = $Matches[1]
                    if ($atual -eq $secao) { $achou = $true }
                    $out.Add($l); continue
                }
                if ($atual -eq $secao -and $l -match ('^\s*' + [regex]::Escape($chave) + '\s*=')) {
                    if (-not $feito) { $out.Add("$chave=$valor"); $feito = $true }
                    continue    # descarta a linha antiga
                }
                $out.Add($l)
            }
            if ($atual -eq $secao -and -not $feito) { $out.Add("$chave=$valor"); $feito = $true }
            if (-not $achou) { $out.Add(''); $out.Add("[$secao]"); $out.Add("$chave=$valor") }
            return $out.ToArray()
        }

        # Le o valor atual de uma chave DENTRO da secao certa.
        function ValorIni($linhas, $secao, $chave) {
            $atual = ''
            foreach ($l in $linhas) {
                if ($l -match '^\s*\[(.+)\]\s*$') { $atual = $Matches[1]; continue }
                if ($atual -eq $secao -and $l -match ('^\s*' + [regex]::Escape($chave) + '\s*=\s*(.*)$')) {
                    return $Matches[1].Trim()
                }
            }
            return ''
        }

        # Mescla preservando as regras que o usuario JA tem. A doc da Bitsum define
        # essas chaves como UMA lista separada por virgula, com N campos por
        # processo:
        #   OocExclusions .......... proc                  (1 campo)
        #   DefaultPriorities ...... proc,prioridade       (2 campos)
        #   DefaultGPUPriorities ... proc,n                (2 campos)
        #   DefaultAffinitiesEx .... proc,0,mascara        (3 campos; mascara usa ';')
        # Antes a linha inteira era substituida, o que APAGAVA as regras que a
        # pessoa tinha para outros programas - e sem avisar. Justo com quem o
        # README chama pelo nome ("se voce instalou o Process Lasso...").
        function MesclaLista($valorAtual, $campos, $novoRegistro, $alvo) {
            $itens = @()
            if ($valorAtual) {
                $itens = @($valorAtual -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
            }
            $out = New-Object System.Collections.Generic.List[string]
            $removidos = 0
            for ($i = 0; $i -lt $itens.Count; $i += $campos) {
                $fim = [Math]::Min($i + $campos - 1, $itens.Count - 1)
                $reg = @($itens[$i..$fim])
                if ($reg[0] -and $reg[0].ToLower() -eq $alvo) { $removidos++; continue }
                foreach ($campo in $reg) { $out.Add($campo) }
            }
            foreach ($campo in ($novoRegistro -split ',')) { $out.Add($campo.Trim()) }
            return [pscustomobject]@{
                Valor      = ($out -join ',')
                Preservados = [int]([Math]::Floor((($out.Count - ($novoRegistro -split ',').Count)) / $campos))
                Removidos  = $removidos
            }
        }

        # detecta UMA vez e usa o mesmo encoding na leitura e na escrita
        $encIni = DetectaEncoding $plIni
        $ini    = [IO.File]::ReadAllLines($plIni, $encIni)
        $alvo   = 'league of legends.exe'
        $regras = @(
            @{ Secao='OutOfControlProcessRestraint'; Chave='OocExclusions';        Campos=1; Novo=$alvo },
            @{ Secao='ProcessDefaults';              Chave='DefaultPriorities';    Campos=2; Novo="$alvo,high" },
            @{ Secao='ProcessDefaults';              Chave='DefaultGPUPriorities'; Campos=2; Novo="$alvo,4" }
        )
        # Afinidade so entra se ela foi realmente calculada: em CPU hibrida, ou em
        # maquina de poucos nucleos onde o usuario respondeu N, escrever
        # "DefaultAffinitiesEx=league of legends.exe,0," seria regra vazia e sem sentido.
        if ($afinidade) {
            $regras += @{ Secao='ProcessDefaults'; Chave='DefaultAffinitiesEx'; Campos=3; Novo="$alvo,0,$afinidade" }
        }
        $totalPreservado = 0
        foreach ($r in $regras) {
            $atualVal = ValorIni $ini $r.Secao $r.Chave
            $m = MesclaLista $atualVal $r.Campos $r.Novo $alvo
            $ini = SetIni $ini $r.Secao $r.Chave $m.Valor
            $totalPreservado += $m.Preservados
            if ($m.Preservados -gt 0) { Say ("  $($r.Chave): preservadas $($m.Preservados) regra(s) suas") Gray }
        }
        EscreveIni $plIni $ini $encIni

        Say 'Process Lasso configurado:' Green
        Say '  - Prioridade Alta' Green
        Say '  - Excluido do ProBalance (senao ele REBAIXA o jogo sozinho)' Green
        if ($afinidade) { Say "  - Afinidade: $afinidade" Green }
        else            { Say '  - Afinidade: NAO aplicada (ver o motivo acima)' Yellow }
        if ($totalPreservado -gt 0) {
            Say ("  - suas regras para outros programas foram MANTIDAS ($totalPreservado no total)") Green
        }

        if (Test-Path $plExe) { Start-Process $plExe }
    }

    # o DESFAZER restaura o prolasso.ini, mas NAO desinstala o programa:
    # deixar isso explicito pra nao prometer "reverte tudo" e mentir
    if ($plInstaladoAgora) {
        $undo.Add("Write-Host ''")
        $undo.Add("Write-Host 'OBS: o Process Lasso foi INSTALADO pelo LoLBoost e continua instalado.' -ForegroundColor Yellow")
        $undo.Add("Write-Host 'Este script nao desinstala programas. Para remover: Configuracoes >' -ForegroundColor Yellow")
        $undo.Add("Write-Host 'Aplicativos > Process Lasso > Desinstalar.' -ForegroundColor Yellow")
        GravaDesfazer
}

# Rede de seguranca: se o benchmark matou o Process Lasso e nenhum caminho depois
# o religou (usuario recusou a configuracao, ini nao encontrado, etc), religa aqui.
# Deixar o programa morto suspende, em silencio, as regras que o usuario ja tinha.
if ($plEstavaRodando -and -not (Get-Process -Name 'ProcessLasso','ProcessGovernor' -EA SilentlyContinue)) {
    $exe = $plExe
    if (-not $exe) { $exe = 'C:\Program Files\Process Lasso\ProcessLasso.exe' }
    if (Test-Path $exe) {
        Start-Process $exe
        Say ''
        Say 'Process Lasso religado (o benchmark tinha fechado ele).' Green
    } else {
        Say ''
        Say 'AVISO: o Process Lasso foi fechado para o benchmark e nao consegui' Yellow
        Say 'religar. Abra ele na mao - sem ele rodando, nenhuma regra vale.' Yellow
    }
}

# =====================================================================
Title '6/6  SCRIPT DE DESFAZER'
# =====================================================================
# Ja foi gravado a cada alteracao (ver GravaDesfazer no topo). Esta chamada e so
# a final: se o script tivesse morrido no meio, o arquivo ja estaria em disco
# cobrindo tudo o que havia sido alterado ate ali.
GravaDesfazer
Say ''
Say 'SE ALGO FICAR PIOR OU ESTRANHO, e so um clique:' White
Say '  Area de Trabalho > "DESFAZER LoLBoost"' Green
Say ''
Say ("(o arquivo tambem esta em: " + $undoFile + ")") Gray
Say ("Acoes revertiveis registradas: " + $undo.Count) Gray

Title 'CONCLUIDO'
Say ''
Say 'REINICIE O PC para o driver grafico assumir o novo nucleo.' Yellow
Say ''
Say 'Depois de reiniciar, confira:' White
Say '  1. Process Lasso esta aberto (ele PRECISA estar rodando pra regra valer)' White
Say '  2. Monitor esta na taxa MAXIMA (Config > Tela > Video avancadas)' White
Say '  3. Riot Client: engrenagem > ao entrar em partida = "Fechar janela"' White
Say ''
Say 'Se algo der errado: rode o DESFAZER.ps1 e reinicie.' Gray
Say ''
Read-Host 'Enter para sair'
