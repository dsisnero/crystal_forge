# Rust source discovery silently drops native function/class/interface IDs

## Suggested destination

File this first against **dsisnero/crystal_forge**, in
`skills/cross-language-crystal-parity/scripts/parity_inventory_lib.rb`.
The verified Chiasmus binary emits these declarations; the downstream Rust
kind filter removes them. Chiasmus should also document/test its native Rust
kind vocabulary so consumers can use it reliably.

This note is ready to copy into an issue. No upstream issue has been filed.

## Affected environment

- Consumer: `dsisnero/arrow-cr`, discovery-audit commit `70ab1d5`.
- Source: `apache/arrow-rs` 60.0.0,
  `ef1fa157977633f0ba21aa921f9ef3d5c669235b`.
- Skill: `cross-language-crystal-parity` v1.8.0; installed skill metadata records
  crystal_forge tree `7f3ebf232662a5d511b768e63fd39ceacd9388cb`.
- Verified native toolchain: Chiasmus v0.3.2, `darwin-aarch64`.
- `chiasmus-discover` SHA-256:
  `d5c8c8bfca16d87c72c0f25aaba345e114134b3399c56c73538b79c9ebf97226`.
- Parser mode: strict `tree-sitter`, with no regex fallback.

The release lookup was unavailable during this reproduction; the skill verified
and used the cached toolchain. This report describes that exact pairing, rather
than claiming every release is affected.

## Problem and impact

The Rust-specific allowed kinds are:

```ruby
'rust' => Set.new(%w[const struct enum trait type func method test])
```

`curated_inventory_items` filters the parsed items by this set:

```ruby
allowed = CURATED_KINDS.fetch(language, DEFAULT_CURATED_KINDS)
dedupe_items(items.select { |item| allowed.include?(item.kind) })
```

The native tool emits Rust free functions as `function`, struct/enum declarations
as `class`, and traits as `interface`. Those labels are already in
`DEFAULT_CURATED_KINDS` but absent from the Rust-specific set. Consequently,
source manifest generation succeeds and reports the tree-sitter backend while
silently removing these declarations.

For the same pinned Arrow checkout and the same 14 source/example roots:

| Native kind | IDs retained by the old Rust filter | IDs with compatible filtering |
| --- | ---: | ---: |
| `const` | 345 | 345 |
| `method` | 3,956 | 3,956 |
| `function` | 0 | 1,386 |
| `class` | 0 | 565 |
| `interface` | 0 | 75 |
| **Total source IDs** | **4,301** | **6,327** |

That is **2,026 silently omitted source IDs**. An empty-output guard cannot
catch this because thousands of constants and methods remain. The separate
inline-test manifest contains 3,184 IDs; the source kind-filter fix does not
change that test count.

## Standalone reproduction

This fixture needs no Arrow checkout or Rust compiler. Set `SKILL_DIR` to the
canonical skill and `CHIASMUS_DISCOVER_BIN` to the verified binary path reported
by its preflight, then run:

```sh
repro_dir="$(mktemp -d)"
mkdir -p "$repro_dir/upstream/src"
cat > "$repro_dir/upstream/src/lib.rs" <<'RS'
pub const VALUE: i32 = 1;
pub struct Demo;
pub enum Mode { First }
pub trait Action { fn apply(&self); }
pub fn free_function() {}
impl Demo { pub fn method(&self) {} }
#[cfg(test)]
mod tests { #[test] fn smoke() { assert_eq!(super::VALUE, 1); } }
RS
"$CHIASMUS_DISCOVER_BIN" --language rust --dir "$repro_dir/upstream" \
  --parser tree-sitter > "$repro_dir/native.tsv"
PORT_SCOPE_INCLUDE=src PORT_PARSER=tree-sitter \
  bash "$SKILL_DIR/scripts/generate_source_parity_manifest.sh" \
  "$repro_dir" "$repro_dir/source.tsv" upstream rust
cat "$repro_dir/native.tsv"
cat "$repro_dir/source.tsv"
```

Observed and verified: native output contains six source declarations plus the
inline test. Successful source manifest generation retains only
`src/lib.rs::const::VALUE` and `src/lib.rs::method::Demo.method`. It drops the
free function, both types and the trait. Expected: all six source declarations
remain; the test belongs in the separate test manifest.

## Arrow reproduction

Use the verified native binary reported by `verify_skill_install.sh`:

