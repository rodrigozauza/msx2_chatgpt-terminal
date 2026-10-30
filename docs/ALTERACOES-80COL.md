# Revisão 80 colunas

SCREEN 7, 80×24, célula 6×8 e margens de 16 pixels. O V9938 usa 3 bytes por caractere por raster; cada nibble representa um pixel independente. Não há duplicação horizontal. Editor e histórico compartilham a quebra em 80; status=19, editor=20–22, rodapé=23. Histórico exibe 17 linhas por página.

A grade usa stride=80 e ocupa 4000h–477Fh. Editor=4800h–4FFFh; raster=5000h–50FFh; nomes=5100h–53FFh; dirty=5400h; cores=5420h; overlay=5500h–5A9Fh; backup de cores=5B00h; comparação do editor=5C00h–5CEFh. Backup de VRAM=6000h–9FFFh e buffers de transporte permanecem nas posições anteriores. O COM cabe abaixo de 4000h.

Mesma placa ObsoNET, TCP/IP UNAPI e SD Mapper; sem troca de drivers, slots, partições ou configuração de boot. Os módulos de transporte de rede, DOS, JSON e persistência mantêm o código da revisão 32 colunas. Em NETCONFIG.ASM, mudou somente o texto do título para 80×24. Fonte incorporada no COM.

A fonte tem cinco pixels de desenho mais separador. Acentos minúsculos usam dois rasters superiores; maiúsculas acentuadas usam corpo próprio de cinco rasters. O teste verifica a distinção O/0, I/l/1, colchetes/chaves/parênteses e os acentos portugueses. A prévia 4:3 foi inspecionada e considerada legível. A aparência de TV/monitor físico permanece pendente; não houve teste físico ou emulador MSX completo. SCREEN 0 não foi implementada nesta revisão porque a avaliação da SCREEN 7 foi satisfatória.

Base técnica: [MSX2 Technical Handbook, capítulo 4](https://konamiman.github.io/MSX2-Technical-Handbook/md/Chapter4a.html).
