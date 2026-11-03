# Declared relation-document DATA

- Responsibility: Common admits one explicitly selected physical JSON relation
  under its retained original Relation declaration. The document and row handles
  contain DATA only. They do not issue a Source, ResourceRef, ContentRef, grant,
  approval, current observation, file installation or dispatch claim.
- Inputs and outputs: admission takes the original declaration, resource, items
  path, optional explicit key-metadata path, primary Text identity, declared
  writable fields, bytes and finite bounds. A present key path must select
  exactly one Text field name equal to the primary identity in the same admitted
  JSON document. The installed Node bridge requires that path. Common also
  supports an explicitly absent key path for documents without key metadata.
- Identity: every row has the original declared closed schema and a unique,
  non-null Text identity. Observation requires the same declaration and original
  document. The version is the canonical typed value digest of the complete row,
  not file-currentness evidence. A copied row, foreign document or stale expected
  version cannot prepare a replacement. Compound keys are not implemented here.
- Ownership: the opaque document owns its byte copy, full structurally admitted
  cursor and selected typed rows. Row handles retain that original document.
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
  Each document retains its own full byte/cursor copy. Hosts validating sibling
  relations must account for all simultaneously retained originals and projection
  outputs; sequential calls alone do not prove physical retirement. Selected
  capture is rechecked against actual input
  contracts and retention limits. Updated bytes replace only validated original
  value spans, preserving every other byte, key order and whitespace.
- Extension: physical values follow declared full nested contracts rather than
  inferred row shapes. Int64 accepts canonical decimal Text and exact JSON
  integer tokens, read from original byte spans without a Double conversion.
  This intentionally broadens the former churn-specific numeric-only codec;
  fractions, exponent spelling, noncanonical Text and overflow remain refused.
  Typed UPDATE wire retains normal Common value encoding, including JsonData
  wrappers, which are removed only when encoding physical JSON payloads. Other
  model relations require their own declared admission; no business-specific
  sibling names or implicit key paths are recognized.
- Verification: `relation_document_target_wbtest.mbt` covers typed Array/Decimal
  updates, exact untouched bytes, Unicode content, nominal originals, stale
  versions, unique identities, declared writable fields, bounds, nested JSON,
  full Int64 endpoints and explicit key metadata. These focused Core checks do
  not establish installed Host transport, funding, conditional writes, normal
  Source/Content/Effect composition or generated artifact acceptance.

The Node and RelA bridge functions project these same Common ports. Their
UPDATE Mapping constructor delegates to the retained original Relation Mapping
owner, using only the explicitly declared writable fields, permission and
approval data. A Mapping does not grant current permission. RelA is an exact
source mirror, not another schema, parser, compiler or authority issuer.
