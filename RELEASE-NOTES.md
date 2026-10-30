# MSX2 ChatGPT v0.7.2 — SCREEN 7 rápida e saída estável para DOS

Corrige dois problemas relatados no MSX físico: renderização de cada tecla acima de 900 ms e caracteres do prompt do DOS deformados após Esc.

## Causas e correções

A versão anterior reconstruía pixels de linhas inteiras para cada tecla, inclusive estado e cursor, e percorria novamente o texto de até 2047 bytes. Agora o V9938 copia glifos de uma atlas de cinco cores na VRAM, atualiza células alteradas e executa rolagem/deslocamento por HMMM. O editor faz reflow apenas da janela afetada; busca de linhas usa CPIR. A cache é preparada uma vez ao iniciar o COM.

A cópia do DOS era lida em modo texto linear e devolvida enquanto SCREEN 7 usava VRAM entrelaçada. Agora os 16 KB físicos do console são guardados em VRAM reservada e restaurados usando SCREEN 5 linear, antes de recolocar os registradores e o modo do DOS. A interface continua integralmente em SCREEN 7; SCREEN 5 é usado somente em transições com vídeo oculto.

## Validação

224 testes Z80/BIOS/VDP/DOS/UNAPI e 83 verificações do PC: total 307. O modelo agora contempla bancos físicos da VRAM, atlas, HMMM/HMMV/XOR, portas reais obtidas da BIOS e seção crítica de status/comandos. Um oráculo independente verifica texto e pixels após inserção/exclusão/LF/rolagem.

Dez cenários de latência passam no orçamento de 100 ms a 3,58 MHz, incluindo 20 ms de margem para apresentação de quadro/interrupções: digitação, texto longo, inserção no meio, rolagem, Enter, esquerda, Backspace, Delete, limite de buffer e piscar do cursor. Veja PERFORMANCE-RESULTS.json. São estimativas em ciclos com tempos de BIOS/VDP modelados; não são medições no seu MSX. A confirmação física permanece pendente.

## Instalação

Reinicie o MSX antes do primeiro teste para recuperar uma fonte do DOS já corrompida pela versão anterior. Extraia o ZIP e substitua o MSX_CHAT.COM no SD. MSXCHAT.COM é um alias idêntico. Mesmos drivers ObsoNET/UNAPI, SD Mapper, IP, porta, gateway e dados salvos. Fonte incorporada; sem nova alocação de RAM mapper. Atualize o conjunto de fontes/ferramentas no PC se mantiver uma cópia do projeto.

A inicialização pode levar mais tempo para preparar a atlas uma única vez; a meta de 100 ms se aplica à edição/renderização interativa, não às operações de rede ou disco.
