# MSXCHAT — Fase 4: comunicação TCP/IP

Entrega de 27/10/2026. A Fase 3 foi considerada homologada no Expert por premissa do usuário. O usuário também confirmou conexão e eco corretos do TCPTEST.COM no Expert. Essa confirmação libera a integração prevista no escopo original: “Integrar somente com uma pilha comprovadamente funcional no MSX1”.

O novo MSXCHAT.COM inicia uma conexão TCP, envia o pedido JSON por HTTP e recebe a resposta diretamente do PC pela LAN. O SD permanece no MSX durante esse fluxo. O servidor desta fase fornece uma resposta manual de teste; não chama a OpenAI e não precisa de chave.

## Começar

Use a mesma pilha, ordem de instalação e ambiente nos quais TCPTEST funcionou. O cliente seleciona a implementação TCP/IP UNAPI de índice 1, como TCPTEST. Se houver várias implementações, confira com NETDIAG se a primeira ainda é a que foi validada. O aplicativo não instala nem configura INL/helper automaticamente.

1. Preserve o COM e faça backup dos arquivos do SD.
2. Copie somente o novo MSXCHAT.COM para a unidade/diretório habitual.
3. No PC, com Node.js 18+, inicie LAN-SERVER.cjs. Exemplo para PC 192.168.1.10 e Expert 192.168.1.50:
```
node LAN-SERVER.cjs --bind 192.168.1.10 --peer 192.168.1.50 --port 8765 --state C:/MSXCHAT-CACHE --reply "Resposta manual recebida pela LAN."
```
No Windows, RUN-LAN.cmd aceita os mesmos argumentos no lugar de node LAN-SERVER.cjs; procura Node no PATH e depois no runtime local do Codex.

4. Aguarde Listening. Permita a porta no firewall da LAN; não publique essa porta na internet.
5. No Expert, com a pilha TCP/IP já instalada:
```
MSXCHAT 192.168.1.10 8765
```
6. Digite a pergunta. Use Ctrl+Q para publicar o REQ e Ctrl+W para transmiti-lo.
7. O programa recebe o corpo em .RXT, fecha e valida, publica .RSP, grava .ACK e apresenta o texto. Ctrl+Y consulta pergunta/resposta.

Adapte os IPs ao seu laboratório; não atribua esses exemplos a equipamentos sem conferir a configuração existente. O IP deve ser numérico e privado (10/8, 172.16/12 ou 192.168/16); a porta deve estar entre 1 e 65535.

A pasta --state fica no PC, não é a unidade do cartão. Guarde-a entre execuções: ela permite repetir pedidos sem gerar outra resposta. Não compartilhe fisicamente o cartão com o PC durante a comunicação. A aplicação usa os arquivos do SD para persistência local e o TCP para intercâmbio.

## Modo offline e interface

```
MSXCHAT
```
Sem argumentos, o terminal continua offline. Argumentos inválidos são informados e impedem transmissão. O cabeçalho indica LAN CONFIG. quando os argumentos são válidos; isso informa configuração, não comprova conexão.

Os controles da Fase 3 permanecem (manual completo em MANUAL-BASE-FASE3.md):
- Ctrl+S grava; Ctrl+D restaura; Ctrl+Q publica; Ctrl+O importa RSP já presente.
- Ctrl+Y consulta histórico; setas/páginas navegam; Ctrl+F recupera pergunta em editor vazio.
- Ctrl+X duas vezes cancela localmente um pedido pendente.
- Ctrl+G ajuda; Ctrl+R fonte; Ctrl+L limpa editor; Esc encerra.

Novo: Ctrl+W transmite o pedido pendente. Se um RSP já existir, tenta importá-lo sem novo POST. Não publica nem apaga o editor automaticamente.

Durante uma transação, o vídeo do DOS é restaurado e aparece NET: connecting/sending/receiving. A interface gráfica volta ao terminar. Esc ou Ctrl+C interrompe a transação, preservando pergunta/editor e mantendo o pedido pendente. Outras teclas lidas durante a espera são descartadas. Esse cancelamento de transporte não cria CAN; para cancelar a pendência local use Ctrl+X após voltar à tela.

Ctrl+T continua controlando a procura periódica de arquivos de resposta. Não produz transmissões automáticas. A consulta ao histórico ignora Ctrl+W enquanto estiver aberta.

## Falhas, repetição e encerramento

Não há reenvio automático de POST. Em falha, confira servidor, cabo, endereço e mensagens. Ctrl+W tenta novamente com o mesmo REQ/ID. O servidor persiste a resposta antes de enviá-la e reproduz essa mesma resposta em novas tentativas equivalentes, inclusive após reiniciar.

