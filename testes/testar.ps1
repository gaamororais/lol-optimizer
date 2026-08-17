# =====================================================================
#  Testes do LoLBoost
#  Rode com:  powershell -ExecutionPolicy Bypass -File testes\testar.ps1
#
#  Nao altera NADA na maquina: as funcoes sao extraidas do LoLBoost.ps1
#  publicado (via AST, nao por regex de indentacao) e rodam contra dados em
#  memoria ou arquivos temporarios. Sai com codigo 1 se algo falhar.
#
#  Cobertura:
#    A) escrita ciente de secao no prolasso.ini
#    B) mesclagem que PRESERVA as regras que o usuario ja tem
#    C) leitura de valor dentro da secao certa (ValorIni)
#    D) mascara de bits da afinidade do driver
#    E) deteccao de CPU hibrida, inclusive sem Hyper-Threading
#    F) GUID do plano de energia em Windows nao-ingles
#    G) encoding: ida e volta sem corromper acento
# =====================================================================

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $PSCommandPath
$ps1  = Join-Path (Split-Path -Parent $raiz) 'LoLBoost\LoLBoost.ps1'
if (-not (Test-Path $ps1)) { throw "nao achei o LoLBoost.ps1 em $ps1" }

# ---- traz as funcoes do script PUBLICADO usando o parser do PowerShell ----
# Por AST em vez de regex: nao depende da indentacao do arquivo, entao limpar
# espacos no script nao quebra os testes em silencio.
# Os erros de parse TEM que ser capturados. Descartando eles (terceiro [ref]$null,
# como estava aqui), o AST ainda contem as funcoes mesmo se o script tiver erro de
# sintaxe - e os testes passariam todos verdes contra um LoLBoost.ps1 que morre na
# primeira linha em producao. Era a forma mais literal possivel de "testar um
# caminho diferente do que o codigo publicado faz".
$errosParse = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ps1, [ref]$null, [ref]$errosParse)
if ($errosParse -and $errosParse.Count -gt 0) {
    Write-Host "O LoLBoost.ps1 NAO COMPILA - $($errosParse.Count) erro(s) de sintaxe:" -ForegroundColor Red
    $errosParse | ForEach-Object { Write-Host ("  linha " + $_.Extent.StartLineNumber + ": " + $_.Message) -ForegroundColor Red }
    exit 1
}
$defs = @{}
$ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
    ForEach-Object { $defs[$_.Name] = $_.Extent.Text }
# O Invoke-Expression tem que rodar no escopo do SCRIPT: dentro de uma funcao, a
# funcao definida por ele morre quando aquela funcao retorna.
foreach ($f in 'SetIni','ValorIni','MesclaLista','MascaraAfinidade','EhCpuHibrida','EhIntelNova','GuidDoPlano','DetectaEncoding','LeIni','EscreveIni','LembraOriginal') {
    if (-not $defs.ContainsKey($f)) { throw "nao achei 'function $f' no LoLBoost.ps1" }
    Invoke-Expression $defs[$f]
}

$total = 0; $falhas = 0
function Checa($nome, $esperado, $obtido) {
    $script:total++
    if ($esperado -eq $obtido) { Write-Host ("  [OK]     $nome") -ForegroundColor Green }
    else {
        Write-Host ("  [FALHOU] $nome") -ForegroundColor Red
        Write-Host ("           esperado: $esperado") -ForegroundColor DarkGray
        Write-Host ("           obtido..: $obtido")   -ForegroundColor DarkGray
        $script:falhas++
    }
}
function Secao($t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }
function SecaoDaChave($linhas, $chave) {
    $sec = '(nenhuma)'
    foreach ($l in $linhas) {
        if ($l -match '^\s*\[(.+)\]\s*$') { $sec = $Matches[1]; continue }
        if ($l -match ('^\s*' + [regex]::Escape($chave) + '\s*=')) { return $sec }
    }
    return '(ausente)'
}

# =====================================================================
Secao 'A) escrita ciente de secao (SetIni)'
# =====================================================================
# OocExclusions tem que cair em [OutOfControlProcessRestraint] e as Default* em
# [ProcessDefaults]. Acrescentar no fim do arquivo joga na secao errada e o
# Process Lasso ignora sem avisar.

