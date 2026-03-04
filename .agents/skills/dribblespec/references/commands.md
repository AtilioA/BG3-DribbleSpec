# DribbleSpec Command Matrix

- All tests: `dribble`
- Help: `dribble --help`
- Help topic: `dribble --help context`
- Name filter: `dribble --name "pattern"`
- Tag filter (AND): `dribble --tag runtime --tag server`
- Context filter: `dribble --context client`
- Fail fast: `dribble --fail-fast`
- With caller UUID metadata: `dribble --mod-uuid 00000000-0000-0000-0000-000000000000`
- Reserved JSON path metadata: `dribble --json-out DribbleSpec/results.json`

## Suggested execution order

1. Targeted check by name/tag.
2. Relevant context run (`--context server` for entity/component suites).
3. Full run.
