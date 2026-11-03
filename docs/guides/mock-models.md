# Declared models and replaceable fixture files

The mock profile uses separate external files for model declarations and sample
records. A scenario name does not select a runtime implementation. The generated
churn-risk and deal-review projects use the same readers and writers.

```json
{
  "profile": "mock",
  "mock": {
    "catalog": "./mock/catalog.json",
    "data": "./mock/data.json",
    "answers": {"model-task:example.v1": "./mock/example.answers.yaml"}
  }
}
```

Paths are relative to the project directory. Replace the configured data file,
or select another file with the same declared model, and reconnect. No source
code change or row-derived schema is required. Active Runs retain the actual
opened file identity and original bytes; replacing a file does not rebind an
existing read, captured version, approval or pending Effect.

## Model declarations

The catalog root is `connections`. Each key names an existing connection in
`connectors.json`; its provider identity comes from that original connection,
not the spelling of the key. The catalog describes:

- `views`: `resource`, `resource_kind` and the existing full Relation `schema`.
  Optional `request_schema`, `facts`, `acquisition`, `resource_identity` and
  `data_classification` use the existing Relation contracts.
- `query_aliases`: explicit `{name, resource}` pairs, optionally with a `request` JSON object. The object supplies literal request data to the existing Source request checker. Omitted fields stay omitted: no defaults or implicit `null` values are inserted. Request data does not introduce parameter, binding, permission, or provider authority.
- `data`: explicit `resource`, `items_path`, `key_path` and `primary_identity`.
  No `rows`, `files`, `contents` or primary-key convention is inferred.
- `writes`: explicit resource, primary identity, writable fields, `permission`,
  `observe_permission`, `approval` and aliases. These are Mapping declarations,
  not current authorization or approval.
- `file_bindings`: explicit logical listing/content resources, physical data
  resource and identity/name/version/media-type/UTF-8 field roles.

For example, a data binding can select `['crm', 'Customer', 'rows']`, with key
metadata at `['crm', 'Customer', 'key']`. That metadata must be exactly the one
non-null Text primary identity declared by the model. Missing, duplicate or
incompatible row fields and duplicate identities are rejected. Both JSON integer
tokens and canonical decimal Text represent declared Int64 values without a
Double conversion; fractional, exponent, overflow and noncanonical encodings
are rejected. Compound keys are not implemented by this fixture codec.

Catalog objects are closed and bounded. Unknown declaration/binding fields,
missing or foreign resources and ambiguous writable targets fail before fixture
I/O. The current installed Effect composition supports one writable target;
multiple aliases for that same target do not create additional targets.

## Physical file records and logical Content

A file-backed data binding supplies its physical `schema` explicitly using the
same Relation contract format. Its raw fields contain ordinary strings, including
inline `content_utf8`; they do not contain usable ResourceRef or ContentRef
objects. Logical listing and Content views have their own declared schemas.
The existing Source issuer creates file references; the existing Run-owned Store
capture creates Content references.

File bindings name `listing_resource`, `content_resource`, `data_resource`,
`identity_field`, `name_field`, `version_field`, `media_type_field` and
`content_utf8_field`; `path_field` is optional. A missing path remains null. A
file name is never an identity or an implicit filesystem path. Listing and
Content capability facts are derived from the actual admitted schemas and bound
Source scope; those bound views must not supply conflicting `facts`.

The exposed fixture-provider version is opaque. It is the SHA-256 identity of
the canonical object containing `declared_version` and the actual admitted
`row_version_cid`. The original version field in the sample file is unchanged.
Changing content while accidentally retaining the same declared version therefore
cannot satisfy an old captured lookup. Reference admission also requires the
same live Source inventory; equal sample rows are not cross-Source authority.

## Verification scope

Declaration and codec tests do not prove an installed run, resource funding,
physical cleanup, approval, restart or a live provider connection. The ordinary
built-package acceptance must execute the unchanged examples through their
existing Source, Content, Model and Effect owners. Fixture transport is not
live Salesforce, Drive or other SaaS coverage.