$r = SetIni @('[General]','Language=0','','[OutOfControlProcessRestraint]','OocEnabled=1','','[ProcessDefaults]','DefaultCPUSets=','','[GUI]','ShowTrayIcon=1') 'OutOfControlProcessRestraint' 'OocExclusions' 'lol.exe'
Checa 'chave ausente, secao no meio do arquivo' 'OutOfControlProcessRestraint' (SecaoDaChave $r 'OocExclusions')

$r = SetIni @('[OutOfControlProcessRestraint]','OocExclusions=notepad.exe') 'OutOfControlProcessRestraint' 'OocExclusions' 'lol.exe'
Checa 'chave existente: substitui no lugar' 'OutOfControlProcessRestraint' (SecaoDaChave $r 'OocExclusions')
Checa 'chave existente: nao duplica'        1 (@($r | Where-Object { $_ -match '^OocExclusions=' }).Count)

$r = SetIni @('[General]','Language=0') 'ProcessDefaults' 'DefaultPriorities' 'lol.exe,high'
Checa 'secao ausente: cria a secao' 'ProcessDefaults' (SecaoDaChave $r 'DefaultPriorities')

$r = SetIni @('[General]','Language=0','','[ProcessDefaults]','DefaultCPUSets=') 'ProcessDefaults' 'DefaultPriorities' 'lol.exe,high'
Checa 'secao alvo e a ULTIMA do arquivo' 'ProcessDefaults' (SecaoDaChave $r 'DefaultPriorities')

# o prolasso.ini real tem secoes DUPLICADAS: dois [ProcessDefaults], dois [Performance]
$iniDup = @('[ProcessDefaults]','DefaultPriorities=','','[Performance]','x=1','','[ProcessDefaults]','DefaultCPUSets=')
$r = SetIni $iniDup 'ProcessDefaults' 'DefaultPriorities' 'lol.exe,high'
Checa 'secoes duplicadas: nao duplica a chave' 1 (@($r | Where-Object { $_ -match '^DefaultPriorities=' }).Count)
Checa 'secoes duplicadas: total de linhas igual' $iniDup.Count $r.Count

# chave presente SO na segunda secao duplicada
$iniDup2 = @('[ProcessDefaults]','DefaultCPUSets=','','[GUI]','x=1','','[ProcessDefaults]','DefaultPriorities=antigo.exe,idle')
$r = SetIni $iniDup2 'ProcessDefaults' 'DefaultPriorities' 'lol.exe,high'
Checa 'chave so na 2a secao duplicada: nao duplica' 1 (@($r | Where-Object { $_ -match '^DefaultPriorities=' }).Count)
Checa 'chave so na 2a secao duplicada: fica em ProcessDefaults' 'ProcessDefaults' (SecaoDaChave $r 'DefaultPriorities')

$r = SetIni @('[ProcessDefaults]','  DefaultPriorities = velho.exe,idle') 'ProcessDefaults' 'DefaultPriorities' 'lol.exe,high'
Checa 'chave com espacos em volta do = e reconhecida' 1 (@($r | Where-Object { $_ -match '^DefaultPriorities=lol' }).Count)

# =====================================================================
Secao 'B) mesclagem preservando as regras do usuario (MesclaLista)'
# =====================================================================
# Essas chaves sao UMA lista separada por virgula com N campos por processo
# (doc da Bitsum). Trocar a linha inteira apagaria as regras que a pessoa tem
# para outros programas.
$alvo = 'league of legends.exe'

$m = MesclaLista '' 1 $alvo $alvo
Checa 'lista vazia (instalacao nova): escreve so a nossa' $alvo $m.Valor

$m = MesclaLista 'notepad.exe,calc.exe' 1 $alvo $alvo
Checa 'OocExclusions: preserva 2 e acrescenta' "notepad.exe,calc.exe,$alvo" $m.Valor
Checa 'OocExclusions: conta preservadas' 2 $m.Preservados

$m = MesclaLista 'obs64.exe,high,chrome.exe,below normal' 2 "$alvo,high" $alvo
Checa 'DefaultPriorities (2 campos): preserva os pares' "obs64.exe,high,chrome.exe,below normal,$alvo,high" $m.Valor
Checa 'DefaultPriorities: conta 2 preservadas' 2 $m.Preservados

$m = MesclaLista "obs64.exe,high,$alvo,idle,chrome.exe,idle" 2 "$alvo,high" $alvo
Checa 'regra nossa antiga e substituida, nao duplicada' "obs64.exe,high,chrome.exe,idle,$alvo,high" $m.Valor
Checa 'conta a remocao da regra antiga' 1 $m.Removidos

