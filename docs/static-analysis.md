# Análise estática — troca de paleta em runtime

Fonte: bytes da ROM `Mr. Nutz (USA) (En,Fr).sfc` (SHA-256 `3472dd57…8a16`), lidos com
`npm run rom:header` e `npm run rom:disasm -- <$BB:AAAA> <len-hex> [--m16] [--x16]`.
Disassembly estático é linear e depende das larguras M/X assumidas; **não substitui trace do Mesen**.

Legenda de confiança: **[byte]** = lido diretamente da ROM e coberto por teste em `tests/snes.test.ts`;
**[hipótese]** = interpretação ainda sem trace.

## Header e vetores [byte]

| Campo | Valor |
| --- | --- |
| Título | `MR.NUTZ` |
| Map mode (`$FFD5`) | `$30` = LoROM + FastROM |
| ROM size | `$0A` = 1 MiB; SRAM nenhuma; região `$01` (USA) |
| Checksum / complemento | `$7E78` / `$8187` (válido, XOR = `$FFFF`) |
| Vetores nativos | NMI `$8349`, IRQ `$83B3`, BRK `$83EC`, COP `$83B3` |
| RESET (emulação) | `$80B5` |

## Carga da paleta do personagem [byte]

1. `$82:8837-$828886` copia ponteiros de um descritor por cena (`$99:0051,X…$99:0057,X`) para
   `$055A` (BG src), `$055C` (BG bank), `$055E/$0560` (ponteiro longo para tabela de paletas de sprite).
   Com `$13B8≠0` usa cópias salvas em `$7FB513-$7FB519` [hipótese: restauração após checkpoint/continue].
2. `JSL $9DABA7` (chamado de `$828AC5`, `$9CF764`, `$9DAE49`, `$9DC3BB`, `$9DC7DC`, `$9DE127`, `$9DE452`)
   inicializa a PPU da cena com `D=$2100` e termina em `$9DAC4D-$9DACB7`:
   - `$9DAC57-$9DAC7B`: DMA canal 0 → `$2122`, 256 bytes de `$055C:$055A` (CGRAM `$00-$7F`, BGs).
   - `$9DAC7E-$9DACB5`: loop de 8× (`$14=8`) lendo `[$10]` = 4 bytes (addr16, bank16) por paleta e
     fazendo DMA de 32 bytes → CGRAM `$80`, `$90`, … `$F0` em sequência (CGADD não é reescrito).
   - `$9DACB7`: `RTL`.
3. Tabelas de ponteiros em `$82:D454+` (file `0x15454+`): 27 ocorrências de `$85:9CC0`, sempre no
   slot 4 (CGRAM `$C0`). Os captures antigos (`X=$9C60/$9D80`, `A=$0085`) são o `LDA [$10]` deste loop.

**[hipótese]** A paleta `$C0-$CF` é carregada só no setup de cena (tela em forced blank via
`$9DAB48`: `$2100=$80` + espera VBlank), não por frame. Logo, uma escrita runtime em CGRAM persiste até
a próxima chamada de `$9DABA7` — mas fades/flashes de dano podem reescrevê-la por outro caminho.

## Outras escritas em CGRAM [byte] / [hipótese]

- `$2121`/`$2122` diretos: `$818F65`, `$82813C`, `$81C3F3-$81C404`, `$8BFCC1` (não analisados).
- HDMA para `$2122` em `$9DB9AE`, `$9DB9E8`, `$9DBE0E`, `$9DCAC9`, `$9DDC8B`, `$9DEA28`, `$9DEA62`.
  O setup de `$9DB997` escreve CGADD `$00` (backdrop) via tabela indireta `$82:E4AA` [hipótese: degradê de céu].
- Banco `$81`/`$85`/`$87`/`$8B` e outros têm `LDA #$22` próximos a DMA; não classificados.

## Controle [byte]

- `$4218` (joypad 1) → WRAM `$1A6F` (word); `$421A` (joypad 2) → `$1A71`. Sites: `$8083CB-$8083D4`
  (caminho de NMI com `$13B4≠0`, pausa [hipótese]) e `$818284-$81828D` (A 16-bit).
- `$8182F1-$818333`: se `$1EC9` bit0 = 1, **R (`$0010`) e L (`$0020`) já têm função** (escrevem
  `$01F4` de `$7FB00D/$7FB00E` e `$056D=1`) [hipótese: recurso de debug/cheat]. Possível conflito com
  `Select+L`/`Select+R`.
- `$8183A0`: Start (`$1000`) alterna `$13B4/$13B5` [hipótese: pausa].

## NMI [byte]

`$808349: JML $80834D` → salva registradores → `JMP ($01DC)`. `$01DC` recebe `$8357`
(`JML $9DB413`, gravado por `$9DAF0C`, `$9DC44F`, `$9DE17D`…) ou `$835B` (`$808213`, `$9DF630`).
**[hipótese]** `$9DB413` é o NMI de gameplay; não confirmado se `$818284` roda dentro do NMI ou no loop principal.

## Espaço livre [byte]

Única sequência de filler ≥ 256 bytes: `$9DA500-$9DA5FF` (256 × `$00`), sem prova de que não é usada.
A ROM de 1 MiB está praticamente cheia ⇒ o código runtime deve ir em **expansão de ROM** (ver design da change).

## Correções após traces no Mesen 2.2.1 (2026-11-04)

- `$01DC` vale **`$835B`** durante gameplay (`$8357` só em telas anteriores) [trace]. Estaticamente, o NMI `$80835B` pode desviar para
  `JML $8180F4` [hipótese]; a leitura de controle `$81828A` roda no fim do frame (scanline 231-259; 2 em lag frame) [trace].
- Hipótese "paleta só no setup de cena": confirmada para boot, menus e fase 1 (`docs/traces/trace-palette.log`).
- Hipótese "L/R já têm função": o bloco existe, mas `$1EC9=$00` em gameplay — desligado no trecho testado.
- Detalhes do hook implementado: `docs/runtime-hook.md`.
