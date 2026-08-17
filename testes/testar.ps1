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
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ps1, [ref]$null, [ref]$null)
$defs = @{}
$ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
    ForEach-Object { $defs[$_.Name] = $_.Extent.Text }
# O Invoke-Expression tem que rodar no escopo do SCRIPT: dentro de uma funcao, a
# funcao definida por ele morre quando aquela funcao retorna.
foreach ($f in 'SetIni','ValorIni','MesclaLista','MascaraAfinidade','EhCpuHibrida','GuidDoPlano','DetectaEncoding','LeIni','EscreveIni','LembraOriginal') {
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
Write-Host ''
if ($falhas -eq 0) {
    Write-Host "TODOS OS $total TESTES PASSARAM" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$falhas de $total TESTE(S) FALHARAM" -ForegroundColor Red
    exit 1
}
