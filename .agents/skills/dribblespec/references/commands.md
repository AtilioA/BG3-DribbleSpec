# DribbleSpec Command Matrix

- All tests: `dribbles`
- Shorthand: `d`
- Help: `dribbles --help`
- Help topic: `dribbles --help context`
- Name filter: `dribbles --name "pattern"`
- Tag filter (AND): `dribbles --tag runtime --tag server`
- Context filter: `dribbles --context client`
- Fail fast: `dribbles --fail-fast`
- Consumer alias run, if `commandAlias` is defined in RegisterTestGlobals.
- Reserved JSON path metadata: `dribbles --json-out DribbleSpec/results.json`

## Suggested execution order

1. Targeted check by name/tag.
2. Relevant context run (`--context server` for entity/component suites).
3. Full run.
