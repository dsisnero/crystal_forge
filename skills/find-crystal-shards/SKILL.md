---
description: Evaluate and select Crystal shard dependencies for a project by searching candidate libraries, comparing maintenance and fit, and applying the chosen dependency to shard.yml. Use when a port or feature needs a Crystal library replacement and dependency choice affects behavior, risk, or maintainability.
name: find-crystal-shards
---
# Find Crystal Shards

## Goal

Select a dependency with explicit quality and compatibility reasoning, then wire
it into `shard.yml`.

## Workflow

### 1) Find candidates

Search shards.info for the target capability and keep 2-5 plausible options.

- `https://shards.info/search?q=<query>`

### 2) Score candidates

Check each candidate for:

- API/behavior fit to the required use case.
- Maintenance freshness (recent commits/releases).
- Adoption signal (stars, dependents, or community use).
- Documentation quality.
- Project health (not archived, manageable issue backlog).

### 3) Recommend one option

Provide a short tradeoff summary and justify the selected shard.

### 4) Install dependency

Preferred automated path:

```bash
ruby scripts/find_crystal_shards.rb --install <dependency_name> <owner/repo>
```

Manual pattern:

```yaml
dependencies:
  dependency_name:
    github: owner/repo
```

Then run:

```bash
shards install
```

## Script

`scripts/find_crystal_shards.rb`

- Search mode: `ruby scripts/find_crystal_shards.rb "http client"`
- Install mode: `ruby scripts/find_crystal_shards.rb --install crest mamantoha/crest`

## Output Requirements

1. List top candidates with short quality notes.
2. Recommend one shard with rationale.
3. Show or run exact install command.
4. Confirm resulting `shard.yml` entry.

## Related Skills

- [porting-to-crystal](/Users/dominic/.agents/skills/crystal_forge/skills/porting-to-crystal/SKILL.md)
- [crystal-shard-lib-patch](/Users/dominic/.agents/skills/crystal-shard-lib-patch/SKILL.md)
