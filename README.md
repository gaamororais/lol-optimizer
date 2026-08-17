# LoLBoost

***Português** · [English](README.en.md)*

**De 90–120 fps, com quedas repentinas para 60, para 200 fps no League of Legends.**

Na mesma máquina que rodava jogos AAA em 4K no ultra sem engasgar. Não era PC fraco, não era falta
de hardware, e não era Windows mal configurado — **era o LoL**, mais duas coisas que estavam
trabalhando contra ele.

**A máquina onde isso foi medido, pra você comparar com a sua:**

| | |
|---|---|
| **Processador** | AMD Ryzen 7 5700X (8 núcleos / 16 threads) |
| **Placa de vídeo** | AMD Radeon RX 9070 XT |
| **Memória** | 32 GB (2×16 GB, DDR4-3200) |
| **Placa-mãe** | MSI MPG B550 Gaming Plus |
| **Jogando em** | 1080p, configurações no mínimo |

Ou seja: **hardware muito acima do que o LoL precisa** — e mesmo assim o jogo não passava de 90–120
fps. É justamente esse contraste que mostra que o problema não era falta de PC.

> ### ⚠️ Leia isto antes de baixar: pode não servir pra você
>
> Isto **não é um "otimizador de FPS"**. Ele resolve **um** problema específico: quando o
> processador tem um núcleo lotado enquanto a placa de vídeo está de bobeira.
>
> Se o seu PC **não tem placa de vídeo dedicada** — ou seja, usa o vídeo que vem junto com o
> processador — o mais provável é que o seu limite seja a placa, e **não** o processador. Nesse caso
> nada aqui vai te dar 200 fps, e eu não vou fingir que vai.
>
> **[Como saber em 2 minutos em qual caso você está](#isto-serve-pra-mim)** — vale mais que qualquer
> coisa que eu escreva aqui.

---

## Índice

- [O problema, em 30 segundos](#o-problema-em-30-segundos)
- [**Isto serve pra mim?**](#isto-serve-pra-mim)
- [O achado principal: o driver de vídeo estava no mesmo núcleo do jogo](#o-achado-principal-o-driver-de-vídeo-estava-no-mesmo-núcleo-do-jogo)
- [O achado extra: o programa de otimização estava atrapalhando](#o-achado-extra-o-programa-de-otimização-estava-atrapalhando)
- [Como usar](#como-usar)
- [O que ele mexe na sua máquina](#o-que-ele-mexe-na-sua-máquina)
- [Quanto esperar de ganho](#quanto-esperar-de-ganho)
- [Isso dá ban?](#isso-dá-ban)
- [Casos em que ele se segura](#casos-em-que-ele-se-segura)
- [Documentação e testes](#documentação-e-testes)

---

## O problema, em 30 segundos

Um processador moderno tem vários **núcleos** — pense em cada um como um trabalhador. Quanto mais
trabalhadores, mais coisas o PC faz ao mesmo tempo.

O problema é que o League **faz quase todo o trabalho pesado em um único núcleo**. A Riot já
confirmou isso publicamente. Então não importa se você tem 8 ou 16: o jogo depende de **um**, e
quando esse um lota, o FPS cai — mesmo com todos os outros de braços cruzados.

Foi exatamente isso que apareceu no monitoramento de uma partida real de 29 minutos. O número de
cada núcleo é quanto ele estava ocupado:

```
#0:59%  #1:45%  #2:74%  #3:87%  #4:28%  #5:28%  #6:65%  #7:65%
#8:32%  #9:31%  #10:54% #11:53% #12:38% #13:37% #14:68%  #15:99%  ← ESSE aqui, lotado
```

**Um núcleo em 99% enquanto a placa de vídeo estava em 10%.** A placa não tinha o que fazer: o
serviço estava empilhado num só trabalhador.

É por isso que um jogo pesado em 4K roda liso e o LoL não. No jogo pesado quem trabalha é a placa de
vídeo. No LoL quem trabalha é **um** núcleo do processador. São problemas **opostos** — e foi essa
confusão que fez o diagnóstico demorar semanas.

E é por isso que baixar gráficos não resolvia: **a placa já estava de bobeira.** Piorava a imagem
sem devolver FPS nenhum.

> **Sendo honesto sobre o que esse monitoramento prova:** ele mostra qual **núcleo** lotou, não qual
> programa lotou ele. Que a carga fosse do League é a explicação de longe mais provável — era o
> único jogo aberto, e a Riot confirma que o jogo é assim — mas isso não é a mesma coisa que ter
> medido. Fica registrado como suposição bem fundamentada, não como fato provado.

---

## Isto serve pra mim?

Dois minutos, e você não precisa instalar nada pra descobrir:

1. Aperte `Ctrl` + `Shift` + `Esc` para abrir o **Gerenciador de Tarefas**
2. Vá na aba **Desempenho**
3. Entre numa partida e jogue até uma **briga grande de late game** (o momento mais pesado do jogo)
4. Volte no Gerenciador e olhe **CPU** e **GPU** ao mesmo tempo

| O que você vê | O que significa | Este projeto ajuda? |
|---|---|---|
| **GPU baixa** (10–40%) e no processador **um núcleo estourado** enquanto os outros estão tranquilos | É exatamente o problema que este projeto resolve | **Sim** |
| **GPU em 95–100%** | Seu limite é a placa de vídeo, não o processador | **Não.** Baixar resolução e qualidade gráfica é o que vai te dar FPS. Comece por aí |
| Processador e placa os dois tranquilos, e o FPS travado num número redondo (60, 120, 144) | Provavelmente é um limitador ligado, ou a taxa do seu monitor | **Não.** Confira isso primeiro, é de graça e resolve na hora |

> **Para ver núcleo por núcleo:** clique com o botão direito no gráfico de CPU → *Alterar gráfico
> para* → *Processadores lógicos*. Em vez de um gráfico só, aparecem vários quadradinhos — um por
> núcleo. É aí que o núcleo lotado fica óbvio.

---

## O achado principal: o driver de vídeo estava no mesmo núcleo do jogo

Aqui está a parte que quase ninguém conta: **a placa de vídeo também dá trabalho ao processador.**
Não é só a placa trabalhando sozinha — cada quadro que ela desenha passa por um pedaço do driver, que
roda no processador. E esse pedaço tem que rodar em **algum** núcleo.

Por padrão, o Windows não coordena isso com nada. Ele coloca o trabalho do driver onde der — e aqui
ele estava caindo **exatamente no núcleo que o jogo já estava lotando.** Dois inquilinos no único
quarto cheio da casa, enquanto sete quartos estavam vazios.

Pior: quando eu medi os 16 núcleos um por um, o núcleo onde o driver estava era o **pior da máquina**
nos momentos de engasgo — quase 3× pior que o melhor.

**Tirar o driver de lá foi o que cravou os 200 fps.** Não "200 de média oscilando": 200 firme.

E é por isso que este script **mede** em vez de mandar você copiar número: qual núcleo está livre e
qual está atrapalhando **muda de PC para PC**. Copiar a configuração que funcionou na minha máquina
pode colocar o seu driver justamente no pior núcleo do seu processador.

> Isso não é gambiarra nem truque: é uma opção que o próprio Windows oferece para dizer em qual
> núcleo o trabalho de um dispositivo deve rodar. Ela existe justo para casos assim. O que o Windows
> não faz é **descobrir sozinho** qual é o melhor — e ninguém nunca tinha dito a ele.

---

## O achado extra: o programa de otimização estava atrapalhando

Esta parte só interessa a você **se você usa algum otimizador** que mexa em prioridade de programa.
Se não usa, **pode pular** — o achado principal é o de cima, e ele não depende disto.

O **Process Lasso** é um programa popular de otimização do Windows — aparece em praticamente todo
guia de "como ganhar FPS". Ele serve pra controlar quanta atenção o Windows dá para cada programa.

Ele tem um recurso ligado de fábrica chamado **ProBalance**, que faz o seguinte: quando um programa
começa a consumir muito processador, o ProBalance **diminui a prioridade dele** para o resto do
Windows continuar respondendo bem.

A intenção é boa. O problema é óbvio quando alguém aponta:

> **Jogo consome muito processador por natureza. Então o ProBalance diminuía a prioridade do jogo.**

O programa instalado para o jogo andar mais rápido estava fazendo o jogo andar mais devagar. E não
era discreto — dava para ver na tela dele, escrito **"Restringido"** na frente do League of Legends.

Pior: colocar a prioridade do jogo em "Alta" **não resolve**. O ProBalance derruba de novo. Você tem
que dizer para ele, explicitamente, "deixa esse programa em paz".

**Nenhum guia que eu consultei avisa disso.** Nem o [PC-Tuning do valleyofdoom](https://github.com/valleyofdoom/PC-Tuning),
que é a referência da área — ele não cita League of Legends, Process Lasso nem ProBalance em lugar
nenhum.

Vale registrar o tamanho disso com honestidade: **soltar esse freio levantou a média**, mas o que
deixou o FPS **firme** foi o achado principal, o do driver. São dois problemas diferentes, e a maioria
das pessoas só tem o segundo.

> **Se você não usa Process Lasso, nada disso está acontecendo com você** — e o script instala e
> configura o programa do jeito certo, sem criar o problema. O achado principal continua valendo
> integralmente pra você.

---

## Como usar

### Antes de começar

- **Windows 10 ou 11**
- **Uma conta de administrador** do PC (o script pede a confirmação do Windows)
- **Uns 15 minutos**, dos quais 10 são só o script medindo sozinho
- **League of Legends e Riot Client fechados.** Se o jogo estiver aberto, ele desfaz a edição do
  arquivo de configuração quando fecha — o script detecta isso e avisa

### 1. Feche o jogo de verdade

Confira na bandeja do lado do relógio se não sobrou nada da Riot rodando.

### 2. Abra o PowerShell como administrador

Menu Iniciar → digite `powershell` → clique com o botão direito → **Executar como administrador** →
**Sim** na janela de confirmação do Windows.

### 3. Cole um comando

Este baixa e já executa. Você não precisa ter mais nada instalado:

```powershell
irm https://github.com/gaamororais/lol-optimizer/archive/refs/heads/main.zip -OutFile "$env:TEMP\lolboost.zip"; Expand-Archive "$env:TEMP\lolboost.zip" "$env:LOCALAPPDATA" -Force; & "$env:LOCALAPPDATA\lol-optimizer-main\LoLBoost\LoLBoost.bat"
```

**Prefere clicar em vez de colar comando?** Botão verde **`Code`** aqui em cima →
**`Download ZIP`** → extraia → entre na pasta `LoLBoost` → botão direito em **`LoLBoost.bat`** →
**Executar como administrador**.

Os arquivos ficam numa pasta do seu usuário, e o script de desfazer é gerado ali junto. Para rodar de
novo depois, é o mesmo comando.

### 4. Vai perguntando, você vai respondendo

São 6 etapas. Ele **pergunta antes de tudo que não é trivial**, e você pode responder **N** (não) em
qualquer uma — o resto continua. As perguntas são em português, e `S` é o sim.

| Etapa | O que acontece |
|---|---|
| **1** | Vê que hardware você tem, e te pergunta se a sua placa de vídeo é dedicada ou é a do processador |
| **2** | Ajustes simples e reversíveis: desliga a gravação de tela em segundo plano do Windows, coloca o plano de energia em Alto Desempenho, e ajusta o arquivo de configuração do jogo |
| **3** | Separa o driver de vídeo do núcleo do jogo. **Aqui você escolhe entre 3 opções** — explicado abaixo |
| **4** | Aplica essa separação |
| **5** | Configura o Process Lasso: prioridade Alta pro jogo, e "deixa esse em paz" no ProBalance |
| **6** | Escreve o desfazer e cria o atalho na Área de Trabalho |

### A escolha da etapa 3, que é a única com risco

São **duas coisas diferentes**, e o script te deixa escolher quanto quer:

- **Separar** o driver do núcleo do jogo → é de onde vem o ganho. **Não reinicia nada**, só passa a
  valer no próximo boot. Risco zero.
- **Medir** qual núcleo é o melhor → refinamento em cima da separação. Exige **reiniciar o driver de
  vídeo uma vez por núcleo**, e é aqui que mora todo o risco.

```
[1] SEPARAR SEM MEDIR  - recomendado. Sem risco, a tela nao pisca.
[2] MEDIR E SEPARAR    - o ideal, se voce topa o risco.
[3] NAO FAZER NADA AQUI
```

> ### ⚠️ Se você escolher a opção 2, a tela vai piscar e pode ficar preta
>
> É esperado: pra medir cada núcleo, o driver de vídeo é reiniciado. **Não mexa no PC durante essa
> parte.**
>
> **Existe risco real do driver travar e não voltar** — isso já aconteceu numa máquina testada, e o
> dono ficou sem imagem até desligar no botão. Não é risco teórico.
>
> **Se a tela ficar preta:** aperte `Win`+`Ctrl`+`Shift`+`B` (reinicia o driver de vídeo). Não
> voltou? Troque o cabo de porta na placa. Não voltou? Segure o power 10 s e ligue de novo.
>
> **O script se recupera sozinho.** Se ele perceber que a medição empacou, ele encerra, limpa a
> configuração que ela deixou na sua placa e tenta trazer o vídeo de volta. E se o PC precisar ser
> desligado no botão, na próxima vez que você abrir o script ele detecta que a medição anterior não
> terminou e **limpa automaticamente**, sem você precisar fazer nada.
>
> Ainda assim: **a opção 1 é recomendada**, e não é consolo. Ela entrega a separação — que é o ganho
> principal — com risco zero. A medição só melhora a escolha do núcleo.

### 5. Reinicie o PC

Obrigatório. A mudança do driver de vídeo só passa a valer depois de reiniciar.

### 6. Depois de reiniciar, confira 3 coisas

1. **O Process Lasso está aberto?** Ele precisa estar rodando pra valer. Se um dia o FPS cair do
   nada, é a primeira coisa a olhar.
2. **Seu monitor está na taxa máxima dele?** Configurações → Sistema → Tela → Configurações de vídeo
   avançadas. Ter monitor de 144 ou 240 Hz e o Windows em 60 joga tudo isso no lixo.
3. **No Riot Client**, na engrenagem: ao entrar em partida, marque **"Fechar janela"**. O client
   continua consumindo processador atrás do jogo se ficar aberto.

### Se quiser desfazer

**Tem um atalho na sua Área de Trabalho chamado `DESFAZER LoLBoost`.** Dois cliques nele, aceite a
confirmação do Windows, e ele reverte tudo. Depois reinicie o PC.

Ele é criado **junto com a primeira mudança**, não no fim — então mesmo que o script pare no meio por
qualquer motivo, o atalho já está lá e já cobre o que foi mexido até ali. E ele se apaga sozinho
depois de reverter, pra não ficar lixo na sua Área de Trabalho.

O arquivo de verdade é o `DESFAZER.ps1`, na mesma pasta do script, se você preferir rodar de lá.

Ele desfaz tudo o que o script mudou. A única coisa que ele **não** faz é desinstalar o Process
Lasso, caso o script tenha instalado pra você — isso você remove em Configurações → Aplicativos,
como qualquer programa.

---

## O que ele mexe na sua máquina

Sem letra miúda. Tudo aqui é reversível pelo `DESFAZER.ps1`:

| O que ele muda | Por quê |
|---|---|
| Desliga a **gravação de tela em segundo plano** do Windows (GameDVR) | Fica gravando os últimos segundos sem você pedir, consumindo processador |
| Coloca o plano de energia em **Alto Desempenho** | Evita o Windows economizar energia no meio da partida. Se a sua máquina não tiver essa opção, ele avisa e segue |
| Ajusta o **arquivo de configuração do jogo** | Desliga animações e efeitos que não mudam nada competitivo. Ele faz uma cópia de segurança antes |
| Diz ao Windows **em quais núcleos o driver de vídeo pode rodar** | Pra ele parar de dividir núcleo com o jogo. É o resultado da medição da etapa 3 |
| Diz ao Windows **em quais núcleos o jogo pode rodar** | Pra ficar longe do núcleo do driver |
| Configura o **Process Lasso** | Prioridade Alta e a exclusão do ProBalance |

> Um aviso específico: o ajuste do arquivo de configuração **desliga a gravação de replay** das suas
> partidas (os arquivos `.rofl`). Se você usa replay, o script te avisa na tela como voltar isso.

### O que ele baixa da internet

Este repositório **não contém programa de ninguém** — só dois arquivos de texto que você pode ler
antes de rodar. Durante a execução, e **só se você autorizar**, ele baixa duas ferramentas, cada uma
do site oficial dela:

- **AutoGpuAffinity** — a ferramenta que mede os núcleos. Baixada direto do GitHub do autor.
- **Process Lasso** — baixado do site da Bitsum, e **só se você ainda não tiver**. O script confere a
  assinatura digital do instalador antes de executar, e pergunta de novo se ela não estiver válida.

Se você responder **não** para as duas, o script ainda faz os ajustes da etapa 2 e gera o desfazer.

### Sobre o Process Lasso ser pago

**Ele é pago** (licença única, não é mensalidade). Mas **a versão gratuita cobre tudo o que este
script usa** — a [própria Bitsum lista](https://bitsum.com/howfree/) prioridade, núcleos e ProBalance
como recursos livres, e diz que a maioria das pessoas pode usar o programa indefinidamente sem
restrição.

A única condição deles: **uso comercial exige compra.** Se você joga em casa, o gratuito cobre. Se é
máquina de trabalho ou de lan house, compre a licença.

### O que ele se recusa a fazer

- **Não desliga proteção do Windows.** Nada de mexer em UAC, Secure Boot ou Integridade de Memória.
  São configurações de **segurança** — decisão sua, não efeito colateral de um script de FPS.
- **Não instala nada sem perguntar.**
- **Não copia configuração de outra máquina.** Esse é o erro mais comum dos guias da internet: mandar
  você copiar os números que funcionaram no PC de outra pessoa. Pode piorar o seu FPS.

Isso é o oposto do que fazem os pacotes de "otimização" vendidos por aí. Um deles, que eu analisei
durante o diagnóstico, **desligava o UAC** — e o botão de "reverter" dele não religava.

---

## Quanto esperar de ganho

### De onde veio o resultado, em ordem de importância

**1. Tirar o driver de vídeo de cima do núcleo do jogo.** Foi isto que cravou os **200 fps
estáveis**. É a parte principal do projeto, e é a que o script **mede na sua máquina** — porque qual
núcleo está livre e qual está atrapalhando muda de PC para PC.

**2. Dar prioridade alta ao jogo.** Isso levantou a média. Numa máquina onde algum programa esteja
segurando o jogo, essa parte rende mais ainda.

**3. O resto** — desligar a gravação em segundo plano, plano de energia, arquivo de configuração.
São migalhas, mas de graça.

O item 1 é o que importa aqui, e ele **não depende de você ter nada instalado nem configurado
errado**. Depende de o seu driver de vídeo estar disputando núcleo com o jogo — o que é o
comportamento **padrão** do Windows, porque ninguém nunca disse a ele para fazer diferente.

### O que este script faz por você

| Sua situação | O que ele faz |
|---|---|
| **Você tem placa de vídeo dedicada** — a maioria dos PCs que jogam LoL | **Faz a parte principal.** Mede os seus núcleos um por um e tira o driver de vídeo de cima do núcleo do jogo. Aqui isso foi a diferença entre "200 na média, oscilando" e **200 cravado** |
| **Você usa Process Lasso** (ou qualquer otimizador que mexa em prioridade) | Além do principal, tem uma chance real de existir um **freio ativo** no seu jogo agora. [Checagem de 10 segundos](#se-você-já-usa-process-lasso-faça-esta-checagem) — se for o seu caso, some um ganho a mais |
| **Vídeo integrado, ou GPU em 95–100% no jogo** | Aqui eu não vou te vender nada: **o seu limite é a placa de vídeo**, e mexer em núcleo não levanta esse teto. [O que fazer no seu caso](#isto-serve-pra-mim) |
| **Processador com 4 núcleos ou menos** | Faz a medição e a prioridade, mas **pergunta antes** de reservar um núcleo — com poucos núcleos, ceder um pode custar mais do que rende |
| **Processador Intel de 12ª geração ou mais novo** | Faz a prioridade e o resto, mas **não mexe nos núcleos** — [por segurança, e o motivo é bom](#casos-em-que-ele-se-segura) |

O ponto que amarra: **o script mede antes de mexer.** Ele te mostra o ranking dos seus núcleos na
tela, e você vê com os próprios olhos se existe diferença na sua máquina ou não. Se não existir, ele
te diz — em vez de aplicar uma receita e você ficar na dúvida se funcionou.

### Se você já usa Process Lasso, faça esta checagem

Com o **jogo aberto**, abra o Process Lasso e ache o `League of Legends.exe` na lista dele:

- Se aparecer **"Restringido"** na coluna *Status* → tem uma penalidade sendo aplicada no seu jogo
  agora mesmo. **Você ganha isso a mais**, somado ao principal.
- Se **não aparecer nada** ali → você não tem essa penalidade. Sobra a parte dos núcleos, que ajuda
  mais nas quedas do que na média.

Outro sinal do mesmo problema: a prioridade aparecendo como **`Alto(a)-`**, com um tracinho no fim.
Esse traço é o próprio Process Lasso dizendo que ele rebaixou o jogo.

> ⚠️ **Atenção se você for instalar o Process Lasso por conta própria:** o ProBalance vem **ligado de
> fábrica**. Instalar e deixar como veio é **criar** o problema descrito aqui. O script já configura
> a exclusão do jogo na mesma execução — mas se você fizer na mão, não esqueça dessa parte.

### E o que ele não faz em nenhum caso

Isto **não transforma o seu processador em outro**. Briga de 10 campeões em late game é o momento
mais pesado do jogo, e o FPS cai ali em qualquer PC. O que segura FPS alto até nesse momento são
processadores com um tipo de memória extra embutida (os modelos **X3D** da AMD, tipo 5700X3D ou
9800X3D) — o LoL é um dos jogos que mais ganha com eles.

O objetivo aqui é te colocar **no teto do PC que você já tem**, não acima dele. E se o seu caso for
um dos "pequeno" da tabela: **ganho pequeno é ganho.** O que não vale é você esperar 200 fps, receber
15, e achar que foi enganado — por isso está tudo escrito antes de você baixar.

---

## Isso dá ban?

Pergunta legítima, porque o League usa o **Vanguard**, um anti-cheat que roda bem no fundo do
Windows e é rígido com qualquer coisa que toque no jogo.

**Nada aqui toca no jogo.** Não substitui arquivo do jogo, não injeta código dentro dele, não roda
junto com ele, e não interfere no anti-cheat. O que este script faz é conversar com o **Windows**,
usando as opções oficiais que o próprio Windows oferece: prioridade de programa, distribuição de
núcleos, e uma configuração de dispositivo. É a mesma categoria de coisa que mudar o plano de
energia.

Em termos técnicos, para quem quiser o detalhe: **as ferramentas usadas aqui não injetam código no
processo do jogo.** O AutoGpuAffinity altera afinidade de dispositivo no registro do Windows, e o
Process Lasso usa as APIs oficiais do Windows de prioridade e afinidade. Nenhum dos dois toca em
arquivo do jogo.

Se você tem dúvida sobre outras coisas que costumam ser recomendadas por aí — trocar arquivos do
jogo, mods de skin, programas que se enfiam dentro do processo — o
[doc 04](docs/04-METODO-E-LICOES.md) tem a lista do que foi verificado e o risco de cada um. **Este
projeto não faz nenhuma delas**, e por isso elas não estão descritas aqui.

---

## Casos em que ele se segura

Duas situações em que o script **de propósito** faz menos do que poderia, porque errar aqui custa
mais que acertar:

**Processador Intel de 12ª geração ou mais novo.** Esses processadores misturam núcleos rápidos e
núcleos lentos de economia no mesmo chip. Se o script mandasse o jogo para os lentos por engano, seu
FPS **cairia pela metade** — e distinguir um do outro com segurança exige uma técnica que ainda não
está implementada. Então ele **não mexe nos núcleos** nesses processadores, e faz só o resto. Você
deixa de ganhar um pouco, mas não perde nada.

**Processador com 4 núcleos ou poucos núcleos.** A ideia de reservar um núcleo inteiro pro driver de
vídeo foi medida num processador de 8 núcleos, onde isso custa 12% do total. Em um de 4, custa 25% —
e ninguém mediu se compensa. O script te pergunta e **recomenda não**.

Nos dois casos, prioridade e ProBalance continuam sendo aplicados normalmente. É a parte que mais
rende, e ela não depende de nada disso.

---

## Documentação e testes

Tudo o que está afirmado aqui está registrado — **incluindo os erros cometidos** e a evidência que
derrubou cada palpite errado no caminho:

| Documento | Sobre |
|---|---|
| [01-HARDWARE.md](docs/01-HARDWARE.md) | A máquina e tudo que foi medido nela |
| [02-CASO-LOL.md](docs/02-CASO-LOL.md) | O caso completo: o monitoramento da partida, a medição dos 16 núcleos, a pesquisa |
| [03-COMO-FUNCIONA-O-LOLBOOST.md](docs/03-COMO-FUNCIONA-O-LOLBOOST.md) | O script por dentro, pra quem quiser ler o código com contexto |
| [04-METODO-E-LICOES.md](docs/04-METODO-E-LICOES.md) | O método, o que se provou **placebo**, e o que dá ban de verdade |
| [05-PENDENCIAS.md](docs/05-PENDENCIAS.md) | O que ainda não foi feito, e quanto se espera de cada coisa |

A pasta [`exemplo/`](exemplo/) tem os resultados **desta** máquina, pra você ver que formato esperar —
**não são valores pra copiar.** Foi medido em cima de 1.058.139 quadros de imagem.

E o detalhe que resume a filosofia do projeto: naquela medição, a **média** de todos os núcleos
variou só 2,9% entre o melhor e o pior. Se eu tivesse olhado a média, teria concluído que não fazia
diferença nenhuma. A diferença estava nos **piores momentos** — o pior núcleo era quase 3× pior que o
melhor exatamente nos engasgos, que é o que a gente sente jogando. **Olhar a métrica errada quase
matou a descoberta.**

Os testes ficam em [`testes/testar.ps1`](testes/testar.ps1) — 63 verificações que rodam sem alterar
nada na sua máquina:

```bash
powershell -ExecutionPolicy Bypass -File testes/testar.ps1
```

---

## Quem fez

Gabriel — jogo LoL e faço vídeos sobre o jogo no
**[@pingumonosylas](https://www.youtube.com/@pingumonosylas)**. Este projeto saiu de um problema meu
que eu não conseguia aceitar como "PC fraco".

Se o script te ajudou, passa lá. E se **não** ajudou, também vale comentar — saber em que máquina não
funcionou é o que faz a próxima versão ser melhor.

### Ferramentas usadas

- [AutoGpuAffinity](https://github.com/valleyofdoom/AutoGpuAffinity) — valleyofdoom (GPL-3.0)
- [Process Lasso](https://bitsum.com/) — Bitsum
- [PresentMon](https://github.com/GameTechDev/PresentMon) — Intel

Licença: [MIT](LICENSE). Sem vínculo com a Riot Games nem com a Bitsum. Use por sua conta e risco.
