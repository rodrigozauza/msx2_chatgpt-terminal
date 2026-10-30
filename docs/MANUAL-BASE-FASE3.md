# MSXCHAT — Fase 3: histórico e interface completa

Entrega de 27/10/2026. A homologação da Fase 2 no Expert foi aceita como premissa informada pelo usuário. Esta entrega implementa o marco seguinte do escopo original: consulta às perguntas e respostas, paginação, reutilização de perguntas, cancelamento local, backup e rotação.

O programa continua offline. Nenhum texto desta demonstração foi produzido pela API. A implementação de transporte TCP/IP pertence à Fase 4 e exige os resultados próprios do diagnóstico de rede; homologar o MSXCHAT offline não comprova a pilha TCP/IP.

## Instalação

1. Faça cópia do conteúdo do cartão. Preserve o COM da Fase 2.
2. Substitua somente MSXCHAT.COM pelo desta entrega, na unidade/diretório usado anteriormente. No DOS1, use a raiz; DOS2/Nextor usam o diretório corrente. Os arquivos válidos da Fase 2 são reconhecidos diretamente.
3. Execute MSXCHAT. O rascunho e os pedidos são recuperados do SD. Abra o histórico com Ctrl+Y.
4. Para teste limpo, use outro diretório ou mídia de ensaio. Não copie examples sobre um histórico real.

Não volte à Fase 2 sobre dados que receberam cancelamento .CAN: a versão anterior não conhece esse estado e poderá considerar o pedido pendente. Para voltar de versão, use a cópia feita antes da atualização.

## Controles do terminal/editor

| Tecla | Ação |
|---|---|
| Ctrl+Y | Abrir o histórico |
| Ctrl+S | Gravar rascunho |
| Ctrl+Q | Publicar pedido JSON, sem limpar o editor |
| Ctrl+O | Procurar resposta do pedido pendente |
| Ctrl+D | Restaurar rascunho; substitui o editor somente após leitura válida |
| Ctrl+B | Rever a última resposta reconhecida no terminal |
| Ctrl+X, Ctrl+X | Confirmar cancelamento local do pedido pendente |
| Ctrl+T | Alternar procura automática |
| Ctrl+G | Ajuda |
| Ctrl+R / Ctrl+P | Calibrar fonte / prévia local do editor |
| Ctrl+L | Limpar editor |
| Setas / Home ou Ctrl+A / Ctrl+E | Mover / início / fim da linha lógica |
| Enter / Backspace / Delete | Nova linha / apagar |
| Esc | Sair, restaurando vídeo |

Editor multilinha com 2047 bytes MSX, quebra em 64 colunas, quatro linhas visíveis e rolagem até o cursor. Ctrl+X precisa ser pressionado duas vezes consecutivas; outra tecla desarma a confirmação e executa sua função normal. Esc fora do histórico encerra o programa. Esc não grava alterações automaticamente.

## Controles dentro do histórico

| Tecla | Ação |
|---|---|
| Esquerda / direita | Pedido anterior / seguinte, pulando reservas sem REQ |
| Cima / baixo | Rolar uma linha |
| Ctrl+U / Ctrl+N | Rolar uma página de 16 linhas |
| Home ou Ctrl+A / Ctrl+E | Topo / fim do pedido |
| Ctrl+F | Copiar a pergunta para um editor vazio |
| Esc ou Ctrl+Y | Voltar ao terminal, sem encerrar |

O cabeçalho informa ID, linha superior/total em hexadecimal e estado. A numeração de linha começa em zero; o total é uma contagem. USER e CHATGPT / RESPOSTA LOCAL distinguem as partes. Uma resposta só entra na consulta depois de recibo válido, com response_id e error_code conferidos contra o RSP. Pendentes e cancelados mostram a pergunta, sem consumir uma resposta tardia.

Perguntas/recibos/respostas inválidos são sinalizados. Texto parcial ou resposta com associação divergente não é mostrado. A consulta é somente leitura: não produz ACK, não cancela, não reenvia e não grava rascunho.

O editor permanece protegido enquanto você navega; digitação, limpeza e envio são ignorados nesse modo. Ctrl+F recusa substituir texto existente. Para reutilizar uma pergunta: saia da consulta, preserve o texto atual com Ctrl+S se necessário, limpe com Ctrl+L, abra a consulta e use Ctrl+F. A cópia ainda precisa de Ctrl+Q para virar novo pedido, com novo ID.

A conversa local 00000001 continua entre execuções. Nesta fase há uma conversa por conjunto de arquivos; não existe seletor de várias conversas nem envio de contexto a um modelo.

## Fluxo offline de teste

