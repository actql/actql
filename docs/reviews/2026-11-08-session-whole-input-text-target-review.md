# Whole input imports and Text sizing target routing

This finite JS input review records two exact current module preimages. It does
not change historical reviews, compiler defaults, archive acceptance or runtime
authority.

`src/connectors_builtin_node/moon.pkg` at
`6f27dfdf10aa232977277ec8580557463e44e81f` is 4022 bytes with SHA-256
`d515c9868140c30ef68b5778b71863813cad0d53cc7300e4ba8fcc3e00405d9d`.
Compared with the prior reviewed body at
`66e7845f75c4eef5ebbb8d59d5fb4b652f73aa0c`, its only changes are the literal
imports `actql/actql/relation_schema` under `@schema` and
`actql/actql/connectors/duckdb/adapter` under `@duckdb_input`. These connect the
existing checked schema and native Whole input codec. The JS-only target,
foreign-library kind, other imports and aliases, and every option remain
unchanged. No new build hook, resolver, linker option or package kind is admitted.

`src/execution_relation/moon.pkg` at
`6813ab0330a17f99c8eef5c9f4a70480ecc7e96c` is 2030 bytes with SHA-256
`2a223e06a52cbb8c01280e9d5c5132485434728f59271ff02900f74ea582d079`.
Compared with its body at `549b54952ceae6eea91bf6ed5dacd42dfd028e14`, it adds
only two literal file predicates: `text_workspace_growth_js.mbt` selects JS and
`text_workspace_growth_nonjs.mbt` selects non-JS. The existing sizing formulas
and shared same-Task growth/current/cleanup implementation are unchanged. The
`+js+wasm+native` target declaration and all production and test imports remain
exact. This Session classification remains JS-only; it is not a separate review
of Native or Wasm execution.

Both files, their manifests, tests and all transitive literal dependencies remain
keyed with their actual Git bytes, modes and directory membership. Nonselected
files are still inputs. Changes to imports, aliases, kind, target expressions,
member names, toolchain or review target retain the existing refusal or
unresolved/full-source fallback. The general manifest parser and the isolated
Core rejection of unreviewed attributes are unchanged.

The previous preimages are not current entries. Old archives and their original
source identities are preserved. A configuration review alone cannot make an
action ready: actual closed input comparison, matching scientific observations,
complete fresh applications, original receipts and final-consumer checks remain
mandatory. This review provides no compiler, normal-package, physical cleanup
or whole-CI acceptance.
