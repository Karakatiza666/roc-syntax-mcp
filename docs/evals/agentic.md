# Agentic evaluation

Produced by `node scripts/eval-agentic.mjs`. Every number is read from the
transcript or from `roc check`, never from the model's prose.

## Per arm

A footer column reading `none shown` means the model never called a tool that
emits one, not that it ignored one. Scope footers appear on `search`,
`search_symbols` type queries, the `list_roc_index` kinds, and a `get_roc_syntax` topic
miss. The host-tier footer appears on `search` and `get_roc_module`.

| Arm | Runs | `tools/list` | Compiles | Set `scope` | Called `roc_check` | Footer retries | Host footers | Tool output | Output tokens | Cost |
|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 4 | 3968 tok | 4/4 | 17% (4/24) | 4/4 | none shown | none shown | 27.0k ch | 3.3k | $0.47 |
| text-only | 4 | 2569 tok | 4/4 | 9% (2/23) | 4/4 | none shown | 1/1 followed | 21.3k ch | 3.2k | $0.45 |
| search-symbols | 4 | 2683 tok | 4/4 | 35% (9/26) | 4/4 | 0% (0/3) | none shown | 23.4k ch | 1.9k | $0.29 |
| search-project-symbols | 6 | 2665 tok | 6/6 | 0% (0/13) | 6/6 | none shown | none shown | 12.1k ch | 2.3k | $0.28 |
| query-lists | 6 | 2697 tok | 6/6 | 23% (7/31) | 6/6 | none shown | none shown | 21.8k ch | 2.8k | $0.34 |
| query-shapes | 3 | 2723 tok | 3/3 | 13% (2/15) | 3/3 | none shown | none shown | 20.3k ch | 3.5k | $0.40 |
| pre-merge | 6 | 2723 tok | 6/6 | 15% (4/26) | 6/6 | none shown | none shown | 20.7k ch | 1.8k | $0.27 |
| merged-syntax | 12 | 2481 tok | 12/12 | 28% (15/54) | 12/12 | none shown | none shown | 20.3k ch | 2.1k | $0.27 |
| roc-module | 12 | 2515 tok | 12/12 | 19% (10/52) | 12/12 | none shown | 0/1 followed | 22.5k ch | 2.0k | $0.28 |
| langref-topics | 12 | 2380 tok | 12/12 | 17% (10/60) | 12/12 | 0% (0/1) | 2/2 followed | 24.4k ch | 2.0k | $0.30 |

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
| query-shapes | roc-ray-local | project | builtin | roc_overview | 5 | pass | 23.5k ch | $0.49 |
| query-shapes | roc-ray-local | project | none | roc_overview | 4 | pass | 17.1k ch | $0.33 |
| query-shapes | roc-ray-local | project | builtin | roc_overview | 6 | pass | 20.4k ch | $0.38 |
| pre-merge | todos-sqlite | basic-webserver | basic-webserver | roc_overview | 6 | pass | 29.1k ch | $0.40 |
| pre-merge | sse-stream | basic-webserver | basic-webserver | roc_overview | 4 | pass | 22.4k ch | $0.24 |
| pre-merge | form-post | basic-webserver | basic-webserver | roc_overview | 6 | pass | 23.1k ch | $0.27 |
| pre-merge | builtin-only | builtin | none | roc_overview | 3 | pass | 15.9k ch | $0.21 |
| pre-merge | local-platform | project | none | roc_overview | 2 | pass | 11.8k ch | $0.19 |
| pre-merge | roc-ray-local | project | none | roc_overview | 5 | pass | 21.9k ch | $0.30 |
| merged-syntax | todos-sqlite | basic-webserver | basic-webserver | get_roc_syntax | 7 | pass | 27.4k ch | $0.31 |
| merged-syntax | sse-stream | basic-webserver | basic-webserver | get_roc_syntax | 5 | pass | 22.3k ch | $0.26 |
| merged-syntax | form-post | basic-webserver | basic-webserver | get_roc_syntax | 6 | pass | 26.1k ch | $0.29 |
| merged-syntax | builtin-only | builtin | none | get_roc_syntax | 3 | pass | 15.7k ch | $0.22 |
| merged-syntax | local-platform | project | none | get_roc_syntax | 2 | pass | 11.8k ch | $0.19 |
| merged-syntax | roc-ray-local | project | none | get_roc_syntax | 5 | pass | 16.9k ch | $0.37 |
| merged-syntax | todos-sqlite | basic-webserver | basic-webserver | get_roc_syntax | 5 | pass | 22.6k ch | $0.28 |
| merged-syntax | sse-stream | basic-webserver | basic-webserver | get_roc_syntax | 4 | pass | 22.1k ch | $0.25 |
| merged-syntax | form-post | basic-webserver | basic-webserver | get_roc_syntax | 6 | pass | 29.6k ch | $0.32 |
| merged-syntax | builtin-only | builtin | none | get_roc_syntax | 3 | pass | 13.8k ch | $0.22 |
| merged-syntax | local-platform | project | none | get_roc_syntax | 3 | pass | 12.7k ch | $0.21 |
| merged-syntax | roc-ray-local | project | none | get_roc_syntax | 5 | pass | 22.5k ch | $0.39 |
| roc-module | todos-sqlite | basic-webserver | basic-webserver | get_roc_syntax | 7 | pass | 41.3k ch | $0.36 |
| roc-module | sse-stream | basic-webserver | basic-webserver | get_roc_syntax | 4 | pass | 22.6k ch | $0.25 |
| roc-module | form-post | basic-webserver | basic-webserver | get_roc_syntax | 6 | pass | 23.1k ch | $0.27 |
| roc-module | builtin-only | builtin | none | get_roc_syntax | 4 | pass | 13.4k ch | $0.22 |
| roc-module | local-platform | project | none | get_roc_syntax | 2 | pass | 11.7k ch | $0.20 |
| roc-module | roc-ray-local | project | none | get_roc_syntax | 3 | pass | 14.4k ch | $0.30 |
| roc-module | todos-sqlite | basic-webserver | basic-webserver | get_roc_syntax | 6 | pass | 34.7k ch | $0.33 |
| roc-module | sse-stream | basic-webserver | basic-webserver | get_roc_syntax | 5 | pass | 32.5k ch | $0.29 |
| roc-module | form-post | basic-webserver | basic-webserver | get_roc_syntax | 7 | pass | 25.8k ch | $0.29 |
| roc-module | builtin-only | builtin | none | get_roc_syntax | 3 | pass | 15.7k ch | $0.21 |
| roc-module | local-platform | project | none | get_roc_syntax | 2 | pass | 11.7k ch | $0.19 |
| roc-module | roc-ray-local | project | none | get_roc_syntax | 3 | pass | 22.4k ch | $0.40 |
| langref-topics | todos-sqlite | basic-webserver | basic-webserver | get_roc_syntax | 8 | pass | 43.8k ch | $0.49 |
| langref-topics | sse-stream | basic-webserver | basic-webserver | get_roc_syntax | 5 | pass | 23.0k ch | $0.25 |
| langref-topics | form-post | basic-webserver | basic-webserver | get_roc_syntax | 6 | pass | 22.1k ch | $0.28 |
| langref-topics | builtin-only | builtin | none | get_roc_syntax | 4 | pass | 17.0k ch | $0.23 |
| langref-topics | local-platform | project | none | get_roc_syntax | 2 | pass | 11.9k ch | $0.19 |
| langref-topics | roc-ray-local | project | roc-ray | get_roc_syntax | 5 | pass | 25.8k ch | $0.36 |
| langref-topics | todos-sqlite | basic-webserver | basic-webserver | get_roc_syntax | 6 | pass | 39.9k ch | $0.36 |
| langref-topics | sse-stream | basic-webserver | basic-webserver | get_roc_syntax | 5 | pass | 22.8k ch | $0.26 |
| langref-topics | form-post | basic-webserver | basic-webserver | get_roc_syntax | 6 | pass | 27.7k ch | $0.29 |
| langref-topics | builtin-only | builtin | none | get_roc_syntax | 3 | pass | 15.9k ch | $0.22 |
| langref-topics | local-platform | project | none | get_roc_syntax | 2 | pass | 11.9k ch | $0.19 |
| langref-topics | roc-ray-local | project | roc-ray | get_roc_syntax | 8 | pass | 31.3k ch | $0.43 |

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
- `query-shapes/roc-ray-local`: roc_overview -> search_project_symbols -> search_symbols(builtin) -> roc_check -> roc_check
- `query-shapes/roc-ray-local`: roc_overview -> search_project_symbols -> search_symbols -> roc_check
- `query-shapes/roc-ray-local`: roc_overview -> search_project_symbols -> search_project_symbols -> search_project_symbols -> search_symbols(builtin) -> roc_check
- `pre-merge/todos-sqlite`: roc_overview -> roc_overview(basic-webserver) -> search_symbols -> search_roc_syntax(basic-webserver) -> search_symbols -> roc_check
- `pre-merge/sse-stream`: roc_overview -> roc_overview(basic-webserver) -> search_symbols -> roc_check
- `pre-merge/form-post`: roc_overview -> roc_overview(basic-webserver) -> search_symbols -> search_symbols -> get_builtin_module -> roc_check
- `pre-merge/builtin-only`: roc_overview -> search_symbols -> roc_check
- `pre-merge/local-platform`: roc_overview -> roc_check
- `pre-merge/roc-ray-local`: roc_overview -> search_project_symbols -> search_project_symbols -> search_project_symbols -> roc_check
- `merged-syntax/todos-sqlite`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> search_symbols(basic-webserver) -> search_symbols(basic-webserver) -> search_symbols(basic-webserver) -> get_roc_syntax(basic-webserver) -> roc_check
- `merged-syntax/sse-stream`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> search_symbols -> roc_check -> search_symbols
- `merged-syntax/form-post`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> search_symbols -> search_symbols -> search_symbols -> roc_check
- `merged-syntax/builtin-only`: get_roc_syntax -> search_symbols -> roc_check
- `merged-syntax/local-platform`: get_roc_syntax -> roc_check
- `merged-syntax/roc-ray-local`: get_roc_syntax -> search_project_symbols -> search_project_symbols -> search_symbols -> roc_check
- `merged-syntax/todos-sqlite`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> get_roc_syntax(basic-webserver) -> search_symbols(basic-webserver) -> roc_check
- `merged-syntax/sse-stream`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> search_symbols -> roc_check
- `merged-syntax/form-post`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> search_symbols(basic-webserver) -> search_symbols(basic-webserver) -> search_symbols(basic-webserver) -> roc_check
- `merged-syntax/builtin-only`: get_roc_syntax -> search_symbols -> roc_check
- `merged-syntax/local-platform`: get_roc_syntax -> roc_check -> roc_check
- `merged-syntax/roc-ray-local`: get_roc_syntax -> search_project_symbols -> search_project_symbols -> roc_check -> roc_check
- `roc-module/todos-sqlite`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> get_roc_module -> get_roc_syntax -> search_symbols(basic-webserver) -> get_roc_syntax(basic-webserver) -> roc_check
- `roc-module/sse-stream`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> search_symbols -> roc_check
- `roc-module/form-post`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> search_symbols -> search_symbols -> search_symbols -> roc_check
- `roc-module/builtin-only`: get_roc_syntax -> search_symbols -> roc_check -> roc_check
- `roc-module/local-platform`: get_roc_syntax -> roc_check
- `roc-module/roc-ray-local`: get_roc_syntax -> search_project_symbols -> roc_check
- `roc-module/todos-sqlite`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> search_symbols(basic-webserver) -> get_roc_syntax(basic-webserver) -> get_roc_syntax -> roc_check
- `roc-module/sse-stream`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> search_symbols -> get_roc_module -> roc_check
- `roc-module/form-post`: get_roc_syntax -> search_symbols -> get_roc_syntax(basic-webserver) -> search_symbols -> search_symbols -> search_symbols -> roc_check
- `roc-module/builtin-only`: get_roc_syntax -> search_symbols -> roc_check
- `roc-module/local-platform`: get_roc_syntax -> roc_check
- `roc-module/roc-ray-local`: get_roc_syntax -> search_project_symbols -> roc_check
- `langref-topics/todos-sqlite`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> get_roc_module -> get_roc_syntax -> search_symbols -> search(basic-webserver) -> get_roc_syntax -> roc_check
- `langref-topics/sse-stream`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> get_roc_module -> search_symbols -> roc_check
- `langref-topics/form-post`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> search_symbols -> get_roc_module -> get_roc_module -> roc_check
- `langref-topics/builtin-only`: get_roc_syntax -> search_symbols -> roc_check -> roc_fmt
- `langref-topics/local-platform`: get_roc_syntax -> roc_check
- `langref-topics/roc-ray-local`: get_roc_syntax -> search_project_symbols -> get_roc_syntax(roc-ray) -> search_project_symbols -> roc_check
- `langref-topics/todos-sqlite`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> get_roc_module -> get_roc_syntax -> search_symbols -> roc_check
- `langref-topics/sse-stream`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> get_roc_module -> search_symbols -> roc_check
- `langref-topics/form-post`: get_roc_syntax -> get_roc_syntax(basic-webserver) -> search_symbols -> search_symbols -> get_roc_syntax -> roc_check
- `langref-topics/builtin-only`: get_roc_syntax -> search_symbols -> roc_check
- `langref-topics/local-platform`: get_roc_syntax -> roc_check
- `langref-topics/roc-ray-local`: get_roc_syntax -> get_roc_syntax(roc-ray) -> get_roc_syntax(roc-ray) -> search_project_symbols -> search_project_symbols -> search_symbols -> roc_check -> roc_fmt
