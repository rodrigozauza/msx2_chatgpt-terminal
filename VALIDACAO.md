# Validação — v0.7.1

211 testes do executável Z80, 37 do gateway, 18 do servidor LAN, 12 do publicador e 16 de backup: total esperado 294. Consulte os relatórios JSON e RELEASE.json para o resultado gerado pelo empacotamento, que exige todos PASS e o hash do COM testado.

A regressão de inicialização usa estados R#1 com bit 7 desligado (10h/30h/50h/70h/60h/68h), MSX2/MSX2+, modos de console 40/80 colunas, SD e rede. Mantém um estado legado F0h e verifica restauração exata do console. Os valores escritos pelo aplicativo em SCREEN 7 não ligam o bit reservado.

A suíte também verifica bitmap, coluna 80, fonte e acentos, cursor, editor de 2047 bytes, rolagem, histórico, JSON/UTF-8 inválido, journal, cancelamento, falhas de disco, HTTP 202, timeout e recuperação. Os asserts do montador verificam o mapa de buffers. Gateway inclui a regressão para instruções de 80 colunas.

O COM real é executado sobre a CPU Z80 incluída, com BIOS, VRAM, DOS e TCP/IP UNAPI simulados. Testes PC usam fixtures locais. Sem chamada paga/autenticada à API; sem emulador MSX completo; sem teste físico. A nova versão precisa ser revalidada no equipamento que apresentou o erro. As prévias são reconstruções da VRAM simulada.

O teste antigo que esperava rejeitar R#1=70h estava incorreto e foi substituído por testes de inicialização bem-sucedida. A análise detalhada está em docs/CORRECAO-BIOS-R1.md.

Publicador e backup precisaram de repetição fora da sandbox do Windows por bloqueio de operações em pastas temporárias. O workflow publica somente depois de recompilar, executar as cinco suítes, conferir SHA256SUMS.txt e verificar o ZIP.
