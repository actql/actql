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

## Discarding private construction originals

- Responsibility: `discard_relation_document_original` and
  `discard_relation_target_document_original` only sever the supplied DATA
  handle's self-original reference. Neither operation is a cleanup owner.
- Inputs and outputs: each function takes its original opaque document and
  returns true only when this call clears its own mark. Already discarded or
  copied carriers return false; the result is not a physical cleanup receipt.
- Identity: discard requires `Some(original)` physically equal to the supplied
  handle. It does not follow a copied carrier to mutate another object, and it
  does not weaken any getter, projection or charged-admission identity check.
- Ownership: callers discard only their private construction originals, normally
  projections before their raw backing. Target discard never changes its parent
  or siblings. Escaped immutable values and the stored payload are unchanged.
- Synchronization: both operations are synchronous and callback-free. Child
  discard checks its own mark without requiring a live parent, so mistaken
  parent-first invalidation does not prevent later child discard.
- Failure: false makes no mutation. After discard, existing getters return None
  and projection/observation/admission retain their ordinary ForeignSource or
  typed refusal. A retained previously returned scalar or byte value is not
  rewritten, and no discarded handle can restore original status.
- Cancellation: discarding DATA issues no abort, physical stop, closed-file
  acknowledgement or release of an accounted RowRun. Those remain with the
  original provider and RowRun cleanup, including every failed cleanup retry.
- Resources: no child list, callback, counter, allocation credit or capacity
  change is added. The existing constructor inventory already includes these
  self Option references. Clearing them permits ordinary reference-counted
  reclamation only after remaining aliases disappear; it does not prove it.
- Extension: this pair covers separately constructed raw and target documents.
  The separate `discard_relation_target_row_original` severs one observation's
  self mark after its consumer returns, including after parent invalidation.
  It refuses copies and repeated discard, without retiring a sibling or changing
  already returned immutable DATA. It acknowledges neither read nor physical
  cleanup. Hosts still own those lifetimes and every escaped alias.
  These entries do not retire the hidden backing produced by
  `admit_relation_target_document`, including that convenience entry's failed
  projection path. Those existing caller boundaries remain separate; this is
  not complete retirement of the relation-document family or Effect handles.
- Verification: `relation_document_discard_wbtest.mbt` checks self-only mutation,
  copied-carrier refusal, immutable retained DATA, sibling isolation and child
  discard after parent invalidation. Source callers must still demonstrate real
  original retained-execution closure; these references do not establish it.

Whole-Source response admission uses the same original document/ticket path as
Query-backed rows. `accept_charged_relation_input_document` matches the original
`RowInputAcquisition` after consuming the response ticket, preserves its declared
schema/view and page limits, and uses the existing whole-input value funding
before append. It does not turn a Query requirement into a whole Source, issue a
read grant, refund physical attempts/bytes or acknowledge transport cleanup.

The installing caller may retain a `RelationDocumentPreparedContract` constructed
by `prepare_relation_document_contract` from the original declaration. It keeps
the same checked schema, field order and primary identity; it issues no Source,
Reference, capacity or read permission. A later projection accepts it only with
the original declaration, selected resource/identity and the same metadata
bounds. Copied declaration DATA cannot substitute for that original. The
compatibility entrance still constructs its mapping when no prepared metadata
is supplied.

Prepared metadata removes schema parsing/hashing and schema construction from
response projection. Every actual path, explicit key, closed row, duplicate
identity, typed value and cumulative document-work limit remains checked.
Mapping work is charged only on the branch which actually reconstructs it.
The original caller funds metadata before construction and retains it through
all borrowers; response admission and physical cleanup remain separate duties.
