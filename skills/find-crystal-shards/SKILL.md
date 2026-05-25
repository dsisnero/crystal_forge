---
name: find-crystal-shards
description: Evaluate and choose Crystal shard dependencies with explicit tradeoff reasoning. Use when a Crystal port or feature needs a library replacement and dependency choice affects behavior, maintenance risk, or compatibility.
---

# Find Crystal Shards

## Workflow

1. Search for 2-5 plausible candidates.
2. Score each one for API fit, maintenance, adoption, docs, and project health.
3. Recommend one option with a short tradeoff summary.
4. Install it in `shard.yml` and run `shards install` if the user wants the
   dependency wired in immediately.

## Script

Use `scripts/find_crystal_shards.rb` when possible.

```bash
ruby scripts/find_crystal_shards.rb "http client"
ruby scripts/find_crystal_shards.rb --install crest mamantoha/crest
```

## Output

Always provide:

1. the candidate list
2. the chosen shard and why
3. the exact install command or `shard.yml` entry
4. the resulting dependency state

## Route away when needed

- General port implementation: `porting-to-crystal`
- Local fixes inside installed shards: `crystal-shard-lib-patch`
