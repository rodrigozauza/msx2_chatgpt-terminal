# Correção da inicialização — v0.7.1

O erro relatado foi reproduzido executando o COM 0.7 no emulador Z80 com geração MSX2, MODE=04h (128 KB VRAM) e R#1=70h. A saída foi exatamente "MSXCHAT: BIOS must have 16K VRAM addressing enabled." e nenhuma entrada em SCREEN 7 ocorreu.

## Causa

MAIN.ASM consultava RG0SAV+1 (F3E0h), aplicava AND 80h e encerrava se o resultado fosse zero. A semântica 4/16 KB do bit 7 pertence ao VDP TMS9918 do MSX1. No V9938/V9958 esse bit é reservado: o diagrama oficial de R#1 o fixa em zero. Logo, a rejeição era do aplicativo e não prova defeito/configuração errada da BIOS, placa de rede ou SD Mapper.

Os testes 0.7 mascaravam o problema: o estado inicial simulado usava R#1=F0h, com bit 7 ligado, e havia até um teste que esperava recusar 70h. A configuração do aplicativo escrevia A0h/E0h, também com bit reservado ligado.

## Solução

Removida a condição sobre R#1 e o erro morto. Permanecem as verificações de geração MSX2+, MODE com 128 KB, TPA, pilha e modo inicial 0–3. O programa escreve 20h para ocultar o vídeo e 60h para exibir SCREEN 7. Ao devolver o console, restaura R#1 e os demais registradores exatamente como encontrados, inclusive em estados legados.

O simulador agora parte de 70h. Foram adicionadas combinações com bit 7 desligado para MSX2 e MSX2+, consoles TEXT1/TEXT2 de 40/80 colunas e operações de SD/rede que deixam e retomam SCREEN 7. O caso legado F0h continua aceito para não criar rejeição desnecessária.

Também foi corrigida a indicação de 64 para 80 colunas nas instruções do gateway. Nenhum driver, slot, partição ou formato de dados foi trocado.

## Referência e limite

[Yamaha V9938 — funções dos registradores, seção 1.1](https://ftp.whtech.com/YAHOO%20group%20backups/GENEVE/FILES/v9938%20Application%20Manual.htm). Testes executam o COM real, mas a BIOS/VDP/DOS/UNAPI são simulados. Não houve teste no MSX físico ou emulador completo nesta correção.
