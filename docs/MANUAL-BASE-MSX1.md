# MSXCHAT — Fase 5: gateway HTTPS para OpenAI

Entrega de 27/10/2026. A Fase 4 foi considerada homologada no Expert por premissa expressa do usuário. Foi implementada a integração: Expert → TCP/HTTP na LAN → gateway no PC → HTTPS Responses API → JSON local → SD/tela.

O novo COM e o gateway estão produzidos e testados localmente. Não houve chamada autenticada real à OpenAI: OPENAI_API_KEY não estava configurada e o usuário preferiu configurar OPENAI_MODEL no PC depois. O teste ponta a ponta com conta/modelo reais e Expert permanece pendente.

## Arquivos

- MSXCHAT.COM: versão 0.5; reconhece HTTP 202 e consulta periodicamente o mesmo pedido.
- GATEWAY.cjs: servidor de produção desta fase.
- OPENAI-CLIENT.cjs: adaptador HTTPS, endpoint oficial fixo.
- GATEWAY-STORE.cjs: diário de pedidos, chamadas e resultados; contexto da conversa.
- RUN-GATEWAY.cmd: iniciador Windows, procura Node no PATH e no runtime local do Codex.
- LAN-SERVER.cjs / RUN-LAN.cmd: servidor manual de teste preservado; não chama a API.
- make-response.cjs / history-backup.py: fluxo offline e manutenção anteriores.
- src, tools, tests: fontes completos, ferramentas e testes. Manuais anteriores preservados como MANUAL-BASE-FASE4.md e MANUAL-BASE-FASE3.md.

## Configurar o PC

Use Node.js 18+ e uma chave da API com acesso ao modelo escolhido. Nenhum modelo é selecionado automaticamente: OPENAI_MODEL é obrigatório, conforme sua preferência.

Na pasta extraída, abra PowerShell. Digite a chave em um prompt mascarado:
```powershell
$msxKey = Read-Host 'Chave da API OpenAI' -AsSecureString
$env:OPENAI_API_KEY = ([System.Net.NetworkCredential]::new('', $msxKey)).Password
Remove-Variable msxKey
$env:OPENAI_MODEL = 'ID_DO_MODELO_COM_ACESSO'
.\RUN-GATEWAY.cmd --check-config
```
Substitua ID_DO_MODELO_COM_ACESSO pelo ID efetivo de um modelo compatível com Responses. O último comando verifica a configuração local, sem chamar a API, e não imprime a chave. Ele não comprova acesso ao modelo na sua conta.

A chave não é argumento de linha de comando, não deve ir para o SD, para o COM ou para arquivos do pacote. O gateway lê a variável somente no PC e a envia como Authorization exclusivamente na conexão HTTPS com api.openai.com. Não desative a verificação TLS. Diagnósticos NODE_DEBUG de HTTP são recusados para evitar exposição de cabeçalhos.

Inicie o gateway com os endereços reais da sua LAN. Exemplo: PC 192.168.1.10 e Expert 192.168.1.50:
```powershell
.\RUN-GATEWAY.cmd --bind 192.168.1.10 --peer 192.168.1.50 --port 8765 --state C:/MSXCHAT-OPENAI
```
A pasta --state deve ser nova/vazia na primeira execução e ficará somente no PC. Não use a pasta de cache do servidor manual da Fase 4. Guarde a mesma pasta entre execuções: ela contém o contexto e impede repetir chamadas. O gateway aceita somente o peer configurado; ambos os IPs devem ser privados. Libere a porta no firewall da LAN e não a encaminhe para a internet.

No Linux, configure as mesmas variáveis no ambiente do processo e execute node GATEWAY.cjs com os mesmos argumentos. Não há instalação de SDK ou pacote: são usadas as bibliotecas padrão do Node.

## Usar no Expert

