# Installed typed UPDATE Mapping continuation

- Responsibility: Common generates UPDATE Mapping DATA from the same retained
  full Relation declaration used by the ordinary installed Source/Effect owner.
  It delegates to `prepare_relation_row_write_mapping`; this is not another
  schema compiler or an authorization, approval or dispatch mechanism.
- Inputs and outputs: the bounded closed wire is
  `{"writes":[{"resource","primary_identity","update":{"fields","permission","approval"}}]}`.
  Typed sources retain their existing target, source-field and null-behavior
  roles. The output is the existing `RowMapping` and unchanged Node metadata
  projection with reference, CID, canonical body, written and omittable fields.
- Identity: the original declaration supplies resource kind, complete nested
  target contracts, connector manifest and resource identity. Write facts cannot
  replace its schema. The existing constructor owns canonical Mapping identity.
- Ownership: the original SourceInitialization retains the declaration and
  generated Mappings. The continuation constructs DATA only and creates no new
  resource owner, installed connector, Source, Effect or persistent capability.
- Synchronization: the pure synchronous constructor checks every declared write
  before selecting the requested resource. Its Host caller retains the same
  initialization/current/one-shot Mapping continuation and reservation fences.
- Failure: unknown members, duplicate JSON members/resources/fields, malformed
  write facts, missing original fields, identity writes, invalid null behavior,
  unsupported approval and bounded-parser or output failures refuse normally.
  An invalid unselected specification cannot be hidden by selection order.
- Cancellation: no physical work or cleanup acknowledgement is issued. The
  existing initialization and Effect owners retain cancellation and retirement.
- Resources: source and write JSON are bounded before UPDATE reconstruction.
  The existing initialization owner must fund constructor and retained-output
  overlap before invoking it; a Mapping or input byte size is not a capacity
  quotation or physical backing proof.
- Extension: the existing CREATE port, wire and semantic constructor remain
  unchanged. The new UPDATE port shares its metadata/source-map adapter and
  delegates to the original typed Relation Mapping owner, preserving Decimal,
  nested Array/Object and declared nullable contracts without primitive labels.
- Verification: `relation_update_mapping_wbtest.mbt` covers full-type constructor
  equivalence, null/omission rules, invalid closed facts and sibling checks.
  `client_relation_update_mapping_wbtest.mbt` checks actual bridge metadata and
  bounded source-map refusal. Neither establishes installed current grants,
  approval, execution claims, physical mutation or whole-workflow acceptance.
