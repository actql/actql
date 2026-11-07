# Full Account initialization metadata fixture

`account-initialization-describe.json` is a fixed, sanitized Describe response
for initialization resource tests. It contains no records, credentials, org
identity or live service configuration. It is not an installed publication or
a saved Run and grants no authority.

The wire preserves the original response's 251217 UTF-8 bytes, object keys,
recursive primitive kinds, array lengths, String UTF-16 lengths and JSON
punctuation. All eight custom field names are replaced with unique synthetic
API names of the same length. Standard Account field names, native types,
reference targets and compound-field associations remain semantic inputs.
Other String content is masked while preserving its wire width and syntax.
The fixture retains all 71 fields and the full ignored metadata structure;
it is not a long padding String standing in for a different schema.

Tests serve this exact wire through the owned TLS fixture, then use the real
Catalog/Row declaration constructors and the same original finite Resource
parent. The Source's initial identity, complete load and final identity read
precede Effect initialization. Normal Account/current/generation/schema and
Mapping checks stay active; no reserve or cleanup result is replaced by a
success mock. Provider/Common declarations remain in their separate runtimes.
