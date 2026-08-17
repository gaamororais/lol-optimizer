# 06 — Histórico e decisões

Por que o projeto está do jeito que está. Cada decisão registrada com o motivo, incluindo as que
foram **revertidas** e as afirmações que se provaram erradas.

Isto existe porque a documentação de "o que a ferramenta faz" não conta a parte mais útil: **o que
quase deu errado e o que a gente aprendeu quando deu.**

---

## A correção mais importante: qual era o mecanismo principal

Durante boa parte do projeto, a documentação afirmava que o **maior ganho vinha do Process Lasso** —
mais especificamente, de remover a penalidade que o ProBalance aplicava ao jogo. O `docs/02` dizia
literalmente *"Process Lasso — o maior ganho (120 → 200 fps, +66%)"*, e o README foi construído em
cima disso.

**Estava errado.** Segundo quem operou a máquina, o que cravou os **200 fps estáveis** foi tirar o
driver de vídeo de cima do núcleo do jogo. A prioridade levantou a **média**; o FPS continuava
oscilando até a afinidade do driver entrar.

Por que isso importa muito mais do que parece:

| Mecanismo | Quem é afetado |
|---|---|
| Penalidade do ProBalance | **Só quem tem o Process Lasso mal configurado** — uma minoria |
| Driver disputando núcleo com o jogo | **Comportamento padrão do Windows** — quase todo mundo com placa dedicada |

Ancorar o projeto no caso raro fez o mecanismo universal virar rodapé. Pior: transformou a
comunicação num pedido de desculpas. A tabela de expectativa respondia *"pequeno, nenhum, pequeno,
pequeno"* para quase todo leitor — e ninguém roda um script depois de ler isso, com razão.

**Consertado:** o achado do driver virou o principal, o do ProBalance virou "achado extra" com
permissão explícita de pular, e a tabela passou a responder *"o que ele faz por você"* em vez de
*"quanto você ganha a menos que eu"*.

---

## Os dois incidentes em campo

O projeto passou por **três rodadas de revisão adversarial** antes de ser publicado, e saiu com
veredito de "pode divulgar". Na **primeira máquina de teste real** — i5-10400F, RTX 3060, Windows
10 — deu dois problemas seguidos, os dois em pontos que eu considerava testados.

### Incidente 1 — o driver de vídeo travou na primeira troca de núcleo

Tela preta, PC ligado, dono sem saber o que fazer. O risco estava documentado. O que **não** estava
previsto:

1. **A placa ficou presa num núcleo.** O benchmark fixa o driver em cada núcleo para testar e
   restaura no fim; morrendo no meio, deixa a última configuração aplicada. E o `DESFAZER` não cobria
   isso, porque quem escreveu no registro foi a ferramenta de terceiro. Foi preciso um comando manual
   para descobrir e limpar — e só foi descoberto porque alguém pensou em conferir.
2. **O aviso chegava tarde.** O texto dizia "se travar, reinicie o PC". A pessoa lê isso **antes**,
   esquece, e quando precisa está de frente para uma tela preta.

### Incidente 2 — o script travou para sempre em "Instalando..."

`Start-Process $inst -ArgumentList '/S' -Wait`. O instalador do Process Lasso em modo silencioso não
encerra de forma confiável: o programa instalou, apareceu no menu Iniciar, e o script ficou parado
indefinidamente esperando o processo sair.

**E eu tinha testado essa etapa.** Mas o teste usava `Start-Process` **sem** `-Wait`, com verificação
por tempo. O código publicado usava `-Wait`.

---

## A lição de raiz, que apareceu quatro vezes

Os dois incidentes, mais dois achados de revisão, são a **mesma classe de erro**:

| Onde | O que o teste exercitava | O que o código fazia |
|---|---|---|
| Testes de máscara de bits, CPU híbrida e GUID | Reimplementações locais no arquivo de teste | As funções do script |
| Teste manual do instalador | `Start-Process` sem `-Wait` | `Start-Process` com `-Wait` |
| `testar.ps1` inteiro | `ParseFile` descartando os erros de sintaxe | Um script que precisa compilar |
| Comentário do undo da placa | "Registrado ANTES do benchmark" | Registrado ~100 linhas **depois** |

