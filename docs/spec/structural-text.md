# Retired structural text AQL

The former `AQL / PROGRAM / STAGE` structural text surface is withdrawn from
the public language. `STEP` and `OP` are not public query productions. The
`aql-text` format selects the implemented [query text profile](query-text.md),
including SQL/Pipe and the admitted Graph pattern forms; it does not select a
legacy parser. `sql` retains its explicit query-head rule. Neither format
falls back to JSON, YAML or an internal fixture decoder after a rejection.

Hosts reject a structural document as typed invalid input before durable Run
acceptance, execution or provider I/O. The lightweight SDK and native CLI send
source using the existing explicit format; they do not install a parser or
infer a format from filenames. Definitive rejection remains distinct from
transport-unknown submission. A rejected source does not acquire a Run reference.

JSON and YAML Program documents remain supported machine inputs. Their IDs,
metadata, parameters, opaque bindings, authored steps, arrays, Results and
Effects continue through ordinary admission, the checker, planner and Host.
This withdrawal does not change Program meaning, its identity rules, access
control, execution or retained-source serialization.

The old parser and formatter are retained solely in the internal
`internal_structural_fixture` tool. No product source route or runtime package
depends on it. Its lossless fixtures preserve independent historical expectations;
their success is not public text acceptance. There is no public compatibility
formatter or alternate legacy entry. The
[historical grammar](../../spec/frontend/historical/actql-text-0.1.ebnf) is not
the active language grammar.

The [migration mapping](../design/frontend-language-migration.md) distinguishes
the adopted target, implemented surfaces and executed evidence. In particular,
retaining an equivalent JSON Program does not complete a replacement text path.
Named SGA calls, source-free construction, explicit Result declarations and
Effect sequencing must migrate to their adopted expressions in later units;
unfinished source construction is not a permanent language prohibition.

The Grammar Manifest's existing structural grammar/rules digest fields now
bind this withdrawal policy and its rejection grammar, not the historical
fixture language. They remain on 0.1. Changing these bytes changes the Manifest
CID and dependent compilation identities; Program source-schema identity is
unchanged.
