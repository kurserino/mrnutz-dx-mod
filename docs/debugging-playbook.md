# Playbook de debug — Mesen 2

## Paleta do personagem

1. Inicie uma fase com Mr. Nutz visível.
2. `Debug > Sprite Viewer`: confira se os 6 sprites OAM selecionados usam Palette index 4 / Palette address `$C0`.
3. `Debug > Palette Viewer`: selecione `$C0` e veja as entradas `$C0-$CF`.
4. `Debug > Memory Viewer`, Memory Type `CGRAM (Palette)`: use **Go To Address**, não **Find**. Abra `0180`.
5. CGRAM armazena 2 bytes por entrada, em little-endian BGR555. Uma cor visível pode não se atualizar até retomar a emulação.
6. Para rastrear carregamento: debugger breakpoint de WRITE `CGRAM` `$0182-$0183`; para investigar origem DMA confira `$4300-$4306` e `$420B`.
7. Para ASM, diferencie registradores antes/depois do DMA e não conclua a fonte só pelo PC.
8. Consulte `docs/rom-map.md` para bytes originais verificados.

## Validação obrigatória de cada patch

- Abra o jogo no Mesen e percorra a primeira fase.
- Captura antes/depois do personagem parado, andando, pulando, sofrendo dano, entre áreas.
- Confirme roupa e pelo visualmente, e verifique se outros sprites compartilham a paleta.
- Confirme que gameplay, vidas, HUD, itens, música, transição de nível e saves não mudaram.
- Teste ROM patchada diretamente se soft-patching IPS não for detectado.
- Para futuras hooks dinâmicas: teste NMI, IRQ, VBlank timing, save states, reset, collisions e performance.

## Critério de evidência

Todo endereço novo deve ter captura do debugger, instrução/disassembly, origem/destino, resultado observável e teste de regressão.