$m = MesclaLista "outro.exe,0,1;3,$alvo,0,9;9" 3 "$alvo,0,2;4;6" $alvo
Checa 'DefaultAffinitiesEx (3 campos, mascara com ;)' "outro.exe,0,1;3,$alvo,0,2;4;6" $m.Valor

# lista malformada (campos nao multiplos da aridade): nao pode PERDER dado do usuario
$m = MesclaLista 'obs64.exe,high,orfao.exe' 2 "$alvo,high" $alvo
Checa 'lista malformada: preserva tudo do usuario' "obs64.exe,high,orfao.exe,$alvo,high" $m.Valor

$m = MesclaLista 'MAIUSCULA.exe,high' 2 "$alvo,high" $alvo
Checa 'nome de outro programa em maiuscula e preservado' "MAIUSCULA.exe,high,$alvo,high" $m.Valor

$m = MesclaLista "LEAGUE OF LEGENDS.EXE,idle" 2 "$alvo,high" $alvo
Checa 'nossa regra antiga em MAIUSCULA tambem e removida' "$alvo,high" $m.Valor

# =====================================================================
Secao 'C) leitura de valor na secao certa (ValorIni)'
# =====================================================================
$iniV = @('[OutOfControlProcessRestraint]','OocExclusions=a.exe','','[ProcessDefaults]','DefaultPriorities=b.exe,high')
Checa 'le da secao certa'                    'a.exe'      (ValorIni $iniV 'OutOfControlProcessRestraint' 'OocExclusions')
Checa 'le da outra secao'                    'b.exe,high' (ValorIni $iniV 'ProcessDefaults' 'DefaultPriorities')
Checa 'chave inexistente devolve vazio'      ''           (ValorIni $iniV 'ProcessDefaults' 'NaoExiste')
Checa 'mesma chave em secao errada nao vaza' ''           (ValorIni $iniV 'ProcessDefaults' 'OocExclusions')
Checa 'chave na 2a secao duplicada'          'x.exe,idle' (ValorIni @('[ProcessDefaults]','Outra=1','','[GUI]','y=2','','[ProcessDefaults]','DefaultPriorities=x.exe,idle') 'ProcessDefaults' 'DefaultPriorities')

# =====================================================================
Secao 'D) mascara de bits da afinidade (MascaraAfinidade)'
# =====================================================================
function Hex($bytes) { return (($bytes | ForEach-Object { $_.ToString('x2') }) -join ' ') }
Checa 'CPU 0  -> 01'    '01'    (Hex (MascaraAfinidade 0))
Checa 'CPU 1  -> 02'    '02'    (Hex (MascaraAfinidade 1))
Checa 'CPU 7  -> 80'    '80'    (Hex (MascaraAfinidade 7))
Checa 'CPU 8  -> 00 01' '00 01' (Hex (MascaraAfinidade 8))
Checa 'CPU 15 -> 00 80' '00 80' (Hex (MascaraAfinidade 15))
Checa 'CPU 23 -> 00 00 80' '00 00 80' (Hex (MascaraAfinidade 23))

# =====================================================================
Secao 'E) deteccao de CPU hibrida (EhCpuHibrida)'
# =====================================================================
# A conta classica nao pegava hibrida SEM Hyper-Threading, e ai a afinidade
# rodava e podia prender o jogo nos E-cores.
Checa 'Ryzen 7 5700X (8C/16T) = uniforme'          $false (EhCpuHibrida 'AMD Ryzen 7 5700X 8-Core Processor' 8 16)
Checa 'i5-10400F (6C/12T) = uniforme'              $false (EhCpuHibrida 'Intel(R) Core(TM) i5-10400F CPU @ 2.90GHz' 6 12)
Checa 'i7-10510U (4C/8T) = uniforme'               $false (EhCpuHibrida 'Intel(R) Core(TM) i7-10510U CPU @ 1.80GHz' 4 8)
Checa 'i5-12600K (10C/16T) = guarda'               $true  (EhCpuHibrida '12th Gen Intel(R) Core(TM) i5-12600K' 10 16)
Checa 'Core Ultra 9 285K (24C/24T) = guarda'       $true  (EhCpuHibrida 'Intel(R) Core(TM) Ultra 9 285K' 24 24)
Checa '13700K com HT desligado (16C/16T) = guarda' $true  (EhCpuHibrida '13th Gen Intel(R) Core(TM) i7-13700K' 16 16)
Checa 'Xeon antigo sem HT (8C/8T) = uniforme'      $false (EhCpuHibrida 'Intel(R) Xeon(R) CPU E5-2670 0 @ 2.60GHz' 8 8)

