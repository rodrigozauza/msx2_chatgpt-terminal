# MSX2 ChatGPT v0.7.1 — SCREEN 7 / 80 colunas

Corrige a interrupção na inicialização com a mensagem "BIOS must have 16K VRAM addressing enabled". A versão anterior interpretava o bit 7 de R#1 como requisito de VRAM. Esse bit é reservado no V9938/V9958; BIOS normais de MSX2 usam R#1=70h/60h/68h, com o bit desligado.

- Removida a checagem indevida; continuam as verificações de MSX2, 128 KB VRAM, TPA e modo inicial 0–3.
- R#1 agora recebe 20h para apagar o vídeo e 60h para mostrar SCREEN 7, com bit reservado zero. Restauração preserva exatamente os registradores originais do DOS.
- Testes usam estados reais de BIOS, incluindo consoles de 40/80 colunas, R#1 com bit 7 desligado, leitura/gravação no SD e ida/volta de operações de rede.
- Instrução textual do gateway corrigida de 64 para 80 colunas.
- Mantidos SCREEN 7 80×24, fonte incorporada 5×7/6×8, ObsoNET, TCP/IP UNAPI, SD Mapper e protocolo msxchat/1.

Validação: 211 testes Z80/BIOS/VDP/DOS/UNAPI simulados; 37 gateway; 18 LAN; 12 publicador; 16 backup. Total: 294. Não houve chamada paga/autenticada à API, emulador MSX completo ou teste físico; a revalidação no MSX real permanece pendente.

## Instalação

Extraia o ZIP. Copie MSX_CHAT.COM para o SD, substituindo o executável anterior. MSXCHAT.COM é um alias de conteúdo idêntico. A fonte já está incorporada; não é preciso copiar o restante para o MSX. Continue usando o mesmo IP, porta, pilha e gateway. Dados existentes não precisam de conversão. Se atualizar o gateway no PC, preserve sua pasta de estado e suas variáveis de ambiente.

Referência: [Yamaha V9938 — Mode Registers](https://ftp.whtech.com/YAHOO%20group%20backups/GENEVE/FILES/v9938%20Application%20Manual.htm), R#1 bit 7 reservado.
