# Original cursor import construction

- Responsibility: describe the existing cursor-import and Source-snapshot
  constructor families. The builder still owns syntax construction; this
  quantity operation neither lowers a query nor imports a value.
- Inputs and outputs: original node and total key/value UTF16 bounds produce
  Source construction units. Counts independently bound containers and fields.
  Negative, empty-node or unrepresentable scalar-emission geometry refuses.
- Identity: callers retain the actual immutable cursor and original builder
  context. Equal quantities are not cursor, Source, document or origin identity.
  No quantity can substitute for normal import ownership checks.
- Ownership: the annotated builder tree and source-map plain tree coexist with
  builder Node, Annotation, field replacement and import work. Source tree,
  collection, Decode index/access/view, key admission, Unicode normalization
  and Writer constructors provide their own representation recipes. Original
  document, origin, Span and input backing remain borrowed. The recipe
  conservatively co-counts their text inside the two tree envelopes.
- Synchronization: one synchronous import and one overlapping admitted snapshot
  share this quantity. Repeated imports need repeated retained storage. Source
  snapshots and their decode indices remain real distinct constructions; the
  outside caller must also bound final emission and its overlap.
- Failure: existing import and snapshot limits, duplicate-key and foreign-owner
  refusal are unchanged. Constructor quantities include failed and returned
  carriers, but do not certify that the requested import will succeed.
- Cancellation: this pure synchronous projection has no separate cancellation,
  close or cleanup owner. It does not retire input or acknowledge a borrower.
- Resources: the Source tree owner covers two tree envelopes; the shared
  collection owner covers work/child arrays and explicit builder records;
  Decode owns indexed and shallow access, including detached array Cursors; normalization owns Unicode growth.
  TextOutput uses normalized-key output plus unchanged value text to bound
  the scalar measuring Writer's control and intentionally
  overcounts text backing. This is logical construction DATA, not heap supply,
  a new tariff, unused capacity or permission to allocate before a parent grow.
- Extension: no lowerer, parser, language limit, serializer or owner is added.
  Future builder constructor changes must update their inventory and callers;
  quantity success does not admit new query or request semantics.
- Verification: focused tests cover invalid and growing geometry, the actual
  nested import/snapshot, expanding normalized keys, unchanged scalar strings,
  and foreign cursor separation. Request-level tests
  separately cover retained and execution one-short grows before repeated alias
  lowering and reuse of the exact original quote after capacity becomes free.