# =====================================================================
Secao 'F) GUID do plano de energia em Windows nao-ingles (GuidDoPlano)'
# =====================================================================
# Extrair por posicao pegava "de" em portugues, e o DESFAZER saia com
# "powercfg -setactive de".
$g = '381b4222-f694-41f0-9685-ff5bb260df2e'
Checa 'pt-BR'                $g (GuidDoPlano "GUID do Esquema de Energia: $g  (Equilibrado)")
Checa 'en-US'                $g (GuidDoPlano "Power Scheme GUID: $g  (Balanced)")
Checa 'es-ES'                $g (GuidDoPlano "GUID de plan de energia: $g  (Equilibrado)")
Checa 'GUID em MAIUSCULA'    $g.ToUpper() (GuidDoPlano ("Power Scheme GUID: " + $g.ToUpper()))
Checa 'saida sem GUID = vazio' '' (GuidDoPlano 'nenhum plano ativo')

# =====================================================================
Secao 'G) encoding: ida e volta sem corromper acento'
# =====================================================================
# No PS 5.1, Get-Content sem -Encoding le UTF-8 sem BOM como ANSI (testado:
# "aplicacao.exe" com cedilha volta como mojibake) e Set-Content grava ANSI.
# Detectar so na escrita nao resolve: grava o mojibake de volta como UTF-8 e a
# corrupcao fica permanente.
$tmp = Join-Path $env:TEMP ("lolboost_teste_" + [IO.Path]::GetRandomFileName() + ".ini")
try {
    $linhasAcento = @('[ProcessDefaults]', 'DefaultPriorities=aplicação.exe,high')

    # UTF-8 sem BOM
    [IO.File]::WriteAllLines($tmp, [string[]]$linhasAcento, (New-Object System.Text.UTF8Encoding($false)))
    $lido = LeIni $tmp
    Checa 'UTF-8 sem BOM: leitura preserva o acento' 'DefaultPriorities=aplicação.exe,high' $lido[1]
    EscreveIni $tmp $lido $null
    Checa 'UTF-8 sem BOM: ida e volta identica' 'DefaultPriorities=aplicação.exe,high' (LeIni $tmp)[1]
    $b = [IO.File]::ReadAllBytes($tmp)
    Checa 'UTF-8 sem BOM: nao inventou BOM na volta' $false ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)

    # UTF-8 com BOM
    [IO.File]::WriteAllLines($tmp, [string[]]$linhasAcento, (New-Object System.Text.UTF8Encoding($true)))
    $lido = LeIni $tmp
    Checa 'UTF-8 com BOM: leitura preserva o acento' 'DefaultPriorities=aplicação.exe,high' $lido[1]
    EscreveIni $tmp $lido $null
    $b = [IO.File]::ReadAllBytes($tmp)
    Checa 'UTF-8 com BOM: mantem o BOM na volta' $true ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)

    # ANSI (o que o Process Lasso grava numa maquina pt-BR sem UTF-8)
    [IO.File]::WriteAllLines($tmp, [string[]]$linhasAcento, [System.Text.Encoding]::Default)
    $lido = LeIni $tmp
    Checa 'ANSI: leitura preserva o acento' 'DefaultPriorities=aplicação.exe,high' $lido[1]
    EscreveIni $tmp $lido $null
    Checa 'ANSI: ida e volta identica' 'DefaultPriorities=aplicação.exe,high' (LeIni $tmp)[1]
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

