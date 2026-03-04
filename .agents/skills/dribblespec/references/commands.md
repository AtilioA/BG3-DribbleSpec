# DribbleSpec Command Matrix

- All tests: `dribbles`
- Shorthand: `d`
- Help: `dribbles --help`
- Help topic: `dribbles --help context`
- Name filter: `dribbles --name "pattern"`
- Tag filter (AND): `dribbles --tag runtime --tag server`
- Context filter: `dribbles --context client`
- Fail fast: `dribbles --fail-fast`
- With caller UUID metadata: `dribbles --mod-uuid 00000000-0000-0000-0000-000000000000`
- Reserved JSON path metadata: `dribbles --json-out DribbleSpec/results.json`

## Suggested execution order

1. Targeted check by name/tag.
2. Relevant context run (`--context server` for entity/component suites).
3. Full run.
