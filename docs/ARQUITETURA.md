# Arquitetura técnica — MSX2 v0.7.1

Interface atual: SCREEN 7, 80×24, células 6×8. Inicialização aceita estados normais do V9938/V9958 com R#1 bit 7 desligado. Veja CORRECAO-BIOS-R1.md e ../VALIDACAO.md para a evidência desta revisão. As descrições e referências às fases anteriores abaixo são históricas do gateway.

## Objetivo e evidência

Conectar o transporte HTTP validado da Fase 4 a um gateway HTTPS da Responses API. A homologação do novo COM da Fase 4 foi assumida por instrução do usuário. O gateway desta entrega foi executado em testes locais, incluindo HTTP e TLS reais em loopback; as respostas da OpenAI nesses testes são simuladas. A chamada autenticada real permanece pendente de chave/modelo no PC.

O uso da skill OpenAI Docs orientou a consulta às fontes oficiais listadas em FONTES.md. Não há SDK nem dependência de pacote externo. HTTPS usa a biblioteca padrão do Node, com certificado validado e hostname oficial fixo.

## Divisão das responsabilidades

| Componente | Responsabilidade |
|---|---|
| MSXCHAT.COM / Assembly | Editor, SCREEN 7 80×24, arquivos, histórico, TCP/IP UNAPI, HTTP 200/202 e consulta |
| GATEWAY.cjs | Configuração por ambiente, listener LAN, ciclo de vida e inspeção |
| OPENAI-CLIENT.cjs | POST HTTPS, autenticação no PC, limite de corpo, timeout e extração de texto |
| GATEWAY-STORE.cjs | Reserva/início/resultado duráveis, serialização, continuidade e replay |
| LAN-SERVER.cjs | Camada HTTP LAN reutilizada; também conserva o servidor manual de teste |
| make-response.cjs / history-backup.py | Publicador offline e backup dos dados MSX |

A comunicação continua iniciada pelo MSX. O gateway não compartilha o cartão nem inicia conexão ao MSX.

## Contratos

Contrato A: POST HTTPS em api.openai.com/v1/responses, com modelo configurado, instruções, mensagens user/assistant, max_output_tokens, store=false e stream=false. reasoning.effort é opcional e só é enviado se configurado. A autenticação Bearer é montada apenas na conexão HTTPS do PC.

Contrato B: os mesmos oito campos locais de msxchat/1. O identificador opaco da API permanece no diário PC; response_id do MSX é o request_id hexadecimal de oito posições. Essa separação evita apresentar o envelope reduzido como JSON público original.

O adaptador percorre output, seleciona mensagens assistant e reúne partes output_text. Não assume que o primeiro item seja texto. Trata recusa, saída vazia, incomplete, failed, tamanho excessivo e UTF-8 inválido. Não executa ferramentas.

## Sequência

1. Ctrl+Q gera o pedido confirmado no SD; Ctrl+W transmite o mesmo REQ.
2. O gateway valida origem, endpoint, Content-Length, JSON, conversa e ID.
3. Reserva .job.json exclusivamente e confirma a gravação. Retorna HTTP 202 rapidamente.
4. A fila serial prepara até oito pares anteriores de contexto, com limite de 16000 escalares do histórico.
5. Confirma .started.json antes de invocar HTTPS uma única vez, usando UUID rastreável no X-Client-Request-Id.
6. O adaptador obtém/normaliza o resultado. Confirma .done.json antes de servi-lo.
7. Consultas seguintes do mesmo ID/conteúdo recebem 202 enquanto ativo, depois 200 com completed/error.
8. O MSX grava RXT incrementalmente, valida e publica RSP; o importador confirma ACK antes de mostrar texto.

A consulta automática de rede só é armada por 202. Não transmite uma pergunta nova por conta própria. É pausada na consulta ao histórico e controlada por Ctrl+T. Erro, cancelamento local confirmado ou nova publicação desarma essa consulta; Ctrl+W permite retomar. Depois de reiniciar, o primeiro contato com o pedido pendente é manual.

## Diário e repetição

GATEWAY-STATE.json fixa peer e conversation_id; a pasta não pode ser reutilizada para um namespace diferente ou misturada com cache manual. gateway.lock impede outra instância normal no mesmo estado.

Reserva e marca de início são separadas do resultado. A existência da marca de início sem resultado impede uma segunda chamada automática após reiniciar. Um job reservado mas ainda não iniciado pode voltar à fila numa consulta futura. Se a configuração mudou, recebe erro explícito em vez de trocar silenciosamente modelo/opções.

