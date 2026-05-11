# TODO

## SolidYAML

### Completed: Split YAML Flow Lexing From Structural Event Assembly

YAML flow parsing now uses two internal stages:

1. `YAMLFlowLexer` emits lower-level lexical tokens from retained byte regions.
2. A structural adapter consumes those tokens with lookahead and emits `YAMLRawToken`.

Target shape:

```text
YAML byte scanner
  -> YAML lexical tokens
  -> YAML structural adapter
  -> YAMLRawToken
  -> ParseEvent / YAMLNodeBuilder
```

Completed goals:
- YAML ambiguity is explicit in the structural adapter instead of recursive flow parsing.
- Retained scalar regions flow through lexical tokens when bytes are unchanged.
- Lookahead for `:`, `,`, `]`, `}`, explicit `?`, empty keys/values, tags, anchors, and aliases is centralized in the structural adapter.
- The old whole-flow materialization gate and recursive flow grammar buffering are removed.

Future follow-up:
- Consider applying the same lexer/structure split to block-line tokenizer internals if profiling shows the remaining block semantic code is a bottleneck.
