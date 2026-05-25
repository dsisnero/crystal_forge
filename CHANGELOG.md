# Changelog

All notable user-facing changes to this project will be documented in this file.

Changes are grouped by release date and category. Only user-facing changes
are included — internal refactors, test updates, and CI changes are omitted.

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