IDs novos precisam avançar em relação aos já conhecidos. Replay de ID conhecido compara SHA-256 dos oito valores canônicos; outro conteúdo recebe conflito. O histórico da API é derivado de resultados confirmados e inclui somente turnos locais completed; erros não entram como respostas bem-sucedidas.

O encerramento aguarda a chamada em andamento e deixa trabalho ainda não iniciado reservado para a próxima execução. Não usa shutdown para iniciar novas chamadas em fila. Queda abrupta pode deixar lock: a recuperação exige confirmar que não existe processo anterior e preservar os arquivos.

Essa política não afirma exatamente uma cobrança diante de todos os tipos de falha de serviço/energia/armazenamento. Evita reenvio automático de um ID já marcado como iniciado. Não se apoia em uma suposta garantia de idempotência do cabeçalho X-Client-Request-Id; esse cabeçalho serve para rastreio.

## Segurança e limites no PC

A chave é lida de OPENAI_API_KEY e nunca é fornecida ao MSX, ao JSON local, ao contexto do modelo ou à linha de comando do gateway. Host/path HTTPS são fixos; não há OPENAI_BASE_URL nem redirecionamento automático. rejectUnauthorized=true e TLS mínimo 1.2. NODE_TLS_REJECT_UNAUTHORIZED=0 e debug HTTP são recusados.

Erros externos são mapeados para códigos/mensagens locais sem copiar seus corpos brutos. Texto inesperado contendo a chave é redigido antes do resultado local. IDs de rastreio são limitados e não podem conter a chave. Configuração que confunda modelo com chave é recusada.

O listener exige IPv4 privado e peer exato. É restrição na LAN, não criptografia do trecho MSX–PC. Nunca encaminhar esse serviço HTTP à internet.

Limites: corpo LAN 32767 bytes; resposta HTTPS 1 MiB; até 2047 escalares no MSX; texto PC até 65536 caracteres; contexto de até oito pares/16000 escalares mais pergunta atual; oito trabalhos pendentes em memória. Tokens de saída padrão 1024, configuráveis entre 16 e 8192. Timeout HTTPS padrão 90 s, máximo 120 s. Não há retries automáticos ao endpoint de geração.

O diário contém texto das conversas e deve ser copiado integralmente no PC para backup com o servidor encerrado. Ele não é coberto pelo utilitário de backup do SD. Não há descarte automático de marcas de deduplicação; o espaço de IDs continua finito.

## Mapa de RAM do MSX

| Faixa | Uso |
|---|---|
| 0100–3FFF | Código/dados/fonte; assert program_end < 4000h |
| 4000–45FF | Grade 64×24 |
| 4600–4DFF | Editor: 2047 bytes e NUL |
| 4E00–4EFF / 4F00–51FF | Linha de padrões / nomes |
| 5200–5217 / 5220–5237 | Linhas sujas / cores |
| 5300–573F / 5740–5750 | Janela salva / cores de sobreposição |
| 5800–58FF | Comparação do editor |
| 6000–9FFF | Backup de 16 KiB da VRAM |
| A000–A7FF / A800–AFFF | message / reply decodificadas |
| B000–B0FF | E/S FCB 256 bytes |
| B100–B1FF / B200–B224 | Metadados JSON / FCB |
| B300–B308 | Códigos HEX |
| B400–BBFF | Pergunta de histórico, fora do modo de rede |
| B400–B4FF / B500–B5FF | Recepção TCP / linha HTTP |
| B600–B6FF / B700–B70A | Envio TCP / parâmetros OPEN |
| C100 ou superior | Requisito mínimo de BDOS/SP inicial |

Os buffers de rede continuam fora da página 1. A consulta de histórico e a rede são mutuamente exclusivas. Não há novo acesso a mapper, portas ou funções DOS2. Os novos flags/ponteiros ficam nos dados estáticos.

VRAM permanece em SCREEN 2: padrões 0000–17FF, nomes 1800–1AFF, terminador de sprites em 1B00 e cores 2000–37FF. 64 × 4 = 256 pixels; 24 × 8 = 192. Vídeo/DTA/ARG/pilha e operações de disco mantêm os mecanismos já testados.

## Pendências de aceite

Sem API key/modelo configurados não foi possível validar conta, permissão de modelo, cobrança, latência real ou resposta autenticada. Sem acesso ao Expert não foi executado este COM no hardware ou em emulador MSX completo. Esses resultados precisam de LIVE-API-RESULTS.json e HOMOLOGACAO.csv preenchidos no ambiente real; não são inferidos dos testes locais.
