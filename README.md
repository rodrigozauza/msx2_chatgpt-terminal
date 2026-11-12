# msx-chatgpt-terminal
Como amante da retrocomputação, resolvi pedir a IA para fazer um terminal em modo gráfico em micros de 8 bits, padrão MSX v2, a partir de um projeto inicial que fiz dessa interface em 1985. Acho que ficou legal. Com o tempo, vou incrementar novas funcionalidades. Fique a vontade também se você é conhecedor do assunto ! divirta-se !  Terminal ChatGPT para MSX2 — SCREEN 7, 80 colunas



Revisão **0.7.2** — [baixar versão publicada](https://github.com/rodrigozauza/msx2_chatgpt-terminal/releases/latest).

Corrige a lentidão na digitação/cursor e a corrupção da fonte do DOS ao sair com Esc. Usa atlas de glifos e cópias do V9938, preservando SCREEN 7 de 80 colunas. Mantém a correção anterior de R#1. Veja [notas da versão](RELEASE-NOTES.md) e [análise da renderização e do DOS](docs/CORRECAO-RENDER-DOS.md).

 Terminal de **80 colunas × 24 linhas**, em SCREEN 7 (512 × 212), com células de **6 × 8 pixels** e margens laterais de 16 pixels.

A fonte original desta revisão tem cinco pixels de desenho e uma coluna de separação, sem redução automática da fonte 8×8 anterior. Inclui maiúsculas, minúsculas, pontuação e o mapa MSX-BR existente. Acentos têm padrões próprios. A inspeção visual das prévias da VRAM, inclusive em proporção 4:3, foi considerada legível; por isso esta entrega mantém SCREEN 7. Isso não substitui a verificação no monitor físico. SCREEN 0 não foi necessária nem é selecionada automaticamente.

## Instalar

1. Reinicie o MSX antes do primeiro teste, para recarregar a fonte do DOS caso a versão anterior a tenha corrompido. Faça backup dos dados do SD.
2. Substitua o executável anterior pelo novo **MSX_CHAT.COM**. **MSXCHAT.COM** tem conteúdo idêntico e pode ser usado com o nome anterior.
3. Inicie pelo console habitual do DOS (modo de vídeo 0 a 3) e use o mesmo IP e porta do gateway:

```text
MSX_CHAT IP_DO_PC PORTA
```

Sem argumentos, o terminal mantém o modo de arquivos offline. A fonte está incorporada ao COM: não é necessário copiar arquivos de fonte para o SD. Os dados de rascunho, perguntas, respostas, recibos e histórico mantêm o formato e não precisam de conversão.

## Organização da tela

| Área | Linhas lógicas |
|---|---|
| Título | 0 |
| Conversa e mensagens; histórico/ajuda sobrepostos | 1 a 18 |
| Estado do editor | 19 |
| Editor multilinha com rolagem | 20 a 22 |
| Atalhos | 23 |

O terminal usa as primeiras 192 linhas de pixels (24 × 8); as 20 linhas restantes da SCREEN 7 têm fundo uniforme. O texto quebra em 80 colunas no editor, nas respostas e no histórico. A resposta e o rascunho continuam limitados a 2047 bytes; a nova janela não reduz o tamanho dos dados salvos. O histórico mostra 17 linhas de conteúdo por página, além do cabeçalho.

O estado usa T=tamanho em bytes, P=posição no texto, L=linha visual, C=coluna, em hexadecimal. A ajuda, calibração de fonte, cabeçalho de histórico e atalhos cabem em 80 colunas.

## Comandos

| Tecla | Ação |
|---|---|
| Setas / Enter / BS / Del | Editar e mover; Enter cria nova linha |
| Ctrl+A ou Home / Ctrl+E | Início/fim da linha lógica |
| Ctrl+Q | Publicar pergunta |
| Ctrl+W | Enviar/consultar no gateway |
| Ctrl+T | Alternar consulta automática |
| Ctrl+S / Ctrl+D | Salvar/carregar rascunho |
| Ctrl+O / Ctrl+B | Importar/rever resposta |
| Ctrl+Y | Abrir histórico |
| Histórico: esquerda/direita | Pedido anterior/seguinte |
| Histórico: cima/baixo | Rolar uma linha |
| Histórico: Ctrl+U / Ctrl+N | Página anterior/seguinte |
| Histórico: Ctrl+A / Ctrl+E | Topo/fim |
| Histórico: Ctrl+F | Copiar pergunta ao editor vazio |
| Ctrl+X duas vezes | Cancelar pendência local |
| Ctrl+G / Ctrl+R | Ajuda/calibração de fonte |
| Ctrl+P / Ctrl+L | Prévia local/limpar editor |
| Esc | Fechar histórico ou restaurar DOS e sair |

## Configuração da máquina

A SM-X informada pelo usuário sintetiza MSX2+ com VRAM de 128 KB e RAM mapper de 2 MB ou 4 MB, conforme firmware OCM/KdL. A detecção corrigida na revisão screen7.1 foi preservada: aceita o campo padrão 04h de 128 KB em MODE (FAFCh), ignora os demais flags e continua recusando 16/64 KB.

Também permanecem as referências anteriores: SD Mapper RAM/ROM de 512 KB, SD de 4 GB, Nextor 2.1, InterNestor Lite 2.3 e ObsoNET BIOS 1.3. O terminal usa a TPA fornecida pelo DOS, não aloca segmentos adicionais nem reconfigura o mapper. Mantenha a mesma instalação da pilha/helper TCP/IP UNAPI, implementação de índice 1, utilizada no projeto anterior.

O caminho FCB comum de MSX-DOS 1/2/Nextor e as partições do SD são preservados. No modo DOS1, mantenha mídia/partição FAT12 suportada pelo driver. IP, porta, máscara, gateway, DNS, drivers, slots e boot não são alterados pelo terminal.

## Gateway no PC

Continue usando o gateway, IP/porta, --peer e pasta --state anteriores. OPENAI_API_KEY e OPENAI_MODEL continuam somente no PC. O protocolo msxchat/1, HTTP na LAN, HTTPS no PC e consulta após HTTP 202 permanecem iguais.

O manual de configuração do PC está em docs/MANUAL-BASE-MSX1.md. Esse documento é histórico: suas menções a SCREEN 2/64 colunas não descrevem esta interface. Não execute versões distintas simultaneamente sobre o mesmo conjunto de pedidos e estado.

## Construir e verificar

```text
python build.py
node tests/test-msxchat.cjs
node tests/test-gateway.cjs
node tests/test-lan-server.cjs
node tests/test-helper.cjs
python tests/test-backup.py
python tools/package_release.py
node VERIFICAR.cjs
```

Use Python 3 e Node 18+. Montador e emulador de CPU incluídos, sem dependências externas para instalar. VERIFICAR.cjs confere a distribuição recebida; relatórios e imagens regenerados pelos testes podem alterar os hashes. Veja VALIDACAO.md para resultados e limites.

Fonte 5×7 original: CC0-1.0; padrões em tools/font5x7.json e gerador em tools/make_font.py. O nome FONT8X8.bin é mantido por compatibilidade do formato (256 glifos × 8 rasters), mas a célula visível é 6×8. As tabelas 8×8 de domínio público da revisão anterior ficam em tools/ como referência histórica.

As imagens PREVIA são reconstruções da VRAM simulada. PREVIA-LEITURA.png usa proporção aproximada 4:3 para facilitar a avaliação; a aparência física depende da saída de vídeo e do monitor. A homologação na SM-X permanece necessária.