1. Preserve os dados e substitua somente MSXCHAT.COM.
2. Mantenha a pilha TCP/IP no ambiente já homologado.
3. Execute:
```
MSXCHAT 192.168.1.10 8765
```
4. Digite a pergunta. Ctrl+Q publica o REQ; Ctrl+W inicia o intercâmbio.
5. O gateway reserva o pedido e responde 202 enquanto trabalha. O terminal mostra Processando e mantém editor/pedido.
6. Com a consulta automática ligada, verifica o mesmo pedido a cada 600 ticks (10 s a 60 Hz ou 12 s a 50 Hz). Ctrl+W consulta manualmente; Ctrl+T alterna a consulta.
7. Quando pronto, recebe HTTP 200 com o envelope local, valida RXT, publica RSP, confirma ACK e mostra a resposta. Ctrl+Y consulta o histórico.

A consulta de um pedido já reservado não cria outra chamada à API. Depois de reiniciar o MSX, use Ctrl+W uma vez para recuperar o resultado/estado do pedido pendente; a consulta automática de rede é reativada somente após receber 202.

Se uma consulta de rede falhar, o programa preserva o pedido e interrompe as novas tentativas automáticas de rede. Corrija a causa e use Ctrl+W. O modo offline sem argumentos e os atalhos anteriores permanecem disponíveis.

## Cancelamento e erros

Esc ou Ctrl+C durante transporte interrompe a espera/conexão local. Não cancela nem garante interromper uma chamada já iniciada no PC; ela pode gerar uso cobrado. Ctrl+X duas vezes cancela a pendência local depois de voltar à interface. Um novo pedido tem outro ID. Se o PC concluir um pedido cancelado apenas no MSX, esse turno pode participar do contexto seguinte: o cancelamento local não é transmitido como cancelamento da API.

A categoria HEX 09 indica processamento no gateway; normalmente aparece como mensagem própria, sem erro. Categorias 01/03/04/05/06/07/08 mantêm os significados da Fase 4. Se a limpeza da conexão falhar, o programa informa o problema em vez de mostrar apenas Processando.

Erros da API retornam como envelope local state=error e error_code, são persistidos e reconhecidos com ACK. O editor permanece. O mesmo ID reproduz esse erro, não refaz a chamada. Após corrigir chave/modelo/cota, publique uma nova pergunta com novo ID para uma nova tentativa explícita.

Exemplos:
| Código | Ação |
|---|---|
| E_API_AUTH / E_API_ACCESS | Conferir chave, projeto e acesso no PC |
| E_API_MODEL / E_API_REQUEST | Conferir ID do modelo e opções compatíveis |
| E_API_RATE | Conferir cota/limites antes de novo pedido |
| E_API_TIMEOUT / E_API_NETWORK | Resultado pode ser incerto; não há retry automático |
| E_OUTPUT_LIMIT | API não completou a resposta; texto parcial é marcado |
| E_REFUSAL / E_EMPTY | Recusa ou ausência de texto utilizável |
| E_AMBIGUOUS | Há registro de envio sem resultado após interrupção; investigar no PC |
| E_STATE / HTTP 503 | Preservar o diário e inspecionar arquivos antes de alterar |
| HTTP 409 | ID com conteúdo diferente, ID antigo desconhecido ou conflito de ordem |

## Continuidade e limites

O gateway monta o contexto no PC: até oito pares anteriores de pergunta/resposta bem-sucedida, limitados a 16000 caracteres Unicode de histórico, mais a pergunta atual. Não envia um arquivo JSON inteiro do histórico MSX à API e não usa previous_response_id. Solicita store=false; isso não é uma promessa geral sobre todas as políticas de retenção do serviço.

A conversa local continua sendo 00000001 por conjunto de dados/peer. O contexto real da API começa na nova pasta do gateway; os ensaios manuais/offline anteriores permanecem no SD, mas não são importados automaticamente como diálogo do modelo. Reiniciar o gateway com a mesma pasta conserva a continuidade.

