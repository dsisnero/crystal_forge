# Changelog

All notable user-facing changes to this project will be documented in this file.

Changes are grouped by release date and category. Only user-facing changes
are included — internal refactors, test updates, and CI changes are omitted.

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