O mesmo ID com conteúdo diferente recebe HTTP 409. O cache é separado por IP do MSX e ID; conversation_id continua fixo em 00000001. Para um novo conjunto independente de arquivos/IDs, use outra pasta --state. Não apague o cache para contornar um conflito sem identificar sua causa.

Timeout por etapa: 1200 ticks BIOS (20 s a 60 Hz ou 24 s a 50 Hz). Limite total verificado: 3600 ticks (60/72 s). Etapas incluem abertura, tentativas de enviar cada bloco, recepção e fechamento. São verificações cooperativas: uma rotina UNAPI ou DOS defeituosa que não retorna não pode ser preemptada. TCP_OPEN anunciado como bloqueante é recusado.

A mensagem de falha mostra três bytes HEX: categoria / erro UNAPI / erro de cleanup.

| Categoria | Significado |
|---|---|
| 01 | Interface, versão, capacidade ou helper indisponível |
| 03 | Falha de API ou estado TCP inesperado |
| 04 | Timeout |
| 05 | Esc ou Ctrl+C durante a transação |
| 06 | HTTP, tamanho, dados urgentes, fechamento prematuro ou framing inválido |
| 07 | Arquivo, escrita, fechamento ou publicação |
| 08 | JSON de resposta inválido ou sem associação correta ao pedido |

Erro UNAPI zero significa que não foi registrado um erro desse serviço. Erro de cleanup diferente de zero exige conferir a pilha. O programa só fecha/aborta a conexão que abriu, nunca usa número zero para encerrar todas. Se um abort falhar, mantém a propriedade da conexão; o próximo Ctrl+W primeiro repete a limpeza, sem abrir outra conexão. A saída tenta limpar novamente e informa no console se ainda falhar.

.RXT é provisório e não é importado na inicialização. Uma nova tentativa pode substituí-lo. O utilitário de backup foi atualizado para preservá-lo. Arquivos REQ, ID, RSP, ACK e CAN confirmados conservam as regras anteriores.

## Contrato HTTP suportado

POST fixo em /msxchat/v1/exchange, Content-Type application/json, Content-Length decimal e Connection: close. Corpo é o contrato local msxchat/1, não o formato público da OpenAI.

O cliente aceita HTTP/1.0 ou HTTP/1.1 com status 200, Content-Type application/json, um Content-Length entre 1 e 32767 e encerramento ordenado pelo servidor após o corpo. Reconhece nomes de campos sem distinguir caixa. Linha de cabeçalho limitada a 255 caracteres; cabeçalhos completos limitados a 2048 bytes. Recebe cabeçalhos e corpo fragmentados, sem supor correspondência entre TCP e mensagens HTTP.

Esta versão recusa redirecionamentos, outros status (inclusive 1xx), Transfer-Encoding, Content-Encoding, duplicação de Content-Length, LF isolado, corpo incompleto ou com bytes extras. Não é um cliente HTTP de uso geral; o servidor incluído produz o subconjunto exigido.

## Servidor de teste

--reply é texto manual e --error pode produzir um erro local de ensaio. Para enviar em partes:
```
node LAN-SERVER.cjs --bind 192.168.1.10 --peer 192.168.1.50 --port 8765 --state C:/MSXCHAT-CACHE --reply "Teste em partes." --fragment 17 --delay-ms 5
```
Escritas pequenas não garantem segmentos TCP separados; a fragmentação exata é verificada também nos testes do COM.

O servidor valida tamanho, protocolo e peer, aceita somente o endpoint indicado e não faz solicitações externas. A restrição por IP é um controle de acesso na LAN, não criptografia. Nenhuma chave de API é usada ou transportada. Arquivo de cache incompleto/inválido é preservado e causa 503 para aquele pedido; copie e investigue antes de alterá-lo.

## Montagem e testes

```
python -S build.py
node tests/test-msxchat.cjs
node tests/test-helper.cjs DIRETORIO_TEMPORARIO
python -S tests/test-backup.py DIRETORIO_TEMPORARIO
node tests/test-lan-server.cjs DIRETORIO_TEMPORARIO
node tests/test-lan-server.cjs DIRETORIO_TEMPORARIO --real
```
O último abre somente loopback no PC; não testa o Expert. Ferramentas e fontes completos estão incluídos. diagnostics contém os COM, fontes e instruções da Fase 0, preservados para comparação.

Resultado: 167 cenários do COM com DOS/BIOS/UNAPI/VRAM simulados; 18 testes do servidor com arquivos/streams; 19 na execução que inclui HTTP real em loopback; 12 do publicador e 16 do backup. Os 18 casos estão contidos nos 19, não são 37 casos distintos.

A Fase 4 ainda precisa de homologação do novo HTTP no Expert e em emulador MSX completo. O eco TCP informado pelo usuário comprova a condição de avanço, não a execução deste novo cliente. Use HOMOLOGACAO.csv. A Fase 5 integrará o gateway à API depois desse aceite.
