> Registro histórico da primeira adaptação MSX2. A interface atual de 32 colunas está descrita em ALTERACOES-32COL.md.

# Alterações em relação à entrega anterior

- MAIN.ASM: verifica geração MSX pelo byte 002Dh da ROM via RDSLT, capacidade VRAM por MODE (FAFCh) e inclui SCREEN7.ASM.
- SCREEN7.ASM substitui SCREEN2.ASM: registradores V9938, bitmap 512×212, fonte expandida para célula 8×8, cursor por célula, dirty rows, backup do console e restauração de 24 registradores.
- ERRORS.ASM: mensagens para MSX1 e VRAM inferior a 128 KB.
- TERMINAL.ASM e NETCONFIG.ASM: identificação visual da versão e geometria. A lógica dos argumentos é idêntica.
- CONFIG.ASM e build.py: comentários de identificação atualizados; mapa de RAM e contrato do montador preservados.
- tests/test-msxchat.cjs: modelo de VRAM de 128 KB, registradores estendidos, oráculo pixel a pixel, isolamento do cursor, rejeição de hardware insuficiente e restauração de estado.

Gateway, UNAPI, HTTP, persistência, editor e protocolo foram reaproveitados. PROVENANCE.json registra hashes e igualdade dos componentes principais.

Não foi transferido para esta adaptação o aceite por premissa da versão MSX1. Os testes locais e o ensaio físico têm registros separados.
