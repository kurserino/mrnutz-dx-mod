# Hook runtime — troca de pelo e roupa no jogo

Status: **implementado e verificado em Mesen 2.2.1 (headless)** na fase 1. Falta smoke test manual
(Mesen GUI) e cobertura de morte/continue/troca de fase — ver "Lacunas".

## Controles

| Atalho | Efeito |
| --- | --- |
| `Select` + `L` | próximo preset de **pelo** (`$CB-$CF`) |
| `Select` + `R` | próximo preset de **roupa** (`$C6-$C9`) |

Cada atalho avança uma vez por pressionamento (borda de subida de L/R com Select segurado).
O índice 0 de cada grupo é a paleta original da ROM; após o último preset volta ao 0.
Presets em `presets/runtime.json` (até 11 por grupo).

## Evidência (Mesen 2.2.1, `npm run trace:*`, logs em `docs/traces/`)

| Fato | Fonte |
| --- | --- |
| Paleta `$C0` carregada só no init de cena: DMA `$85:9CC0 → CGRAM $0C0` em `$9DACB3` | `trace-palette.log` (frames 45, 1607) |
| Cor escrita em runtime persiste ≥ 1120 frames andando/pulando | `trace-palette.log` (`PERSIST`, nenhuma mudança) |
| `$81:828A LDA $4218` roda 1×/frame em gameplay com `M16 X16 DBR=$00 D=$0000`, nativo | `trace-hook-site.log` |
| Scanline nesse ponto varia: 231, 243, 259 e **2** (lag frame) | `trace-hook-site.log` |
| `$1EC9=$00` em gameplay; L/R/Select não alteram `$01F4/$056D` | `trace-palette.log` (`RAM`) |
| `$C1-$C5` branco/cinza, `$C6-$C9` boné+colete amarelos, `$CA` preto, `$CB-$CF` pelo vermelho; nenhum outro sprite na tela usa a paleta 4 | varredura E4 (`trace-palette.lua`, screenshots em `output/traces/`) |
| WRAM `$7FB6C0-$7FBFFF` sem leitura nem escrita no jogo inteiro, créditos, reset e boot | `sweep-wram.log` |
| Leitura de CGRAM via `$213B`: bit 15 é open bus (lido `$CFBF` para `$4FBF`) | depuração do hook |
| ROM 2 MiB boota; hook roda 1345/1345 frames; ciclo de presets e persistência OK | `verify-runtime.log` |

## Alterações na ROM (manifesto em `src/runtime.ts`, relatório em `output/runtime-report.json`)

| File offset | CPU | Original | Novo | Motivo |
| --- | --- | --- | --- | --- |
| `0x7FD7` | `$80:FFD7` | `0A` | `0B` | header: 1 MiB → 2 MiB |
| `0x7FDC-0x7FDF` | `$80:FFDC` | `87 81 78 7E` | recalculado | checksum/complemento da imagem de 2 MiB |
| `0x0828A-0x0828F` | `$81:828A` | `AD 18 42 8D 6F 1A` | `22 00 80 A0 EA EA` | `JSL $A08000` + `NOP NOP` |
| `0x100000+` | `$A0:8000` | (expansão) | código do hook | ver abaixo |
| `0x100400+` | `$A0:8400` | (expansão) | tabela de pelo + offsets em `+$70` | presets |
| `0x100480+` | `$A0:8480` | (expansão) | tabela de roupa | presets |
| `0x100000-0x1FFFFF` | `$A0-$BF` | (expansão) | `$FF` (RLE) | preenchimento |

A paleta estática `0x029CC0` **não** é alterada pelo patch runtime.

## Fluxo do hook (`$A0:8000`)

1. Executa as instruções originais relocadas (`LDA $4218`, `STA $1A6F`) com o DBR original.
2. Salva `P, X, Y, DBR`; `DBR=$A0` (I/O e WRAM baixa continuam espelhados nos bancos `$80-$BF`).
3. Inicializa o estado em `$7FBE00` se o magic `"NZ"` (`$5A4E`) não estiver presente.
4. Detecta borda: `pressed = (cur ^ prev) & cur`; com Select segurado, L/R avançam os índices.
5. Só toca a CGRAM se `$4212` bit 7 (VBlank) e scanline ≤ 250; senão tenta no próximo frame.
6. Lê `$C6` e `$CF` da CGRAM e decide:
   - já igual à seleção → nada;
   - igual à **original** (cena recarregada) ou à **última aplicada** (troca de preset) → grava 9 cores;
   - qualquer outro valor → outra paleta ocupa o slot 4: **não grava**.
