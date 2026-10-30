# Validação — v0.7.2

224 testes do COM real sobre CPU Z80 e modelo de BIOS/VDP/DOS/UNAPI; 37 gateway, 18 LAN, 12 publicador e 16 backup: total 307 PASS.

## Latência

PERFORMANCE-RESULTS.json contém dez cenários: eco em editor vazio, fim de texto longo, inserção no meio, rolagem na coluna 80, Enter, esquerda, Backspace, Delete, rejeição de buffer cheio e piscar. CPU de 3.579.545 Hz, 2T adicionais por instrução, 1600T por despacho BIOS, 64T por byte de transferência BIOS, HMMM 16T/byte, HMMV 8T/byte e LMMV XOR 32T/pixel. CPU e VDP avançam em paralelo; S#2 CE é consultado até a conclusão. Cada cenário recebe mais 20 ms de margem para apresentação de quadro/interrupções e deve ficar em até 100 ms.

Valores locais: digitação simples ~34 ms; inserção longa ~70 ms; rolagem ~75 ms; Enter ~74 ms; Backspace ~60 ms; Delete ~77 ms; cursor ~15 ms. São estimativas em ciclos, não medidas no MSX físico. O limite é validado nos cenários cobertos; firmware, waits e outras interrupções do equipamento ainda precisam ser medidos. Rede/disco e preparação inicial da atlas têm seus próprios tempos.

## Vídeo e DOS

O modelo agora separa VRAM física e endereços entrelaçados de SCREEN 7. A versão 0.7.1 falha no teste de restauração física; a nova preserva exatamente os 16 KB físicos do console em modos TEXT1/TEXT2, inclusive após gravar, ler e usar a rede. Atlas, cópias sobrepostas em ambos sentidos, preenchimento e XOR do cursor são verificados por um oráculo independente de layout/pixels.

Também há testes de portas VDP obtidas da BIOS em base 88h, latch de controle com interrupções desabilitadas, retorno a S#0 antes de EI e espera de conclusão de comandos. A correção anterior do bit reservado R#1 permanece.

Sem emulador MSX completo, teste físico da v0.7.2 ou chamada paga/autenticada à API. Publicador e backup usaram execução fora da sandbox após bloqueios de arquivos temporários já conhecidos. O GitHub Actions recompila e repete as cinco suítes antes de gerar a release.