A resposta do MSX tem até 2047 valores escalares Unicode. Texto maior recebe marcador TRUNCADO NO MSX. O PC guarda texto de saída até 65536 caracteres e os IDs/uso disponíveis. A resposta HTTPS tem limite de 1 MiB. Bytes privados do mapa MSX sem correspondência Unicode viram ? na entrada da API; arquivos originais do SD permanecem intactos.

Opções de ambiente:
| Variável | Padrão |
|---|---|
| OPENAI_API_KEY | Obrigatória, somente no PC |
| OPENAI_MODEL | Obrigatória; nenhum modelo padrão |
| GATEWAY_MAX_OUTPUT_TOKENS | 1024; intervalo 16–8192 |
| GATEWAY_API_TIMEOUT_MS | 90000; intervalo 1000–120000 |
| OPENAI_REASONING_EFFORT | Não enviado se ausente; configure somente se o modelo suportar |

O limite de tokens inclui eventual raciocínio do modelo. Se ele retornar incomplete, o gateway marca erro/saída parcial; não tenta automaticamente de novo com orçamento maior.

## Diário, backup e recuperação

Cada pedido tem reserva .job.json, marca de início .started.json e resultado .done.json em --state/jobs. O início é confirmado no disco antes do POST HTTPS. Resultado é confirmado antes de ser servido ao MSX. Há exclusão mútua por gateway.lock e serialização de chamadas da conversa.

Se o processo cair com started mas sem resultado, o pedido não é reenviado automaticamente. Uma consulta produz E_AMBIGUOUS ou sinaliza diário inválido. Não há promessa de exatamente uma cobrança em todos os tipos de falha externa; a política evita uma segunda chamada automática do mesmo ID.

Inspeção sem chave e sem chamada de rede:
```
node GATEWAY.cjs --inspect --state C:/MSXCHAT-OPENAI
```
Ela lista IDs/estados/códigos, sem imprimir perguntas e respostas.

Ctrl+C para o servidor aguarda a chamada em andamento, deixa trabalhos ainda não iniciados reservados para a próxima execução e libera o lock. Depois de queda abrupta pode restar gateway.lock: confira que o processo antigo realmente terminou e preserve uma cópia da pasta antes de remover somente esse lock para reabrir. Não remova started/job/done para forçar repetição de um pedido incerto.

Para backup do gateway, encerre-o e copie toda a pasta --state no PC. history-backup.py continua sendo o backup dos arquivos do MSX, não desse diário. Não misture snapshots de namespaces e não apague resultados para liberar IDs: isso compromete a proteção contra repetição. O intervalo de IDs continua finito (00000001–0000FFFF).

## Validação

Passaram 175 testes do COM em CPU Z80 com DOS/BIOS/UNAPI/VRAM simulados; 37 casos-base do gateway; 39 na execução que inclui esses 37 e mais HTTP/TLS reais em loopback. Também passaram 18 do servidor manual, 12 do publicador e 16 do backup. Não são testes físicos do novo COM.

O teste TLS usa certificado/chave sintéticos em tests/fixtures, sem credencial da OpenAI. A chamada real da API está registrada como NOT_RUN em LIVE-API-RESULTS.json.

Depois de configurar chave/modelo, este teste faz uma chamada real e pode gerar cobrança:
```
node tests/smoke-live.cjs --live
```
Sem --live, ele não chama a API. O resultado fica em LIVE-API-RESULTS.json. Depois faça o ensaio completo no Expert e preencha HOMOLOGACAO.csv. A Fase 6 é a homologação integral do conjunto.

Depois de encerrar o servidor, remova a variável do PowerShell se não precisar mais dela:
```powershell
Remove-Item Env:OPENAI_API_KEY
```

Fontes oficiais e detalhes do contrato estão em FONTES.md e PROTOCOLO.md; arquitetura/memória em ARQUITETURA.md.
