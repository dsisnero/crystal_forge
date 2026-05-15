# Rust to Crystal Porting Reference

This reference complements `porting-to-crystal/SKILL.md` for Rust-heavy ports.

## Numeric Semantics

- Map Rust integer widths explicitly (`u8`, `u16`, `u32`, `u64`, `i64`, etc.).
- For wrapped arithmetic parity, use explicit conversion/wrapping helpers rather than implicit Crystal casts.
- Track any place where Rust uses `as` conversions that can truncate or reinterpret values.

## UTF-8 and Indexing

- Distinguish byte offsets from character columns.
- Use `String#bytesize` for byte-length parity.
- Use `String#byte_index_to_char_index` when converting byte positions to display columns.
- Treat non-boundary byte indexes as explicit error paths when upstream does.

## Ranges and Boundaries

- Rust `start..end` is half-open; map to Crystal `start...end`.
- Keep boundary behavior exact for `disjoint`, `merge`, and off-by-one checks.
- Preserve inclusive vs exclusive semantics in tests first, then refactor.

## Traits and API Surface

- Port public contract first: type names, method names, return semantics.
- Trait-heavy code can map to Crystal modules + abstract defs or concrete adapter classes.
- Document any unavoidable deviations in `docs/porting-parity.md` immediately.

## Errors and Invariants

- Keep panic/assert contracts explicit in Crystal (`raise` or guarded checks).
- Preserve error message shape when tests or snapshots depend on it.
- Prefer typed error classes over generic exceptions in shared library surfaces.

## Testing and Snapshots

- Port unit tests alongside implementation, not after.
- For Rust `insta` snapshot suites, keep snapshot text as source-of-truth fixtures.
- Normalize only platform-specific differences (line endings) and document it.

## Recommended Sequence for Rust Ports

Architecture-first staging rule:

- First mirror module boundaries and entry points (`mod.rs`, renderer/view shells) so integration compiles early.
- Then fill behavior from leaves inward (helpers -> views -> renderer), validating after each layer.

1. Port core value types and spans/indices.
2. Port file/source utilities and boundary/error behavior.
3. Port diagnostics data models and builders.
4. Port rendering config and view layers.
5. Port renderer and snapshot harness.
6. Run parity diff checks on fixtures until stable.
