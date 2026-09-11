# Source-owned opaque Binding declarations

`binding_declarations.prepare` reads bindings from one opaque parsed Program.
Its result retains that Program and sorted, immutable declaration handles with
original source positions. It does not accept a separate declaration map or
concrete values. Lookup is exact and case-sensitive; names follow the ASCII
identifier grammar used by the pinned Program schema.

The closed forms are resource_ref with required nonempty resource_kind, and
artifact_ref with optional nonempty media_type. Absence of media_type is retained
as absence, not replaced with an invented wildcard or default. Explicit null is
not absence. Other keys, nullable and default are rejected; these are opaque
invocation declarations, not ordinary Parameter contracts. Resource/media labels
are not narrowed to an implementation-specific registry or ASCII syntax.

The normative owner is [Connector SourceViews](../spec/language.md#sourceviews),
with [Authoring Context](../spec/language.md#authoring-context) allowing declaration
meta and [Canonical identities](../spec/language.md#canonical-identities)
excluding it from semantic declarations. Nonempty meta permits arbitrary
service-defined keys except top-level actql_. Nested business keys are not
interpreted. Source parsing already establishes finite numbers, well-formed
Unicode and NFC/LF normalization. A bounded iterative walk charges all retained
declaration and annotation data, including deep metadata, before constructing
declarations. A failed preparation returns no partial collection.

`emit_declaration` writes the closed annotation-free declaration to an enclosing
canonical writer, sharing its text/measurement/hash limits. It preserves type
constraints without injecting checked-value nullability or concrete Ref data.
There is no CID API: used-only references and the semantic envelope still need
to be closed by Program integration. Reading all declarations does not establish
that all are used or that any invocation has supplied valid values.

Sketch `87dc7144:src/actql-invocation-bindings.ts` supplied the two-form reference
model, not authority to copy its older metadata omission or permissive empty
media_type handling. The pinned executable Program schemas in
`actql-protocol-schemas.json` require nonempty media_type when present. Those
execution-material declarations are annotation-free; their omission of meta
does not override the authored annotation rule. This implementation adds no
language rule and requires no identity-domain or schema pin change.

Tests cover fixed declaration bytes, sorted lookup, exact source ownership,
absence, closed forms, scalar constraints, ASCII names, metadata reservations,
depth 10,000, exact work limits and enclosing three-sink boundaries. No Reference
issuance, Host binding admission, SourceView request compatibility, value
redaction, execution permission or final Program identity is claimed. Those
boundaries must consume these declarations rather than infer names or types
from an opaque values artifact.
