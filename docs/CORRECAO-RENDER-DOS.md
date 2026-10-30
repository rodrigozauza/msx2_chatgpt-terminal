# Renderização e restauração do DOS — 0.7.2

## Causas raiz reproduzidas

A tecla e o piscar invalidavam linhas inteiras. Cada raster reconstruía pixels de até 80 glifos por linha no Z80, e o editor voltava a percorrer todo o texto. O caminho anterior de uma tecla somou ~491 ms no modelo de ciclos, compatível com um gargalo de CPU, embora não seja uma reprodução quantitativa dos >900 ms medidos pelo usuário.

A saída salvava o console sob um modo de VRAM linear e escrevia os bytes de volta ainda em SCREEN 7. Nesse modo, o endereço lógico A0 seleciona o banco físico: P=((A>>1)|((A&1)<<16)). Restaurar os mesmos endereços lógicos sob esse mapeamento embaralha os bytes físicos e os padrões de caracteres. O modelo anterior usava um único vetor linear e escondia a corrupção. Com bancos físicos, a versão 0.7.1 falha e a nova passa.

## Solução mantendo SCREEN 7

- Atlas com 256 glifos, cinco pares de cores, em X=16–495/Y=256–383. O V9938 executa HMMM 6×8 para os glifos; LMMV/XOR inverte somente a célula do cursor.
- Cache de códigos e inversão em RAM; somente células alteradas são copiadas. Estado e edição não invalidam a linha inteira.
- Rolagem 480×16 e deslocamentos horizontais usam HMMM. Cache e grade seguem exatamente o mesmo deslocamento, inclusive com cópias sobrepostas no sentido correto.
- Inserção/exclusão faz reflow da janela afetada. CPIR localiza linhas/viewport sem interpretar novamente todos os pixels ou reconstruir o buffer inteiro.
- Nas transições, o vídeo fica oculto e SCREEN 5 fornece endereçamento físico linear. Um HMMM guarda os 16 KB do console em 1C000h–1FFFFh; o inverso ocorre antes de restaurar os registradores do DOS. SCREEN 5 não é a interface do terminal.

A atlas ocupa endereços físicos 8000h–BFFFh e 18000h–1BFFFh, sem sobrepor o backup. Dados do console DOS padrão em 0000h–3FFFh são preservados. Não há nova alocação de segmentos do mapper, arquivo temporário no SD ou alteração de drivers.

## RAM

Código/constantes até 43FFh; grade 4400h–4B7Fh; editor 4C00h–53FFh; raster 5400h–54FFh; cache 5500h–577Fh; cores da cache 5780h; dirty 5800h; cores 5820h; overlay 5900h–5E9Fh; cores do overlay 5F00h; comparação de entrada 5F40h–602Fh; células alteradas 6040h; LUT de atlas 6100h–63FFh. Buffers de protocolo/rede A000h–BFFFh continuam no mesmo lugar. O montador verifica os limites.

## Referências primárias

- [VDP V9938, comandos e registradores](https://ftp.whtech.com/YAHOO%20group%20backups/GENEVE/FILES/v9938%20Application%20Manual.htm).
- [MSX2 Technical Handbook, comandos VDP](https://konamiman.github.io/MSX2-Technical-Handbook/md/Chapter4b.html).
- [openMSX, executeCpuVramAccess e mapeamento planar](https://github.com/openMSX/openMSX/blob/master/src/video/VDP.cc).

Tempos são modelados e a revalidação física continua necessária. Reinicie o MSX antes do primeiro teste para recarregar a fonte do DOS que uma execução da versão antiga pode ter corrompido.