O último é o mais desconfortável: **o comentário do código afirmava o oposto do que o código fazia**.
E o terceiro é o pior em consequência: com os erros de parse descartados, os 63 testes passariam
**todos verdes contra um script que morre na primeira linha em produção**.

> **Teste que não roda o código real não é teste, é ensaio.** Vale para o arquivo de testes, vale
> para o comando que se digita no PowerShell para "conferir se funciona", e vale para o comentário
> que descreve o que o código faz.

A resposta estrutural foi a **seção I** do `testar.ps1`: regras cobradas por AST, e não por memória.

| Regra trancada | De onde veio |
|---|---|
| Nenhum `Start-Process` com `-Wait` | Incidente 2 |
| Não **chama** `Restart-PnpDevice` | Não existe no Windows 10 |
| Nenhum `New-Item -Force` em chave de registro | 1ª revisão |
| Script é ASCII puro | Era promessa em comentário |
| Undo da placa aparece **antes** do benchmark | Incidente 1 |
| Regex de Intel num lugar só | 4ª revisão |

Detalhe que vale registrar: o teste do `Restart-PnpDevice` falhou na primeira tentativa porque pegou
o nome **num comentário** explicando por que não se usa. Corrigido para checar por AST — comentário
não é chamada. Teste que confunde texto com código é o mesmo erro de novo, em miniatura.

---

## A separação que mudou o desenho

Depois do incidente 1, ficou claro que o risco e o benefício estavam **no mesmo botão**:

| | O que é | Risco |
|---|---|---|
| **Separar** | Escrever no registro em qual núcleo o driver roda. **Não reinicia driver** — vale no boot seguinte | Nenhum |
| **Medir** | Descobrir qual núcleo é o melhor. Reinicia o driver uma vez por núcleo | Tela preta |

Quem recusava o benchmark — a escolha sensata em máquina que não pode ficar fora do ar — perdia
**também** a separação, que é o ganho principal. A etapa virou um menu de três opções, com a segura
como recomendada **e** como padrão de resposta não reconhecida.

---

## Decisões técnicas e o motivo de cada uma

| Decisão | Por quê |
|---|---|
| **Script em ASCII puro** | Em PowerShell 5.1, um acento no arquivo vira mojibake na tela de quem roda. Cobrado por teste |
| **`pnputil /restart-device`, não `Restart-PnpDevice`** | O cmdlet **não existe no Windows 10** (verificado no build 19045). Testar só em Windows 11 teria feito a recuperação falhar exatamente na máquina onde ela precisa funcionar |
| **Log em modo append** | A reação natural de quem viu dar errado é rodar de novo — e isso apagava a única evidência de por que falhou |
| **Log registra a resposta, não só a pergunta** | Recebi o log de uma execução que travou e não conseguia saber que caminho a pessoa tinha escolhido |
| **Estado original em `%LOCALAPPDATA%`, fora da pasta do script** | Quem apaga a pasta e baixa de novo perderia o registro dos valores originais, e a execução seguinte capturaria como "original" o que a primeira já tinha modificado |
| **Atalho do DESFAZER na Área de Trabalho** | Quem precisa dele está com pressa, e pode ser alguém cujo PC acabou de ficar pior. Criado desde a primeira alteração, e se apaga sozinho depois de reverter |
| **Mesclar o `prolasso.ini` em vez de sobrescrever** | As chaves são listas de vários processos numa linha. Sobrescrever apagaria as regras que a pessoa já tem — e isso pegaria em cheio justamente quem o README chama pelo nome |
| **Ranquear por 0.1% low, não por média** | Na medição real a média variou **2,9%** entre o melhor e o pior núcleo. Olhar a média teria concluído que não fazia diferença |
| **Não mexer em HVCI, UAC nem Secure Boot** | É segurança do sistema operacional. Decisão de quem usa a máquina, não efeito colateral de um script de FPS |
| **Não redistribuir binário de terceiro** | O repositório tem só dois arquivos de texto. As ferramentas são baixadas do site oficial de cada uma, com consentimento, e o instalador tem a assinatura digital conferida |

