# Declared relation-document DATA

- Responsibility: Common admits one explicitly selected physical JSON relation
  under its retained original Relation declaration. One explicit byte input is
  admitted into a shared original before per-relation projection. No model-specific
  sample data or parsed document is cached. The document and row handles
  contain DATA only. They do not issue a Source, ResourceRef, ContentRef, grant,
  approval, current observation, file installation or dispatch claim.
- Inputs and outputs: original admission takes explicit bytes and finite page
  and total-work bounds. Each projection takes that same original, the retained
  declaration, resource, items path, optional explicit key-metadata path, primary
  Text identity and declared writable fields. A present key path must select
  exactly one Text field name equal to the primary identity in the same admitted
  JSON document. The installed Node bridge requires that path. Common also
  supports an explicitly absent key path for documents without key metadata.
- Identity: every row has the original declared closed schema and a unique,
  non-null Text identity. Observation requires the same declaration and original
  document. The version is the canonical typed value digest of the complete row,
  not file-currentness evidence. A copied row, foreign document or stale expected
  version cannot prepare a replacement. Compound keys are not implemented here.
- Ownership: the opaque original owns one byte copy and full structurally
  admitted cursor. All relation projections share those exact bytes and cursor
  backing while retaining their own declared schemas and selected typed rows.
  Row handles retain the corresponding original projection.
  Read-only getters expose bounded Text, exact UTF-8 bytes, row count and Text
  identities; they cannot create reference authority or normalize content.
- Synchronization: update preparation checks original row/document correspondence
  and expected value version synchronously. The actual Host must still check the
  installed original file, current authorization, approval and durable claim,
  and conditionally replace the exact observed bytes. No I/O occurs here.
- Failure: malformed documents, unknown or missing selected-row fields, duplicate
  identities, invalid key metadata, non-writable updates, type failures and
  exhausted bounds refuse without prepared output. Reads require the actual
  acquisition/view, charged byte count and input contracts. Failed acceptance
  aborts the same existing RowRun; it cannot substitute another attempt.
- Cancellation: the DATA handles have no independent cancellation or cleanup
  acknowledgement. Charged acceptance uses the existing RowRun state and page
  ticket, whose logical abort and physical retirement remain separate.
- Resources: input bytes, nodes, depth, rows and work are bounded before output.
  One admitted original retains the full byte/cursor copy. All projection
  attempts, including failures and repeated requests, consume its same finite
  work counter, with no per-projection reset. Hosts must fund the raw constructor
  and all simultaneously retained projection outputs before reading; sequential
  calls alone do not prove physical retirement. The usage getter reports only
  bounded cumulative observations, not a pre-I/O quotation or retirement proof.
  Selected capture is rechecked against actual input
  contracts and retention limits. Updated bytes replace only validated original
  value spans, preserving every other byte, key order and whitespace.
- Extension: physical values follow declared full nested contracts rather than
  inferred row shapes. Int64 accepts canonical decimal Text and exact JSON
  integer tokens, read from original byte spans without a Double conversion.
  This intentionally broadens the former churn-specific numeric-only codec;
  fractions, exponent spelling, noncanonical Text and overflow remain refused.
  Typed UPDATE wire retains normal Common value encoding, including JsonData
  wrappers, which are removed only when encoding physical JSON payloads. Other
  model relations require their own declared projection of the same original;
  no business-specific sibling names or implicit key paths are recognized. The
  older combined admission entry remains a single-projection convenience, not
  the multi-relation Host path.
- Verification: `relation_document_target_wbtest.mbt` covers typed Array/Decimal
  updates, exact untouched bytes, Unicode content, nominal originals, stale
  versions, unique identities, declared writable fields, bounds, nested JSON,
  full Int64 endpoints, explicit key metadata, shared original backing,
  cumulative successful/failed projection budgets and externally replaced data. These focused Core checks do
  not establish installed Host transport, funding, conditional writes, normal
  Source/Content/Effect composition or generated artifact acceptance.

The Node and RelA bridge functions project these same Common ports. Their
UPDATE Mapping constructor delegates to the retained original Relation Mapping
owner, using only the explicitly declared writable fields, permission and
approval data. A Mapping does not grant current permission. RelA is an exact
source mirror, not another schema, parser, compiler or authority issuer.
