# Interface legível em SCREEN 7

- Geometria escolhida: 32 × 16 células de 16 × 12 pixels; SCREEN 7 de 512 × 212 preservada.
- Fonte 8×8 de domínio público, com o mapa MSX-BR, substitui a antiga fonte 4×8. Pixel duplicado na horizontal; escala vertical 1,5 por mapa de scanlines.
- Renderizador: 32 células de oito pares de pixels por scanline, 12 scanlines por linha; total de 256 bytes por scanline. Cursor inverte a célula inteira e as cores continuam por linha.
- Buffer lógico mantém stride de 64 bytes para preservar o mapa de RAM; somente as primeiras 32 posições de cada linha são visíveis. Os limites do editor, diretórios e protocolo não mudam.
- Conversa: dez linhas com rolagem; editor: três linhas com viewport; histórico: nove linhas por página. Ajuda e cabeçalhos cabem em 32 colunas.
- Estado compacto T/P/L/C e mensagens longas com quebra em 32 colunas.
- A correção de VRAM padrão 04h da SM-X foi mantida.
- Gateway, autenticação no PC, arquivos do SD e configuração do mapper foram preservados.

Os fontes completos, gerador da fonte, tabelas e testes acompanham o pacote. A revisão anterior foi preservada em work/screen7-32col/original, fora do pacote de instalação.
