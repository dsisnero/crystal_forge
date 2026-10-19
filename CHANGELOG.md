# Changelog

All notable user-facing changes to this project will be documented in this file.

Changes are grouped by release date and category. Only user-facing changes
are included — internal refactors, test updates, and CI changes are omitted.

## [Unreleased]

### Added

- Portable `AGENTS.md` template (`templates.AGENTS.md`) and `docs/resuming.md`
  template (`templates.resuming.md`) for any porting repo, with per-repo
  placeholders for the upstream pin, vendor path, gates, and plan paths.
- `templates/parity_plan.md` in `cross-language-crystal-parity`, including the
  **Where we are** resume block.
- Resume contract shared by `crystal-forge-setup-project`,
  `initialize-crystal-porting-project`, `porting-to-crystal`, and
  `cross-language-crystal-parity`: entrypoint structure, session start/end
  steps, plan refresh, and atomic per-feature commits.

### Changed

- `initialize-crystal-porting-project` baseline verifier now checks the agent
  entrypoint (resume block, principles, session continuity, definition of done,
  commit prefix, no leftover placeholders) and `docs/resuming.md`.

### Fixed

- Rust parity discovery now retains the native Chiasmus `function`, `class`, and
  `interface` declarations emitted by strict tree-sitter discovery alongside the
  historical `func`, `struct`, and `trait` labels, instead of silently dropping
  them from generated source and test manifests.

## [1.9.0] - 2026-10-19

### Added

- Verified-cache Chiasmus installer with exact release pins and offline reuse.
- Workspace skill refresh and drift checks that preserve origin metadata and
  link supporting resources to canonical sources.
- Real-release consumer verification through discovery and reconciliation.

### Fixed

- Relative repository roots now resolve reconciliation rules correctly.
- The legacy release sync command uses the verified installer instead of
  assembling incomplete binary bundles inside the skill.
- Windows wrappers select packaged executables, and explicit regex discovery
  avoids toolchain resolution.
- Skill documentation and shell lint findings, including stale installation
  instructions and workspace resource copies.

## [1.4.0] — 2026-05-25

### Changed
- **Skill library**: Reduced instruction redundancy across all Crystal Forge
  skills and standardized them around tighter trigger, routing, workflow, and
  guardrail sections so the skills are easier to load and follow.
- **Bubble Tea parity skills**: Simplified orchestration, golden-generation,
  and example-parity guidance while preserving the handoff boundaries between
  workflow, example, and shard-fix ownership.
- **Crystal project and porting skills**: Compressed setup, initialization,
  performance, shard-patching, dependency-selection, and porting workflows into
  shorter operational guides with the same core constraints.
- **cross-language-crystal-parity**: Consolidated parity-plan guidance into a
  smaller workflow centered on curated `plans/parity.md`, manifest ownership,
  and adversarial signoff.

### Fixed
- **cross-language-crystal-parity references**: Corrected supporting guidance
  to consistently refer to `plans/parity.md` instead of the older repo-root
  `parity.md` path.

## [1.3.0] — 2026-05-25

### Changed
- **cross-language-crystal-parity**: Refined parity.md policies with granular
  red-green TDD cycles, upstream source/test reading requirements, and
  small-commit checkpoint discipline for feature-level parity tracking.
- **porting-to-crystal**: Aligned porting loop with parity.md feature-level
  workflow; added Rust source-reading step, small-commit checkpoint policy,
  and full gate suite verification before feature completion.

### Fixed
- **parity_inventory_lib**: Fixed AppleDouble (`._*`) file filtering by
  checking each path segment instead of the full path prefix, avoiding
  false negatives with nested paths.
