# Agentic evaluation

Produced by `node scripts/eval-agentic.mjs`. Every number is read from the
transcript or from `roc check`, never from the model's prose.

## Per arm

A footer column reading `none shown` means the model never called a tool that
emits one, not that it ignored one. Scope footers appear on `search`,
`search_symbols` type queries, the `list_roc_index` kinds, and a `search_roc_syntax`
miss. The host-tier footer appears on `search` and `get_builtin_module`.

| Arm | Runs | `tools/list` | Compiles | Set `scope` | Called `roc_check` | Footer retries | Host footers | Tool output | Output tokens | Cost |
|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 4 | 3968 tok | 4/4 | 17% (4/24) | 4/4 | none shown | none shown | 27.0k ch | 3.3k | $0.47 |
| text-only | 4 | 2569 tok | 4/4 | 9% (2/23) | 4/4 | none shown | 1/1 followed | 21.3k ch | 3.2k | $0.45 |
| search-symbols | 4 | 2683 tok | 4/4 | 35% (9/26) | 4/4 | 0% (0/3) | none shown | 23.4k ch | 1.9k | $0.29 |
| search-project-symbols | 6 | 2665 tok | 6/6 | 0% (0/13) | 6/6 | none shown | none shown | 12.1k ch | 2.3k | $0.28 |
| query-lists | 6 | 2697 tok | 6/6 | 23% (7/31) | 6/6 | none shown | none shown | 21.8k ch | 2.8k | $0.34 |

## Per run

| Arm | Task | Wants | Scopes used | First call | Calls | `roc check` | Tool output | Cost |
|---|---|---|---|---|---|---|---|---|
| baseline | todos-sqlite | basic-webserver | basic-webserver | roc_overview | 9 | pass | 31.0k ch | $0.57 |
| baseline | sse-stream | basic-webserver | basic-webserver | roc_overview | 4 | pass | 21.6k ch | $0.32 |
| baseline | form-post | basic-webserver | basic-webserver | roc_overview | 5 | pass | 25.3k ch | $0.44 |
| baseline | builtin-only | builtin | none | roc_overview | 6 | pass | 29.9k ch | $0.54 |
| text-only | todos-sqlite | basic-webserver | basic-webserver | roc_overview | 10 | pass | 32.5k ch | $0.69 |
| text-only | sse-stream | basic-webserver | basic-webserver | roc_overview | 4 | pass | 20.8k ch | $0.32 |
| text-only | form-post | basic-webserver | none | roc_overview | 4 | pass | 17.3k ch | $0.37 |
| text-only | builtin-only | builtin | none | roc_overview | 5 | pass | 14.6k ch | $0.41 |
| search-symbols | todos-sqlite | basic-webserver | basic-webserver | roc_overview | 6 | pass | 28.9k ch | $0.38 |
| search-symbols | sse-stream | basic-webserver | basic-webserver | roc_overview | 6 | pass | 26.1k ch | $0.26 |
| search-symbols | form-post | basic-webserver | basic-webserver | roc_overview | 11 | pass | 22.7k ch | $0.31 |
| search-symbols | builtin-only | builtin | none | roc_overview | 3 | pass | 15.9k ch | $0.21 |
| search-project-symbols | local-platform | project | none | roc_overview | 2 | pass | 11.8k ch | $0.27 |
| search-project-symbols | local-platform | project | none | roc_overview | 2 | pass | 11.8k ch | $0.18 |
| search-project-symbols | local-platform | project | none | roc_overview | 2 | pass | 11.8k ch | $0.18 |
| search-project-symbols | roc-ray-local | project | none | roc_overview | 2 | pass | 12.2k ch | $0.34 |
| search-project-symbols | roc-ray-local | project | none | roc_overview | 3 | pass | 12.9k ch | $0.37 |
| search-project-symbols | roc-ray-local | project | none | roc_overview | 2 | pass | 12.2k ch | $0.32 |
| query-lists | form-post | basic-webserver | basic-webserver | roc_overview | 6 | pass | 25.4k ch | $0.29 |
| query-lists | roc-ray-local | project | none | roc_overview | 4 | pass | 25.2k ch | $0.46 |
| query-lists | form-post | basic-webserver | basic-webserver | roc_overview | 6 | pass | 21.9k ch | $0.28 |
| query-lists | roc-ray-local | project | none | roc_overview | 3 | pass | 16.1k ch | $0.33 |
| query-lists | form-post | basic-webserver | basic-webserver | roc_overview | 8 | pass | 25.1k ch | $0.33 |
| query-lists | roc-ray-local | project | none | roc_overview | 4 | pass | 16.9k ch | $0.37 |