# =====================================================================
Secao 'H) estado original entre execucoes (LembraOriginal)'
# =====================================================================
# E o mecanismo que impede o pior bug de reversao: rodar o script 2x fazia ele
# capturar como "valor anterior" o que ELE MESMO escreveu na 1a rodada, e o
# DESFAZER passava a restaurar o estado ja modificado reportando sucesso.
# A funcao usa $estado e $estadoFile do escopo de quem chama - por isso da pra
# testar redefinindo os dois aqui.
$estadoFile = Join-Path $env:TEMP ("lolboost_estado_" + [IO.Path]::GetRandomFileName() + ".json")
try {
    $estado = @{}

    # 1a execucao: guarda o valor original
    Checa 'primeira chamada devolve o valor passado' 1 (LembraOriginal 'gdvr' 1)
    # 2a execucao: o script leria 0 (o que ele mesmo gravou) - tem que ignorar
    Checa 'segunda chamada IGNORA o valor novo e devolve o original' 1 (LembraOriginal 'gdvr' 0)
    Checa 'arquivo de estado foi criado' $true (Test-Path $estadoFile)

    # $null tem que ser lembrado COMO null (valor nao existia no registro)
    $r = LembraOriginal 'ausente' $null
    Checa 'valor originalmente ausente e lembrado como null' $true ($null -eq $r)
    Checa 'nao recaptura depois: continua null' $true ($null -eq (LembraOriginal 'ausente' 99))

    Checa 'false e lembrado como false (nao virou "vazio")' $false (LembraOriginal 'criou' $false)
    Checa 'nao recaptura o false' $false (LembraOriginal 'criou' $true)

    # simula processo novo: recarrega do disco, como o script faz no inicio
    $estado = @{}
    (Get-Content $estadoFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $estado[$_.Name] = $_.Value }
    Checa 'apos recarregar do disco: inteiro preservado'    1     (LembraOriginal 'gdvr' 0)
    Checa 'apos recarregar do disco: null preservado'       $true ($null -eq (LembraOriginal 'ausente' 99))
    Checa 'apos recarregar do disco: false preservado'      $false (LembraOriginal 'criou' $true)
    Checa 'apos recarregar: string de bytes preservada' '1,2,3' (LembraOriginal 'afin_set' '1,2,3')

    # JSON invalido: tem que degradar como "primeira execucao", nao explodir
    Set-Content -Path $estadoFile -Value '{ isso nao e json' -Encoding UTF8
    $estado = @{}
    try {
        (Get-Content $estadoFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $estado[$_.Name] = $_.Value }
    } catch { }
    Checa 'JSON corrompido: trata como primeira execucao' 7 (LembraOriginal 'gdvr' 7)
} finally {
    Remove-Item $estadoFile -Force -ErrorAction SilentlyContinue
}

# =====================================================================
Secao 'I) regras estruturais do script publicado (as licoes dos incidentes)'
# =====================================================================
# Estes testes nao exercitam funcoes: eles cobram REGRAS sobre o arquivo publicado,
# usando o AST. Existem porque as duas falhas em campo tiveram a mesma raiz - uma
# regra que eu "sabia" e o codigo nao cumpria. Regra que ninguem cobra volta.

$fonte = Get-Content $ps1 -Raw

# 1. Nenhum Start-Process com -Wait. Foi o incidente 2: o instalador em modo
#    silencioso nao encerra, e -Wait deixou o script preso pra sempre.
$comWait = $ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and
    $n.GetCommandName() -eq 'Start-Process' -and
    ($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Wait' })
}, $true)
Checa 'nenhum Start-Process usa -Wait (incidente 2)' 0 $comWait.Count

# 2. Restart-PnpDevice nao pode ser CHAMADO: nao existe no Windows 10, e a
#    recuperacao automatica falharia exatamente na maquina onde ela precisa
#    funcionar. Checagem por AST, e nao por texto: o script MENCIONA o nome num
#    comentario, explicando por que nao usa - e comentario nao e chamada.
$chamaRestartPnp = $ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and
    $n.GetCommandName() -eq 'Restart-PnpDevice'
}, $true)
Checa 'nao CHAMA Restart-PnpDevice (nao existe no Win10)' 0 $chamaRestartPnp.Count

# 3. New-Item -Force em caminho de registro apaga valores e subchaves da chave
#    existente. Só pode aparecer dentro da GaranteChave, que protege com Test-Path.
$newItemRegistro = $ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and
    $n.GetCommandName() -eq 'New-Item' -and
    $n.Extent.Text -match 'HKLM|HKCU'
}, $true)
Checa 'nenhum New-Item -Force direto em chave de registro' 0 $newItemRegistro.Count

# 4. O script tem que ser ASCII puro: em PowerShell 5.1 um acento no arquivo vira
#    mojibake na tela de quem roda. Hoje isso era promessa em comentario.
$bytes = [IO.File]::ReadAllBytes($ps1)
$altos = 0
foreach ($b in $bytes) { if ($b -ge 0x80) { $altos++ } }
Checa 'script e ASCII puro (nenhum byte >= 0x80)' 0 $altos

