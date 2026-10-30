# Fonte atual — 80 colunas

Fonte 5×7 original CC0, tools/font5x7.json; células 6×8. Ver docs/ALTERACOES-80COL.md e tools/LICENSE-font5x7.txt. As referências de fontes abaixo são históricas.

# Atualização da fonte — revisão 32 colunas

Fonte 8×8: Daniel Hepper / Marcel Sondaar / IBM VGA, domínio público. Tabelas originais: https://github.com/dhepper/font8x8. Arquivos tools/font8x8_basic.h e tools/font8x8_ext_latin.h; licença em tools/LICENSE-font8x8.txt. O gerador tools/make_font.py preserva o mapa MSX-BR e produz FONT8X8.bin e src/FONT8X8.ASM.

As referências abaixo são históricas da implementação anterior; a antiga fonte 4×8 foi substituída nesta revisão.

# Referências — Fase 5

## OpenAI Docs consultadas antes da implementação

- [Geração de texto](https://developers.openai.com/api/docs/guides/text): requisição Responses e estrutura de saída com itens/partes output_text.
- [Estado de conversas](https://developers.openai.com/api/docs/guides/conversation-state): composição manual de mensagens e store=false. O limite de oito pares/16000 caracteres é decisão deste gateway.
- [API Overview](https://developers.openai.com/api/reference/overview): autenticação Bearer no servidor, proteção de credenciais e IDs de rastreio.
- [Códigos de erro](https://developers.openai.com/api/docs/guides/error-codes): classificação de falhas. A decisão de não reenviar automaticamente geração é política explícita desta aplicação.
- [Modelos de raciocínio](https://developers.openai.com/api/docs/guides/reasoning): max_output_tokens e status incomplete. Não foi selecionado modelo; OPENAI_MODEL será configurado no PC.

O endpoint é chamado por HTTPS padrão, sem SDK. Não foi pressuposta idempotência externa do X-Client-Request-Id. O diário local implementa sua própria prevenção de nova chamada.

## Base MSX preservada

- [TCP/IP UNAPI](https://github.com/Konamiman/MSX-UNAPI-specification/blob/master/docs/TCP-IP%20UNAPI%20specification.md).
- [MSX UNAPI 1.1](https://github.com/Konamiman/MSX-UNAPI-specification/blob/master/docs/MSX%20UNAPI%20specification%201.1.md).
- [MSX-DOS FCB, cópia primária no projeto Nextor](https://github.com/Konamiman/Nextor/blob/v2.1/docs/DOS2-FCS.TXT).
- [ASCII Technical Handbook, BIOS](https://www.konamiman.com/msx/msx2th/th-5a.txt).
- [TMS9918A Data Manual](https://computers.baffa.tec.br/pages/datasheet/TMS9918A_TMS9928A_TMS9929A_Video_Display_Processors_Data_Manual_Nov82.pdf).
- [RFC 9112, HTTP/1.1](https://www.rfc-editor.org/rfc/rfc9112.html) e [RFC 8259, JSON](https://www.rfc-editor.org/rfc/rfc8259).

Nenhuma nova função BIOS/DOS, porta de cartucho ou acesso a mapper foi introduzido. HTTP 202 reutiliza a camada TCP/HTTP existente. A premissa de homologação não substitui medição do novo COM no Expert.

## Ferramentas

pyz80, sem modificação: blob e9d1bbc33de7255c589cf6e9cb9aeba1372119fb; GPL-2.0-or-later em tools/COPYING-pyz80.txt. [Fonte](https://github.com/simonowen/pyz80/blob/main/src/pyz80/pyz80.py).

Z80.js, sem modificação: blob 92760b9a346492243df099a11eca560a6085fd11; MIT em tests/LICENSE-Z80.txt. [Fonte](https://github.com/DrGoldfire/Z80.js/blob/master/Z80.js).

Fontes próprios MIT em LICENSE.txt. Python e Node usam biblioteca padrão. O certificado/chave sintéticos dos testes locais foram gerados com OpenSSL nativo do Git; os testes Node usam os arquivos incluídos e não requerem OpenSSL instalado.

As respostas sintéticas e o resultado NOT_RUN não são apresentados como saída real da OpenAI.