1. Digite e use Ctrl+Q. O programa publica, por exemplo, 00000001.REQ.
2. Saia com Esc e transfira o cartão ao PC.
3. Com Node.js 18+ execute:
```
node make-response.cjs X:/00000001.REQ --text "Resposta de teste manual."
```
4. Retorne o cartão ao Expert, execute MSXCHAT e use Ctrl+O.
5. Abra Ctrl+Y para consultar pergunta e resposta. Saia e reinicie para conferir persistência e ausência de ACK duplicado.

A procura automática atua somente em pedido pendente, a cada 600 ticks (cerca de 10 s a 60 Hz ou 12 s a 50 Hz). Ela pausa enquanto o histórico ou a confirmação de cancelamento estão abertos. Falha de leitura/validação a desliga; Ctrl+O permite tentar manualmente.

Cada E/S restaura temporariamente o vídeo do DOS e depois redesenha SCREEN 2. A alternância pode ser visível. Erros nativos de mídia continuam sob controle do DOS; Abort pode encerrar o processo e perder alterações ainda não gravadas em RAM.

## Cancelamento

A confirmação grava e fecha .CNT, reabre e valida, depois renomeia para .CAN e descarrega buffers. Somente então o pedido deixa de ser pendente. Falha mantém o pedido pendente e o editor preservado. .CNT incompleto é ignorado na inicialização.

A reserva .ID e o .REQ permanecem. Cancelamento é local e persistente; não apaga a pergunta e não é um comando de cancelamento enviado a servidor. Uma resposta posterior fica no disco para inspeção, sem ser importada. .CAN e .ACK para o mesmo pedido são conflito e bloqueiam a fila.

## Backup e controle de crescimento

O utilitário history-backup.py usa Python 3 e biblioteca padrão no PC. Feche MSXCHAT e use a mídia exclusivamente no PC durante o procedimento. Guarde o ZIP em outro disco/local de backup, usando um nome novo:
```
python -S history-backup.py backup X:/ C:/Backups/MSX-20261027.zip
python -S history-backup.py verify C:/Backups/MSX-20261027.zip
```
Sem --rotate, nenhum arquivo do cartão é removido. O backup inclui somente os nomes conhecidos do protocolo, incluindo rascunhos e arquivos provisórios para recuperação. Arquivos de outros programas ficam fora dele.

Para reduzir o histórico consultável no cartão, após a validação das regras do protocolo:
```
python -S history-backup.py backup X:/ C:/Backups/MSX-rotacao-01.zip --rotate --keep 20
```
Essa opção é explícita: cria um ZIP novo, fecha/sincroniza, verifica CRC e SHA-256 e só depois remove os arquivos dos pedidos concluídos ou cancelados mais antigos, preservando os 20 terminais mais recentes. Pendentes, rascunhos e todas as reservas .ID permanecem. Registro inválido impede rotação; ainda é possível fazer backup sem rotação para análise.

O REQ é removido primeiro em cada grupo. Se a limpeza for interrompida, a ausência dele impede reviver um pedido antigo como pendente. Restos de RSP/ACK/CAN podem permanecer; o ZIP verificado conserva os dados. Não há promessa de resistência física a falhas de controlador/energia. Conserve cópias independentes do ZIP.

Para restaurar, use um diretório novo ou vazio:
```
python -S history-backup.py restore C:/Backups/MSX-20261027.zip C:/MSX-Restaurado
```
O utilitário recusa diretório com conteúdo e verifica o arquivo antes de extrair. Não mescla snapshots com o cartão ativo nem sobrescreve arquivos existentes. A restauração é um snapshot daquele instante; revise os arquivos antes de decidir substituí-los no cartão. Para consultar um período antigo, pode-se usar a cópia restaurada em uma mídia de ensaio.

A rotação reduz o conteúdo das mensagens e parte das entradas de diretório. As reservas continuam crescendo, o intervalo de IDs continua limitado a 00000001–0000FFFF e a busca inicial é sequencial. Portanto não há histórico infinito nem renumeração automática. No DOS1 também existe limite de entradas da raiz; planeje um novo conjunto de dados antes de esgotá-las.

## Compilar e validar

```
python -S build.py
node tests/test-msxchat.cjs
node tests/test-helper.cjs
python -S tests/test-backup.py
```
Os dois últimos testes aceitam diretório temporário alternativo como argumento. As ferramentas não precisam de rede ou pacotes adicionais.

Foram executados 100 testes do COM em CPU Z80 com DOS/BIOS/VRAM simulados, 12 do publicador offline e 16 de backup/rotação com arquivos reais no PC. Não houve teste desta fase em Expert físico ou emulador MSX completo. Use HOMOLOGACAO.csv para o aceite no equipamento.

Consulte ARQUITETURA.md, PROTOCOLO.md, COMPATIBILIDADE.md, TESTES.md, FONTES.md e os resultados JSON. Código Assembly completo em src; montagem, mapa e listagem incluídos.
