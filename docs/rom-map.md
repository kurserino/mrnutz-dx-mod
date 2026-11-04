# Mapa da ROM — Mr. Nutz (USA) (En,Fr)

## Proveniência e limites

- Arquivo original fornecido pelo usuário: `Mr. Nutz (USA) (En,Fr).sfc`, 1,048,576 bytes, sem header copier.
- O tamanho e a assinatura de paleta foram confirmados diretamente contra os bytes enviados.
- Os IDs CRC32/SHA256 são obtidos do arquivo pelo comando `npm run rom:inspect`; não confie em IDs transcritos de fóruns.
- Mapeamento SNES: LoROM observado. Endereço CPU `$85:9CC0` → file offset `0x029CC0` pela regra `(bank & 0x7F) * 0x8000 + (address & 0x7FFF)` (válida somente para regiões ROM do mapeamento).
- 32 bytes de paleta no offset `0x029CC0..0x029CDF`, 16 entradas BGR555 little-endian.
- Sprite Viewer: seis objetos OAM indexados 0–5, todos com palette index 4, CGRAM entry `$C0` (confirmado em capturas).
- CGRAM color entries `$C0-$CF`, equivalentes aos byte offsets `$0180-$019F` em um dump CGRAM.
- Entrada `$C0` = cor transparente; não modificar.
- Índices `$C1-$C5`: tons neutros (brancos/cinzentos).
- Índices `$C6-$C9`: tons amarelo/oliva, presumivelmente roupa; verificar nos sprites.
- Índice `$CA`: preto.
- Índices `$CB-$CF`: vermelho escuro → vermelho vivo, presumivelmente pelo; verificar nos sprites.
- A modificação manual de `$C1` na CGRAM foi visualizada no Mesen, comprovando a associação com pelo menos uma cor do personagem, mas **não** prova a categorização dos demais pixels.

## Bytes originais — fonte verificada contra ROM fornecida

```
$859CC0 / 0x029CC0:
00 00 CE 49 52 5A D6 6A 5A 7B DE 7B 1A 03 92 02
8A 01 C8 00 00 00 0E 00 12 00 16 00 1A 00 1E 00
```

| Entry | ROM offset | Original (little-endian) | Initial hypothesis |
| --- | --- | --- | --- |
| C0 | 029CC0 | 00 00 | Transparent |
| C1 | 029CC2 | CE 49 | Neutral shadow |
| C2 | 029CC4 | 52 5A | Neutral |
| C3 | 029CC6 | D6 6A | Neutral |
| C4 | 029CC8 | 5A 7B | Neutral |
| C5 | 029CCA | DE 7B | Highlight |
| C6 | 029CCC | 1A 03 | Outfit highlight |
| C7 | 029CCE | 92 02 | Outfit base |
| C8 | 029CD0 | 8A 01 | Outfit shadow |
| C9 | 029CD2 | C8 00 | Outfit dark |
| CA | 029CD4 | 00 00 | Black |
| CB | 029CD6 | 0E 00 | Fur darkest |
| CC | 029CD8 | 12 00 | Fur dark |
| CD | 029CDA | 16 00 | Fur mid |
| CE | 029CDC | 1A 00 | Fur base |
| CF | 029CDE | 1E 00 | Fur highlight |

## Mesen traces and caveats

- A CGRAM write breakpoint at byte offsets `$0182-$0183` caught a DMA invocation near CPU `$9DACB4`.
- Before DMA, a call at `$9DACA3` sets DMA source from `X` + `A`. In one capture `X=$9C60`, `A=$0085`, `CGRAM Addr=$90`; in another `X=$9D80`, `A=$0085`, `CGRAM Addr=$80`.
- Captures of CPU `$85:9CC0` showed the exact complete palette bytes above. This **is the static source**, but the DMA assembly flow should still be traced carefully for the in-game recoloring feature.
- `CGRAM Addr` is hardware state that may advance during DMA; do not assume it always displays the start address at the post-DMA breakpoint.
- Do not generalize to other regional revisions without explicit mapping and signatures.

## Análise estática (2026-11-04)

Detalhes e níveis de confiança em `docs/static-analysis.md`. Resumo:

- Header: LoROM + FastROM (`$30`), checksum válido, NMI `$8349` → `JMP ($01DC)`.
- O breakpoint antigo em `$9DACB4` é o loop de 8 paletas de sprite de `$9DAC7E-$9DACB5`, cauda da rotina de init de cena `JSL $9DABA7`.
- Ponteiros de paleta: tabelas em `$82:D454+`, slot 4 = `$85:9CC0` (27 ocorrências).
- Controle: `$4218` → `$1A6F` em `$81828A`/`$8083D1`. L/R têm uso condicional em `$8182F1`.
- Sem espaço livre comprovado na ROM de 1 MiB.

## Extension work

1. Confirm stable palette across all animations, costumes, levels, damage states and reloads.
2. Trace controller input and safe VBlank palette uploads in Mesen (see `docs/debugging-playbook.md`).
3. Identify free-space or expand ROM safely with validated LoROM header changes.
4. Patch runtime selection logic, maintain default palette, protect other objects sharing palette index 4.
5. Include reproducible patch byte diffs in release reports.