---

## Coisas que foram propostas e **descartadas**

Cortar escopo é decisão de projeto tanto quanto adicionar.

| Descartado | Por quê |
|---|---|
| Empacotar o script num `.exe` | SmartScreen e Defender tratam `.exe` novo sem assinatura que promete FPS como malware. E mataria o principal ativo do projeto: dois arquivos de texto que a pessoa pode ler antes de rodar |
| Ponto de restauração do sistema antes de mexer no registro | Lento, frequentemente desabilitado justo no PC fraco que é o público-alvo, e é bala de canhão para dois valores de registro. O DESFAZER cobre melhor |
| Tweaks clássicos de "otimizador" (MSI mode, timer resolution, core parking, desativar serviços) | É o gênero de que este projeto é o antídoto: evidência fraca, superfície de dano grande, e diluiria a identidade de "faz **uma** coisa, medida, com desfazer" |
| Auto-update do script ou da ferramenta de medição | O contrário do certo. Ferramenta que roda como administrador na máquina de outra pessoa não deve mudar de comportamento entre o teste do autor e o download do usuário — que é o erro de raiz deste projeto em outra roupa |
| Interface gráfica | O `.bat` mais script elevado é a superfície certa para o público. GUI multiplica estados que ninguém testa |
| A tabela de risco de ban no README | O projeto **não mexe** em nada daquilo. Listar cheat de terceiro coloca a ferramenta na vizinhança errada. Ficou no `docs/04`, que é o lugar dela |

---

## O que ainda está aberto

Ver [05-PENDENCIAS.md](05-PENDENCIAS.md) para a lista com estimativa. O resumo:

- **Nenhuma execução completou as 6 etapas** em máquina nenhuma. Os componentes foram validados
  individualmente; o fluxo inteiro, não. Estimativa honesta: **35–40% do risco do script mora em
  código que só uma máquina física exercita.**
- **A medição sem reiniciar o driver** é a próxima grande mudança, e eliminaria o único risco
  relevante que sobrou. Prova de conceito já feita — ver a seção abaixo.
- Suporte real a CPU híbrida via `GetSystemCpuSetInformation`.
- Detectar e informar o que **já está aplicado** ao rodar de novo, em vez de refazer em silêncio.

---

## A prova de conceito da medição sem risco

O caminho para eliminar o risco de tela preta: **medir a interferência por núcleo sem reiniciar
driver nenhum.**

A ideia não é emular o jogo. É medir a causa: prender uma tarefa de uma thread só em cada núcleo,
rodar um laço apertado e contar os **engasgos** em microssegundos. Toda interrupção que o Windows
atende naquele núcleo rouba tempo da tarefa e aparece como pico — que é o mesmo mecanismo que faz o
frame demorar no jogo.

Resultado da prova de conceito, num i7-10510U, em **5,6 segundos**:

```
CPU 0  ->  p99.99 = 55.612 us   <- pior
CPU 4  ->  p99.99 =  5.185 us   <- melhor
diferenca: 10.7x
```

A **CPU 0 sendo a pior é de livro**: por padrão o Windows direciona a maior parte das interrupções
para ela. É exatamente o núcleo a evitar — e agora dá para **provar** isso na máquina de quem roda,
sem baixar nada e sem risco.

**O que essa medição não é:** ela **não** mede FPS, e o número não pode ser apresentado como FPS. Ela
mede interferência, que é a causa. A prova final continua sendo no jogo.

---

## Nota de método

Este documento e os outros registram os erros junto com os acertos **de propósito**. Um projeto que
se apresenta como "medir, nunca assumir" tem obrigação de registrar quando falhou no próprio padrão —
e falhou, quatro vezes, sempre pelo mesmo motivo.

O valor do projeto não está no número de 200 fps. Está no método: **medir antes de mexer, deixar
tudo reversível, e escrever o que não funcionou.**