7. Restaura registradores e retorna (`RTL`); a próxima instrução original (`LDA $1A04`) redefine N/Z.

Estado em WRAM: `$7FBE00` magic, `$7FBE02` índice do pelo, `$7FBE03` índice da roupa,
`$7FBE04` controle anterior, `$7FBE06/$7FBE08` últimas cores aplicadas (slot+6/slot+15), `$7FBE0A` slot.
Até 2026-11-04 o estado ficava em `$7FFFF0`, que o jogo limpa em algumas mudanças de mundo.

## Reset / persistência

- Power-on: WRAM sem magic → índices 0 (visual original).
- Reset: a seleção **persiste** após soft reset (verificado em `sweep-all.log`).
- Mudança de mundo: a seleção **persiste** (varredura completa, nenhuma perda).
- Troca de cena: o init recarrega a paleta original da ROM; o hook detecta isso e reaplica no próximo
  frame de gameplay com VBlank livre (1 frame com a cor original no máximo na varredura completa).

## Lacunas antes do release

- Smoke test manual no Mesen GUI (task 3.3).
- Chefes e continue/game over (task 3.3); morte, troca de estágio e natação já verificados (ver abaixo).
- Decidir se a seleção deve sobreviver à mudança de mundo (hoje volta ao original).
- Reset (persistência acima).
- Desligar o console apaga a WRAM: a seleção volta ao original no power-on. Persistir além disso exigiria SRAM,
  e o jogo trava se detectar SRAM (checagem anticopiadora em `$80:83EF`, `$70:0034`).

## Verificação estendida (2026-11-04, Mesen 2.2.1 headless)

- **Pulo de estágio de debug** (`$1EC9` bit0 + R, só na RAM do emulador): confirmado — avança estágios
  (`docs/traces/probe-warp.log`; script substituído por `npm run sweep:prepare`). Usado apenas para testes.
- **Troca de estágio:** seleção mantida em todas as áreas de gameplay 1-16. Telas de intro/"Stage Clear"
  mostram a cor original (o hook só roda em gameplay).
- **Mudança de mundo:** entre as áreas 17 e 18 o jogo limpou a WRAM do estado (`idx` voltou a `0/0`) →
  **a seleção voltava ao original ao trocar de mundo.** Corrigido movendo o estado para `$7FBE00` (ver abaixo).
- **Paleta estrangeira:** na área 26 o slot 4 continha `C6=$728A`, `CF=$7BDE`; o hook não gravou (proteção OK).
- **"The Living Room" (área 33), NÃO é natação** (corrigido pelo usuário: pendurado na corrente, andando, rolando em canos):
  1800 frames sem mudança em `$C6/$CF`, sem DMA para `$C0-$CF`, hook 1800/1800 frames. Inclui contato com a
  água suja que causa dano (`swim-0160`, identificado pelo usuário): a cor não mudou. Não confirmado se o dano
  ocorreu de fato (HUD não foi lido). Natação: ver item abaixo.
  (`docs/traces/probe-swim.log`; script removido, coberto por `npm run sweep:all`).
- **Natação em água azul com peixes (áreas 35 e 37 da varredura longa, apontadas pelo usuário):** verificado.
  Scripts `probe-swim-blue` removidos; as fases com água (estágios 13-15 de `sweep:prepare`) são cobertas por `npm run sweep:all`.
  - Cores trocadas **durante** a natação (`Select+L` em t=200, `Select+R` em t=260) e mantidas submerso.
  - OAM: o Mr. Nutz continua na **paleta 4** debaixo d'água (área 37: 6 sprites p4 constantes; o polvo usa p5).
    O tom azulado é efeito da água sobre a cena, não troca de paleta; rosa/verde ficam visíveis sob o tom.
  - Morte na água: DMA `$85:9CC0 → $C0` restaura a original; o hook reaplica em 5-16 frames.
  (`docs/traces/swim-blue-35.log`, `docs/traces/swim-blue-37.log`)

## Varredura do jogo inteiro (2026-11-04, `npm run sweep:all`, `docs/traces/sweep-all.log`)

Do Woody Land 1 até os créditos e a tela final, via pulo de estágio de debug, com ciclo de ações em cada
estágio (andar, correr, pular, Y/X/A, agachar, olhar para cima, voltar), pausa/despausa, checkpoints que
restauram vidas e, no fim, um soft reset. Seleção usada: pelo 2 (azul), roupa 3 (roxo).

