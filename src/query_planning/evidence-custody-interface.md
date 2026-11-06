# Original query evidence custody

The Common registration, selected attempt authority, retained scan/output and
issued records remain the original owners used by Direct Row acquisitions and
DuckDB Broad acquisitions. This interface describes their existing issuance
and retirement boundaries. It grants no Source permission and acknowledges
neither physical stop nor allocation release.

- Responsibility: `QueryEvidenceCustody` verifies the original registration,
  authority, issuer, attempt and retention for issuance, one-shot capture and
  consumer binding. `retire_query_evidence_custody` severs only that custody's
  reciprocal issued/captured references; it creates no replacement evidence.
- Inputs and outputs: the retirement input is an original opaque
  `QueryEvidenceIssued`. Its Bool reports whether those references were retired
  or already absent. It is not a transport, cleanup or Resource receipt.
- Identity: the stored issued handle must be physically identical to the input.
  Live verification still checks the exact registration/authority/issuer/attempt,
  retained row-wire handles and original transport callback. Equal documents,
  CIDs, row counts and reconstructed records cannot replace these identities.
- Ownership: escaped records retain their immutable artifacts, and escaped
  captured observations retain document, CID and usage DATA. The owning attempt
  separately drops its records/observation state after successful retirement;
  clearing only one side would leave a reference-counted cycle. Escaped DATA
  aliases may continue to retain memory until their holders release them.
- Synchronization: retirement is synchronous and invokes no callback. A live
  successful capture is refused without mutation. Once the original registration
  is closed, retirement is idempotent; a failed pre-capture issued set can be
  retired while its registration remains live. Neither path can reopen it.
- Failure: rejected retirement preserves its original holder and references.
  Issuance/capture failures retire only records stored in that same attempt,
  never foreign records supplied to a failed verification call. A failed real
  residual or provider cleanup preserves the existing cleanup owner for retry.
- Cancellation: abort of a successful Captured attempt remains nondestructive.
  An EvidenceIssued abort can retire its uncaptured custody before becoming
  Failed. Successful captured custody retires only after registration revocation
  and the caller's required cleanup; logical close alone is not physical ACK.
- Resources: no child list, callback registry, new Ledger, allocation credit,
  budget or numeric profile is introduced. Accounted Row retirement follows
  successful residual/provider cleanup and original holding/reservation
  settlement. Unaccounted Row retirement waits for its residual if one exists.
- Extension: DuckDB Broad uses the same original issued custody and retires it
  after `cleanup_duckdb_broad_residual` succeeds, including its no-child case.
  Raw issuer close only revokes authority; a holder still owes that cleanup.
  Row Input/Keyed states and DuckDB native evidence keep their separate existing
  cleanup contracts. Registration cannot enumerate or retire arbitrary attempts.
- Verification: `src/query_integration/evidence_retirement_wbtest.mbt` checks
  uncaptured retirement, live-capture refusal, closed DATA aliases, cancellation,
  failed issued records and accounted/unaccounted Row cleanup. Existing capture
  lifetime and DuckDB Broad cleanup tests retain their failure/retry assertions.
  These references are not test results. Actual Native physical retirement must
  be observed by the original retained-execution owner after aliases leave scope;
  JS liveness or zero logical reservations cannot substitute for that result.