# 5. A limpeza da placa TEM que entrar no DESFAZER antes de a medicao comecar. Se o
#    script morrer durante a medicao, o unico socorro e o arquivo que ja esta em
#    disco. Esta e a licao do incidente 1, travada por ordem no arquivo.
$posUndoPlaca = $fonte.IndexOf("AssignmentSetOverride -Force -EA SilentlyContinue")
$posBench     = $fonte.IndexOf('Start-Process -FilePath $agaExe')
Checa 'undo da placa e registrado ANTES de iniciar a medicao' $true (($posUndoPlaca -gt 0) -and ($posBench -gt 0) -and ($posUndoPlaca -lt $posBench))

# 6. O marcador da camada 2 tem que ser escrito antes da medicao tambem.
$posMarcador = $fonte.IndexOf('Set-Content -Path $marcadorBench')
Checa 'marcador de recuperacao e escrito ANTES da medicao' $true (($posMarcador -gt 0) -and ($posMarcador -lt $posBench))

# 7. O regex de Intel nova vive num lugar so (senao guarda e mensagem divergem).
$ocorrencias = ([regex]::Matches($fonte, '1\[2-9\]th Gen')).Count
Checa 'regex de Intel nova aparece uma unica vez no arquivo' 1 $ocorrencias

# =====================================================================
Secao 'J) deteccao de Intel nova (EhIntelNova)'
# =====================================================================
Checa 'i5-12600K'            $true  (EhIntelNova '12th Gen Intel(R) Core(TM) i5-12600K')
Checa 'Core Ultra 9 285K'    $true  (EhIntelNova 'Intel(R) Core(TM) Ultra 9 285K')
Checa 'Core 5 120U (Series1)' $true (EhIntelNova 'Intel(R) Core(TM) 5 120U')
Checa 'Core 7 240H (Series2)' $true (EhIntelNova 'Intel(R) Core(TM) 7 240H')
Checa 'i5-10400F NAO e nova' $false (EhIntelNova 'Intel(R) Core(TM) i5-10400F CPU @ 2.90GHz')
Checa 'Ryzen NAO e Intel'    $false (EhIntelNova 'AMD Ryzen 7 5700X 8-Core Processor')

# =====================================================================
Secao 'K) o DESFAZER gerado precisa ser PowerShell valido'
# =====================================================================
# GravaDesfazer monta codigo por concatenacao de string. Caminho com apostrofo
# (usuario "D'Avila") ou com espaco geraria um arquivo que nao parseia - e ninguem
# descobre isso ate precisar dele.
$tmpDir = Join-Path $env:TEMP ("lolboost_undo_" + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force $tmpDir | Out-Null
try {
    $undoFile       = Join-Path $tmpDir 'DESFAZER.ps1'
    $atalhoDesfazer = Join-Path $tmpDir 'atalho.bat'
    $undo = New-Object System.Collections.Generic.List[string]
    $undo.Add("Copy-Item 'C:\Caminho Com Espaco\game.cfg.bak' 'C:\Caminho Com Espaco\game.cfg' -Force")
    $undo.Add("Set-ItemProperty 'HKCU:\System\GameConfigStore' GameDVR_Enabled 1")
    $undo.Add("powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e")
    $undo.Add("Set-ItemProperty 'HKLM:\SYSTEM\Teste' AssignmentSetOverride ([byte[]]@(2,0)) -Type Binary")
    foreach ($f in 'GravaDesfazer') {
        if (-not $defs.ContainsKey($f)) { throw "nao achei 'function $f'" }
        Invoke-Expression $defs[$f]
    }
    GravaDesfazer
    Checa 'DESFAZER.ps1 foi gerado' $true (Test-Path $undoFile)
    $errUndo = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($undoFile, [ref]$null, [ref]$errUndo)
    Checa 'DESFAZER.ps1 gerado e PowerShell valido' 0 $(if ($errUndo) { $errUndo.Count } else { 0 })
    Checa 'DESFAZER.ps1 exige administrador' $true ((Get-Content $undoFile -Raw) -match 'IsInRole')
} finally {
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

# =====================================================================
Write-Host ''
if ($falhas -eq 0) {
    Write-Host "TODOS OS $total TESTES PASSARAM" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$falhas de $total TESTE(S) FALHARAM" -ForegroundColor Red
    exit 1
}