- **Bug encontrado e corrigido:** o slot de CGRAM do Mr. Nutz **varia por cena**. No estágio 10 da varredura
  a tabela `[$055E] = $82:D60C` coloca `$85:9CC0` no **slot 0** (`$80`) e o Mr. Nutz usa `pal=0`
  (`docs/traces/sweep-debug10.log`). O hook agora procura `$85:9CC0` nos 8 slots da tabela atual a cada
  frame (`find_slot`) e escreve no slot encontrado; se nenhum slot contém a paleta, não escreve nada.
- **Resultado:** em todos os estágios com gameplay (0-36 jogáveis + créditos), 100% dos frames de gameplay
  com a seleção na CGRAM do slot correto; o máximo sem a seleção foi 1 frame (reaplicação após recarga).
  Revisão visual: Mr. Nutz azul/roxo em todas as fases, incluindo chefes, neve, nuvens, circo e vulcão.
- **Reset:** a seleção **persiste** após soft reset (`idx=2/3`, magic intacto) e é aplicada ao voltar ao
  gameplay.
- **Mudança de mundo:** com o estado antigo (`$7FFFF0`) o jogo zerava a seleção em algumas transições.
  Com o estado em `$7FBE00`, nova varredura completa: **nenhuma perda (`SELECTION_LOST`) em 71 estágios + reset**.
- **Telas sem gameplay** (intro, "Stage Clear", créditos, mapa de continue) mostram a cor original.
- Sprites sem a paleta do Mr. Nutz por até 32 frames em alguns estágios (piscando após dano/fora da tela);
  a CGRAM continuou correta.

Notas de ferramenta: o `--testRunner` do Mesen 2.2.1 encerra scripts longos com exit -1 sem `--timeout`
(o runner passa `--timeout=3600`); o callback de carga de savestate fica restrito ao vetor de reset `$00:80B5`
para não executar Lua a cada instrução.

## Só o Mr. Nutz muda de cor (2026-11-04) — substitui o fluxo "grava no slot S" acima

**Problema (relatado pelo usuário):** a lagarta das nuvens, e outros objetos, usam a **mesma paleta** `$85:9CC0`
do Mr. Nutz. Gravar as cores escolhidas no slot `S` do Mr. Nutz mudava esses objetos também.
`docs/traces/sweep-analyze.log` mostra objetos no slot dele em quase todas as fases (tiles `$064`, `$060-$062`,
`$100-$12E`, `$104/$16E/$1C4`, `$0CC-$0EC`…), enquanto o Mr. Nutz usa sempre tiles `$000-$046` da tabela 0.

**Solução:** paleta privada.
- Segundo hook em `$81:C36A` (`LDA #$4300 / TCD` → `JSL oam_hook`), dentro do upload de OAM `$81:C367`, antes do DMA
  do buffer `$00:0321` (`$0024` bytes). Roda 1×/frame, scanline 225-243 (`sweep-oamtiming.log`).
- O hook escolhe um slot `X` ≠ `S`, **no mesmo grupo de color math** (0-3 ou 4-7; só 4-7 sofrem color math), que
  nenhum outro objeto usou desde que a tabela de paletas da cena mudou (`stickyMask`). O upload completo de 512
  bytes das cenas de chefe (partes fixas na OAM alta) também é escaneado, mesmo fora do VBlank.
- Grava em `X` a paleta do Mr. Nutz com as cores escolhidas e troca o campo de paleta **só** das entradas do
  Mr. Nutz (tile < `$50`, tabela 0, paleta `S` ou `X`). **`S` nunca é escrito.**
- Se outro objeto passar a usar `X`, `X` recebe de volta a paleta da tabela da cena antes do DMA.
- Sem slot livre no grupo: o Mr. Nutz fica com a cor original naquela cena (nada é corrompido).
- O hook `$81:828A` agora só trata `Select+L/R`.

**Verificação (`npm run sweep:all`, jogo inteiro, oráculo novo):**
- `sharedChanged=0` em todos os estágios: o slot `S` sempre igual à ROM → objetos que dividem a paleta intactos.
- `foreignOnX=0` em todos os estágios: nenhum outro sprite visível usou `X` com as cores do Mr. Nutz.
- Mr. Nutz com a seleção em 100% dos frames visíveis em todas as fases, **exceto**: chefe aranha (Woody Land 5)
  e créditos, onde os 4 slots do grupo 4-7 estão ocupados → cor original nessas cenas.
- Seleção persistente em mudanças de mundo e após reset.

**Limite conhecido:** no chefe aranha o color math de sprites está desligado (`sweep-colormath.log`), então um
slot do grupo 0-3 teria a mesma aparência, mas `$2131` é só-escrita e o jogo o grava com constantes (sem cópia em
WRAM, `$85:939C`). Usar o grupo 0-3 ali exigiria uma lista de cenas validadas — não implementado.

