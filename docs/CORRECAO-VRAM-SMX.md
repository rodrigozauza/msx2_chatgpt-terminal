# Correção da detecção de VRAM — revisão screen7.1

Falha relatada: a execução de MSX_CHAT.COM na SM-X com 128 KB de VRAM terminava com a mensagem de VRAM insuficiente.

Causa confirmada no código: MAIN.ASM usava AND 06h / CP 06h / JP NZ. O campo padrão de 128 KB é 10b nos bits 2:1, isto é, 04h após a máscara. O teste anterior também adotava 06h por padrão e ocultava a falha. A fonte consultada inicialmente, apêndice 4 do manual, contém uma indicação conflitante com a tabela 2.22 do capítulo 2.

Reparo: AND 06h / CP 04h / JP C. Valores 00h e 02h continuam recusados; 04h é aceito e a aceitação anterior de 06h é mantida. Outros bits de MODE não interferem e não são alterados. Não se trata de ignorar a capacidade ou de forçar uma SM-X com memória insuficiente.

Novos casos: gerações MSX2 e MSX2+, MODE 04h/0Ch/84h/8Ch/06h/0Eh, incluindo inicialização, gravação de rascunho, retorno à SCREEN 7 e saída; recusas com 16/64 KB e flag de máscara. Todo o restante da suíte agora usa 04h por padrão.

A falha foi reproduzida com o binário antigo antes da reconstrução. O registro e a cópia anterior estão em work/screen7-vram-fix no projeto, fora do pacote para instalação.

O nome MSX_CHAT.COM foi adicionado como alias 8.3 do executável MSXCHAT.COM para corresponder ao comando usado na homologação. Ambos devem ter o mesmo hash. A configuração de rede, gateway, SD e mapper não muda.

Referências:
- [Manual MSX2 — capítulo 2, tabela 2.22](https://konamiman.github.io/MSX2-Technical-Handbook/md/Chapter2.html#table-222--getting-the-information-about-the-vram-capacity).
- [Projeto SM-X — MSX2+ baseado em OCM/KdL](https://gitlab.com/victor.trucco/sm-x).

Limite da verificação: a codificação foi reproduzida em CPU Z80 com BIOS/VDP simulados; a placa do usuário não foi acessada remotamente. A homologação física do novo executável permanece a fazer.
