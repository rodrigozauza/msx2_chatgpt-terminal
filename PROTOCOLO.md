# Contratos — Fase 5

## A: OpenAI Responses API

Endpoint fixo HTTPS: https://api.openai.com/v1/responses. O gateway monta Authorization: Bearer a partir do ambiente PC e não o encaminha ao MSX.

Formato emitido:
```json
{
  "model": "VALOR_DE_OPENAI_MODEL",
  "instructions": "Instrucoes fixas de resposta curta em texto simples",
  "input": [
    {"role":"user","content":"Pergunta anterior"},
    {"role":"assistant","content":"Resposta anterior"},
    {"role":"user","content":"Pergunta atual"}
  ],
  "max_output_tokens": 1024,
  "store": false,
  "stream": false
}
```
É um exemplo estrutural, não uma requisição executada com esse placeholder de modelo. O conteúdo real vem do diário validado. reasoning.effort só aparece quando configurado.

O texto é extraído de todas as partes output_text de mensagens assistant em output. IDs opacos, status e contagens disponíveis são guardados no PC. O atalho output_text dos SDKs não é presumido no JSON HTTP bruto. [Guia oficial de texto](https://developers.openai.com/api/docs/guides/text).

O contexto é montado manualmente; não usa previous_response_id nem a Conversations API. store=false é enviado em cada chamada. [Estado de conversas](https://developers.openai.com/api/docs/guides/conversation-state).

O limite max_output_tokens inclui raciocínio quando aplicável. Saída incomplete vira erro local com indicação visível, não uma repetição oculta. [Guia de raciocínio](https://developers.openai.com/api/docs/guides/reasoning).

## B: envelope local no SD e HTTP 200

Exatamente oito propriedades string; conversa fixa 00000001, profundidade um, sem chaves extras/duplicadas. Exemplo de pedido:
```json
{"protocol":"msxchat/1","request_id":"00000001","conversation_id":"00000001","state":"pending","message":"Pergunta","response_id":"","reply":"","error_code":""}
```
Exemplo de resposta local (não é JSON original da OpenAI):
```json
{"protocol":"msxchat/1","request_id":"00000001","conversation_id":"00000001","state":"completed","message":"","response_id":"00000001","reply":"Texto extraido pelo gateway.","error_code":""}
```

| Estado | Regras |
|---|---|
| draft | request_id=00000000; message pode ser vazio; response_id/reply/error_code vazios |
| pending | ID correspondente ao nome; message não vazio; response_id/reply/error_code vazios |
| completed | IDs associados; message vazio; response_id válido não zero; reply não vazio; error_code vazio |
| error | IDs associados; message vazio; response_id válido não zero; error_code não vazio; reply pode ser vazio |
| ack | IDs associados; message/reply vazios; response_id não zero; error_code pode preservar erro |
| cancelled | ID associado; message/response_id/reply/error_code vazios; marcador local |

IDs de pedido vão de 00000001 a 0000FFFF, em oito hexadecimais maiúsculos; não são globais. O gateway usa o mesmo ID como response_id local, sem comprimir o ID opaco da API nesse campo. Limites: message/reply até 2047 posições decodificadas MSX; error_code ASCII imprimível até 31; arquivo bruto até 32767 bytes.

UTF-8 sem BOM; escapes JSON e pares substitutos válidos. O parser MSX rejeita UTF-8 inválido, campos ausentes/duplicados/extras, estruturas aninhadas e conteúdo excedente. Caracteres sem glifo aparecem como ?, preservando o RSP original. A política MSX-BR e os escapes privados U+E080–U+E0FF de rascunho permanecem; o gateway substitui esses bytes privados por ? antes da entrada da API. Controles não gráficos são neutralizados para texto do modelo/tela.

Resposta acima de 2047 escalares é cortada em limite de caracteres e recebe marcador. incomplete/recusa/saída vazia são identificadas por códigos locais, não escondidas como sucesso. O texto PC é limitado a 65536 caracteres.

## HTTP LAN

POST /msxchat/v1/exchange, Host com IPv4/porta, Content-Type application/json, Content-Length e Connection: close. O servidor aceita somente peer configurado e não aceita Transfer-Encoding/Content-Encoding.

HTTP 200 carrega somente completed/error do contrato B. O MSX exige cabeçalhos limitados (linha 255; bloco 2048 bytes), comprimento positivo até 32767, corpo exato e EOF ordenado. O corpo é recebido incrementalmente em RXT antes de validar/publicar RSP; ACK precede a exibição.

Novo controle HTTP 202: indica que o pedido foi reservado/está processando no PC. Pode trazer {"state":"processing"} e Retry-After: 2. Esse corpo de controle não é resposta do modelo, não é publicado como RSP e não recebe ACK. O cliente libera sua conexão e conserva REQ/editor. A consulta automática só é armada por esse status e repete o mesmo POST/ID; o diário evita nova chamada.

Outros status continuam sendo erro de transporte/protocolo. O mesmo ID com outro conteúdo ou ID desconhecido antigo recebe 409; estado inválido recebe 503. Não há redirects, chunked, gzip, DNS ou TLS no Z80. HTTPS fica no gateway.

## Arquivos e diário

SD: MSXDRAFT.JSN/BAK/TMP; XXXXXXXX.ID/REQ/TMP/RSP/NEW/AKT/ACK/CNT/CAN/RXT. ID é reserva permanente; REQ/RSP/ACK/CAN confirmados são preservados. Provisórios não são adotados automaticamente. Fluxos e manutenção dos manuais anteriores permanecem.

PC: GATEWAY-STATE.json, gateway.lock, jobs/PEER-ID.job.json, .started.json e .done.json. Reserva/início/resultado são confirmados separadamente. Início sem resultado após queda gera ambiguidade, sem retry da API. A pasta de estado é um namespace; não deve ser substituída para forçar reenvio nem mesclada a outro cartão/conjunto de IDs.

X-Client-Request-Id é um UUID de rastreio, não uma garantia externa de idempotência. A prevenção de repetição é implementada pelo diário do gateway. A chave de API nunca faz parte de nenhum desses contratos locais. [Autenticação e rastreio oficiais](https://developers.openai.com/api/reference/overview).
