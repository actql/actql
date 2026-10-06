# GoogleSQL STRUCT is not the existing named object contract

Owner: B. Inspected main: `b98a50ff763d1367e344fdfa8aea380ec8749132`.
This is a common-contract dependency, not an implemented constructor or a
request to change ModelTask output objects.

The selected [GoogleSQL STRUCT reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types#struct_type)
defines ordered fields, permits anonymous/duplicate field names and empty
STRUCTs, and compares corresponding fields by position while ignoring names.
The existing language's "Object and array construction" defines a nonempty
closed product keyed by unique static names, with canonical key order rather
than an author-selected semantic order. No direct `STRUCT` mapping to `object`
preserves those meanings.

## Independent boundary examples

```sql
SELECT STRUCT(1 AS a, 2 AS b) = STRUCT(1 AS b, 2 AS a) AS same;
-- Required: [{"same": true}], by pairwise ordinal values 1,2.

SELECT STRUCT(1, 2) AS value;
-- Required: an ordered two-field STRUCT with anonymous fields.

SELECT STRUCT(1 AS x, 2 AS x) AS value;
-- Required: both fields retained; named x access is ambiguous.

SELECT STRUCT() AS value;
-- Required: the empty STRUCT, not SQL NULL or a guessed JSON object.
```

For the first case, proposed object expressions would instead construct
`{a:1,b:2}` and `{a:2,b:1}`. Their named-map meaning differs, independent of
the small exact numeric values. The current query parser/lowerer does not have
this source constructor. No public product execution or Google-service
differential run is claimed by this source/spec inspection.

## Required common boundary

Provide an admitted typed STRUCT value/constructor retaining ordered entries,
optional field names and duplicates, separate from existing object values.
Checker signatures, field/ordinal access, pairwise equality and NULL behavior,
grouping/DISTINCT, canonical identity and supported serialization/retention
boundaries must agree. STRUCT less/greater comparisons remain disallowed by
the selected reference; existing object ordering must not leak into them.
Clarify the public Result schema/profile for anonymous and duplicate fields
rather than silently dropping, renaming or overwriting them in a JSON map.
Keep common object and ModelTask meanings unchanged.

Once A/C supply the agreed admitted representation and interfaces, B can connect
the constructor through ordinary source AST/lowering and public Local/HTTPS.
Named-only object sugar is not recorded as full STRUCT completion. Existing
INFER KEEP/AS uses its adopted ActQL named-object projection, not a claim of
general GoogleSQL STRUCT conformance. No new owner or adapter is added here.
