# Arquitetura

Pipeline determinístico:

```
source ROM -> identity and signature check -> palette preset
           -> BGR555 encoder -> narrow byte diff -> IPS encoder
           -> replay IPS -> compare expected 32-byte target
           -> patched ROM + ips + JSON report
```

TypeScript CLI é a implementação de referência para patch estático. `src/core.ts` contém operações puras de validação, cor, diff e IPS. `src/cli.ts` faz I/O.

Expansão de código 65C816 (futuro) deve ficar em `asm/` e ser compilada por assembler apropriado validado em Windows. Não inserir ASM inventado em patch final sem tracing de hooks e testes reais.

Arquivos de saída (`output/`) e ROMs (`roms/`) são privados e ignorados por Git. Patch IPS e relatórios podem ser distribuídos separadamente conforme legalidade local; não publicar ROM.
