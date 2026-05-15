<p align="center">
  <strong>Agent skills for working on Crystal code projects.</strong><br>
  Reusable setup and workflow guidance for Crystal-first agent engineering.
</p>

<p align="center">
  <a href="docs/architecture.md">Architecture</a> &middot;
  <a href="docs/development.md">Development</a> &middot;
  <a href="docs/coding-guidelines.md">Guidelines</a> &middot;
  <a href="docs/testing.md">Testing</a> &middot;
  <a href="docs/pr-workflow.md">PR Workflow</a>
</p>

---

Like a forge, this project shapes rough ideas into dependable tools, but for Crystal engineering workflows. Each skill is a repeatable mold: it captures standards once, then applies them consistently across projects. The result is less setup friction and more predictable, high-quality Crystal work.

---

## Quick Start

1. Install dependencies:

   ```bash
   make install
   ```

2. Run code quality gates:

   ```bash
   make format
   make lint
   make test
   ```

3. Run markdown checks:

   ```bash
   make markdown-check
   ```

## Features

- Crystal-focused skill workflows under `skills/`.
- Crystal setup baseline including `.ameba.yml` and `.rumdl.toml` templates.
- Enforced Crystal code gates for format, lint, and specs.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     crystal_forge:
       github: dsisnero/crystal_forge
   ```

2. Run `shards install`

## Usage

```crystal
require "crystal_forge"
```

`<!-- TODO: add concrete runtime usage examples as public APIs are added -->`

## Development

Essential commands:

```bash
make install
make format
make lint
make test
make markdown
make markdown-check
```

See [Development Guide](docs/development.md) for full setup instructions.

## Documentation

| Document | Purpose |
|----------|---------|
| [Architecture](docs/architecture.md) | System design and data flow |
| [Development](docs/development.md) | Setup and daily workflow |
| [Coding Guidelines](docs/coding-guidelines.md) | Code style and conventions |
| [Testing](docs/testing.md) | Test commands and patterns |
| [PR Workflow](docs/pr-workflow.md) | Commits, PRs, and review process |

## Contributing

1. Create an issue: `/forge-create-issue`
2. Implement: `/forge-implement-issue <number>`
3. Self-review: `/forge-reflect-pr`
4. Address feedback: `/forge-address-pr-feedback`
5. Update changelog: `/forge-update-changelog`

## Contributors

- [Dominic Sisneros](https://github.com/dsisnero) - creator and maintainer