## Tool call order

- `baseline/todos-sqlite`: roc_overview -> roc_overview(basic-webserver) -> search_roc_syntax -> lookup_builtin -> get_builtin_module -> search_builtin_signatures(basic-webserver) -> lookup_builtin -> search_roc_syntax -> roc_check
- `baseline/sse-stream`: roc_overview -> search_roc_syntax -> roc_overview(basic-webserver) -> roc_check
- `baseline/form-post`: roc_overview -> roc_overview(basic-webserver) -> search_roc_syntax -> search_roc_syntax -> roc_check
- `baseline/builtin-only`: roc_overview -> get_builtin_module -> get_builtin_module -> search_roc_syntax -> roc_check -> roc_check
- `text-only/todos-sqlite`: roc_overview -> roc_overview(basic-webserver) -> search_roc_syntax -> lookup_builtin -> get_builtin_module -> get_builtin_module -> lookup_builtin -> search_roc_syntax -> roc_check -> roc_fmt
- `text-only/sse-stream`: roc_overview -> search_roc_syntax -> roc_overview(basic-webserver) -> roc_check
- `text-only/form-post`: roc_overview -> search_roc_syntax -> search_roc_syntax -> roc_check
- `text-only/builtin-only`: roc_overview -> get_builtin_module -> lookup_builtin -> roc_check -> roc_check
- `search-symbols/todos-sqlite`: roc_overview -> roc_overview(basic-webserver) -> search(basic-webserver) -> search_roc_syntax(basic-webserver) -> search_roc_syntax -> roc_check
- `search-symbols/sse-stream`: roc_overview -> roc_overview(basic-webserver) -> search(basic-webserver) -> search_roc_syntax(basic-webserver) -> search_roc_syntax(basic-webserver) -> roc_check
- `search-symbols/form-post`: roc_overview -> roc_overview(basic-webserver) -> search_symbols -> search_symbols -> search_symbols -> search_symbols -> search_symbols -> search_symbols(basic-webserver) -> get_builtin_module -> get_builtin_module -> roc_check
- `search-symbols/builtin-only`: roc_overview -> get_builtin_module -> roc_check
- `search-project-symbols/local-platform`: roc_overview -> roc_check
- `search-project-symbols/local-platform`: roc_overview -> roc_check
- `search-project-symbols/local-platform`: roc_overview -> roc_check
- `search-project-symbols/roc-ray-local`: roc_overview -> roc_check
- `search-project-symbols/roc-ray-local`: roc_overview -> search_project_symbols -> roc_check
- `search-project-symbols/roc-ray-local`: roc_overview -> roc_check
- `query-lists/form-post`: roc_overview -> roc_overview(basic-webserver) -> search_symbols -> search_symbols -> search_symbols -> roc_check
- `query-lists/roc-ray-local`: roc_overview -> search_project_symbols -> roc_check -> roc_fmt
- `query-lists/form-post`: roc_overview -> roc_overview(basic-webserver) -> search_symbols -> get_builtin_module -> get_builtin_module -> roc_check
- `query-lists/roc-ray-local`: roc_overview -> search_project_symbols -> roc_check
- `query-lists/form-post`: roc_overview -> search_symbols(basic-webserver) -> search_symbols(basic-webserver) -> roc_overview(basic-webserver) -> search_symbols(basic-webserver) -> roc_check -> search_symbols(basic-webserver) -> roc_check
- `query-lists/roc-ray-local`: roc_overview -> search_project_symbols -> search_symbols -> roc_check
