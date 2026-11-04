# Pedido de evidências — Mesen 2

**Status 2026-11-04:** E1, E2, E4 e E5 coletados automaticamente com `tools/mesen/` (logs em `docs/traces/`); E3 parcial (falta morte, continue, troca de fase, chefe); E6 OK no Mesen, falta ares. Itens abertos estão em `docs/runtime-hook.md` → Lacunas.

Cada item desbloqueia uma task de `openspec/changes/runtime-palette-switch/tasks.md`.
Para cada um, envie: screenshot do debugger (ou texto do Trace Logger), PC, registradores
(A, X, Y, D, DB, P com flags m/x), e o que estava na tela. Salve traces em `docs/traces/` (texto, sem ROM).

## E1 — Quem roda a leitura de controle (task 1.1)

1. Debugger → breakpoint **Read** em `$4218` (CPU), fase 1 em gameplay normal.
2. Anote o PC de cada hit (esperado: `$81828A` e/ou `$8083D1`) e o **Call Stack**.
3. Diga se o hit está dentro do NMI (stack contém retorno de `$808354`/`$9DB413`) ou no loop principal.
4. Repita pausado (Start) e no mapa/menu.

## E2 — `$1EC9` e uso de L/R (task 1.1)

1. Memory Viewer → CPU `$1EC9` em gameplay: valor observado.
2. Pressione L e R sozinhos: algo muda no jogo? Valor de `$01F4` e `$056D` antes/depois.

## E3 — Todas as escritas em CGRAM `$C0-$CF` (task 1.2)

1. Breakpoint **Write** em CGRAM `$0180-$019F`.
2. Gatilhos: entrar na fase, morrer/continuar, sofrer dano, pegar item, trocar de área, pausar, fim de fase.
3. Para cada hit: PC, `$4300-$4306`, `$4212` (VBlank?), e se foi DMA (`$420B`) ou HDMA (`$420C`).
4. Esperado só `$9DACB0`; qualquer outro PC é crítico (fade/flash) e muda o design.

## E4 — Classificação de pixels (task 1.3)

Escreva manualmente na CGRAM (Memory Viewer → CGRAM) uma cor berrante (ex.: `1F 7C`) em **uma** entrada
por vez de `$C1-$CF`, e capture Mr. Nutz parado, andando, pulando, dano. Diga o que mudou (pelo, roupa,
olhos, sapatos, contorno) e se **outro sprite** (inimigo, item, HUD) também mudou.

## E5 — RAM livre (task 1.4)

Precisamos de ~4 bytes de WRAM sem uso (índices de pelo/roupa + estado anterior do controle).
Candidato a investigar: área `$7F:F000-$7F:FFFF`. Em Mesen: Memory Viewer → WRAM, jogue fase 1,
2 e um continue; confirme se permanece intocada (use **Memory Access Counter / highlight de escrita**).

## E6 — Compatibilidade de expansão (task 1.4)

Teste se a ROM expandida (gerada após E1–E5) carrega no Mesen 2 e no ares; reporte versão dos emuladores.