## Hook v3: orçamento de VBlank e testes rápidos (2026-11-04)

**Bug achado pela varredura rápida:** o hook v2 escaneava todas as entradas de OAM dentro do upload de OAM
(caminho crítico). Isso atrasava o resto do NMI ~25 scanlines: a habilitação de HDMA (`$420C`, em `$81:81F6`)
passava de 233-237 para 258-261 e, num frame, para o scanline 0 → a HDMA começava com estado velho e escrevia
cores no slot do Mr. Nutz (estágio 04, `docs/traces/stage04-*.log`).

**Arquitetura v3:**
- `oam_hook` (crítico): só uma passada leve no buffer em uso (`$0024` bytes): campo de paleta = S ou X? Entradas
  do Mr. Nutz vão para X; outro objeto em X → X recebe a paleta da cena na hora (VBlank) e o Mr. Nutz fica original
  naquele frame. Antes, confere na CGRAM se X ainda tem a seleção (recarga de cena, respawn).
- `input_hook` (`$81:828A`, depois da habilitação de HDMA): atalhos + gerenciador. Lê 16 entradas da **OAM do PPU**
  por frame via `$2138` (o buffer `$0321` tem lixo além da parte em uso; a OAM real tem `y=$E0` nas vazias) e
  restaura OAMADD como o jogo (`$0026 >> 1`). Entradas além da parte em uso (peças fixas de chefe) entram numa
  máscara permanente da cena; as dinâmicas, numa janela de duas passadas. Só usa X depois de uma passada completa.
- `ready` vale só se o gerenciador rodou nos últimos 2 frames (`$01DA`), então o hook de OAM não age fora do gameplay.
- CGRAM só é acessada pelo gerenciador quando slot/pelo/roupa mudam.

**Testes rápidos** (`tools/mesen/`, `tools/mesen/lib.lua` com o oráculo comum):
- `npm run sweep:prepare`: uma vez, na ROM original — um savestate por estágio em `output/states/` (40 estágios).
- `npm run sweep:all`: gera o patch atual, roda `stage-check.lua` em todos os estágios em paralelo (~35 s) e
  `persist-check.lua` (8 pulos de estágio + reset). Falha (exit 1) com `sharedChanged`, `foreignOnX`,
  `hdmaLate` (HDMA habilitada na área visível) ou atalho/persistência quebrados. Relatório: `docs/traces/sweep-all.log`.
- `npm run sweep:stage -- 14,15`: só alguns estágios.
- `npm run research:sweep`: varredura longa antiga, só para os modos de investigação.

**Resultado v3:** 0 violações em 40 estágios; persistência 6/6; HDMA sempre habilitada em VBlank (máx. scanline 255).
Mr. Nutz com a seleção em ≥ 99% dos frames em 34 estágios; menos onde não há slot livre (chefe aranha 0%,
estágio 04 ~45%, 33 ~91%, 02 ~87%) — nesses frames ele fica com a cor original e nada mais muda.

## Piscada na troca de cor (2026-11-04)

**Sintoma (relatado pelo usuário):** ao trocar de cor, o Mr. Nutz às vezes "piscava".
**Causa medida** (`tools/mesen/flicker-check.lua`): a cor nova era gravada pelo gerenciador (`input_hook`, scanline
231-259), que só pode tocar a CGRAM até o scanline 250. Quando rodava tarde, adiava a gravação e desligava o
`ready` → no frame seguinte o Mr. Nutz aparecia com a **cor original** e só depois com a nova (estágios 13 e 21).
Também, ao voltar de uma pausa/cena sem gameplay, o carimbo de frame ficava velho → 1 frame original.
**Correção:** o gerenciador só calcula as cores e marca `pending`; o upload (e a devolução da paleta ao voltar para a
cor original, e a regravação após recarga de cena) é feito pelo `oam_hook`, sempre no início do VBlank. O `oam_hook`
age quando o NMI é o de gameplay (`$01DC=$835B`) e a tabela de paletas é a que o gerenciador preparou.
**Verificação:** `sweep:all` roda o teste de piscada em todos os estágios (24 trocas + pausa): `flash=0` em 40/40.
Resta, por desenho, 1 frame com a cor original quando outro objeto toma o slot privado (`slotSwitch`, 1 caso no
estágio 35): trocar de slot no mesmo frame dobraria o trabalho no caminho crítico (risco de estourar o VBlank).
A troca de cor tem 1 frame de latência normal (o frame em que o botão é lido ainda mostra a cor anterior).