```sh
bash "$SKILL_DIR/scripts/verify_skill_install.sh" "$PWD" rust tree-sitter
"$CHIASMUS_DISCOVER_BIN" --language rust \
  --dir vendor/arrow-rs/arrow-string/src --parser tree-sitter > /tmp/rust-native.tsv
rg '::function::|::class::' /tmp/rust-native.tsv
```

`CHIASMUS_DISCOVER_BIN` above means the actual verified binary path; set it from
the preflight output if it is not already configured. Relevant raw output IDs
(relative to that scan directory) include:

```text
regexp.rs::function::regexp_is_match
binary_predicate.rs::class::BinaryPredicate
```

Scanning `vendor/arrow-rs/arrow-array/src` also produces:

```text
types.rs::interface::ArrowPrimitiveType
```

Now run the canonical generator without the workaround, writing to a temporary
output so a curated ledger or existing manifest cannot be overwritten:

```sh
PORT_SCOPE_INCLUDE=arrow-string/src PORT_PARSER=tree-sitter \
  bash "$SKILL_DIR/scripts/generate_source_parity_manifest.sh" \
  "$PWD" /tmp/rust-source-parity.tsv vendor/arrow-rs rust
rg '::function::|::class::|::interface::' /tmp/rust-source-parity.tsv
```

Expected: the declarations emitted by strict native discovery remain in the
source manifest. Actual with the affected filter: those kinds are absent even
though generation succeeds. Use a fresh temporary output name for repeat runs,
or explicitly pass the generator's force-overwrite flag for that temp file.

For the full Arrow reproduction, set `PORT_SCOPE_INCLUDE` to the comma-joined
contents of arrow-cr's `plans/inventory/rust_scope.txt`.

## Proposed Crystal Forge fix

Admit the native vocabulary while retaining historical labels:

```diff
-    'rust' => Set.new(%w[const struct enum trait type func method test]),
+    'rust' => Set.new(%w[const struct enum trait type func function method test class interface]),
```

Retaining both vocabularies avoids dropping IDs from older grammar/backends.
Do not rename existing curated IDs or transfer `ported` status just because
names resemble each other. If broader native declaration kinds are supported,
make the Rust policy explicit and test each one.

In Chiasmus, documenting/testing the emitted Rust vocabulary would prevent this
integration mismatch. Changing native labels to language-specific names would
be a separate, versioned migration: it changes manifest IDs and should not be
used as an unannounced fix for existing consumers.

## Regression tests to add upstream first

1. Create a Rust fixture containing a constant, free function, struct, enum,
   trait, impl method and inline `#[test]` function.
2. Discover it with the real strict tree-sitter backend; assert the expected
   native IDs/kinds are present before any consumer filtering.
3. Feed native `function`, `class` and `interface` items through
   `curated_inventory_items(language: 'rust')`; assert they survive. These
   assertions fail with the current Rust set.
4. Assert historical `func`, `struct`, `enum` and `trait` labels remain admitted.
5. Generate and check source/test manifests end to end; assert representative
   declarations survive, not merely that output is nonempty or exit status is 0.
6. Remove a representative kind from the resulting source snapshot and assert
   the strict drift checker fails. Keep known-symbol anchors so a future
   intentional refresh cannot silently redefine the baseline around an omission.
7. Keep implementation status separate from discovery: newly identified IDs
   must not inherit the native TSV's `ported` marker as Crystal signoff.

## Downstream workaround and validation

arrow-cr's `scripts/parity/generate_source.rb` loads the canonical library, merges
`DEFAULT_CURATED_KINDS` into the process-local Rust set, then loads the canonical
source generator. It copies no parser code and changes no installed skill files.
The committed source metadata records that kind policy and the verified producer.

`rust_discovery_anchors.tsv` additionally requires a constant, method, free
function, type, trait and inline test. The anchor regression was observed red
before the guard and green after it; the complete audit suite has 14 specs.

After refreshing the discovery indexes, the full live checks pass with 6,327
source IDs and 3,184 tests. All 3,799 pre-existing curated ledger rows remain
byte-for-byte unchanged. New IDs are conservatively `missing`, and 606 historical
IDs remain explicit legacy entries pending mapping review. Discovery counts
therefore do not assert complete Arrow implementation or test coverage.

Once the upstream kind policy is fixed and verified against these anchors, the
local generation bootstrap can be removed. The independent ledger-preservation
and audit checks should remain.
