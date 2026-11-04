# Proposal: Runtime palette switching

## Why
O patch estático funciona, mas o usuário quer selecionar e trocar cores dentro do próprio jogo, sem regenerar ROM.

## What Changes
- Criar conjuntos de paletas pré-definidas para pelo e roupa, com default original.
- Implementar troca de paleta dentro da fase com atalhos de controle (`Select+L` para pelo, `Select+R` para roupa), evitando conflitos com controles originais.
- Adicionar aplicação da seleção na CGRAM durante um momento seguro de atualização.
- Distribuir alteração como IPS e permitir restauração do visual original.

## Capabilities

### New Capabilities
- `runtime-palette-switch`: Alternância independente de paletas em tempo de jogo via comandos e atualização da CGRAM.

### Modified Capabilities
- `ips-build`: Suporte à futura inclusão de código/novos dados 65C816 e patches não limitados à paleta estática, com manifesto explícito e validação rígida.

## Impact
Requer engenharia reversa de rotinas de controle e DMA, eventual free-space da ROM, ferramentas de assembler e testes no emulador. Não há código runtime implementado nesta entrega.
