///|
fn runtime_record(state : String, sequence : Int64) -> PublicationContract {
  let prior = if sequence == 0L {
    "null"
  } else {
    "\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\""
  }
  let wire = "{\"cleanup_owner_cids\":[],\"failure_cid\":null,\"observed_at\":\"2026-09-19T00:00:00Z\",\"prior_record_cid\":" +
    prior +
    ",\"public_index_entry_cid\":null,\"publication_attempt_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"publication_record_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"sequence\":" +
    sequence.to_string() +
    ",\"state\":\"" +
    state +
    "\"}"
  let value = parse_contract_wire(wire, 4096, 128, 16).unwrap()
  {
    name: "publication_record",
    identity_field: "publication_record_cid",
    identity: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    wire,
    value,
  }
}

///|
test "publication attempt progression owns every record-state decision" {
  assert_eq(
    prepare_publication_attempt_step(None, false, false),
    PublicationAppendPreparing,
  )
  assert_eq(
    prepare_publication_attempt_step(None, true, false),
    PublicationAttemptInvalid,
  )
  let preparing = runtime_record("preparing", 0L)
  assert_eq(
    prepare_publication_attempt_step(Some(preparing), false, false),
    PublicationCheckActive,
  )
  assert_eq(
    prepare_publication_attempt_step(Some(preparing), true, false),
    PublicationAppendCommitting,
  )
  assert_eq(
    prepare_publication_attempt_step(Some(preparing), true, true),
    PublicationAttemptInvalid,
  )
  let committing = runtime_record("committing", 1L)
  assert_eq(
    prepare_publication_attempt_step(Some(committing), false, false),
    PublicationCheckActive,
  )
  assert_eq(
    prepare_publication_attempt_step(Some(committing), true, false),
    PublicationIssueIndex,
  )
  assert_eq(
    prepare_publication_attempt_step(Some(committing), true, true),
    PublicationCommitIndex,
  )
  assert_eq(
    prepare_publication_attempt_step(Some(committing), false, true),
    PublicationAttemptInvalid,
  )
  assert_eq(
    prepare_publication_attempt_step(
      Some(runtime_record("publication_unknown", 2L)),
      false,
      false,
    ),
    PublicationRequireReconciliation,
  )
  assert_eq(
    prepare_publication_attempt_step(
      Some(runtime_record("succeeded", 2L)),
      false,
      false,
    ),
    PublicationRejectMissingIndex,
  )
  assert_eq(
    prepare_publication_attempt_step(
      Some(runtime_record("cancelled", 2L)),
      false,
      false,
    ),
    PublicationRejectTerminal,
  )
}

///|
test "publication cancellation preserves the commit uncertainty boundary" {
  assert_eq(
    prepare_publication_cancellation_step(None),
    PublicationCancellationRethrow,
  )
  assert_eq(
    prepare_publication_cancellation_step(Some(runtime_record("preparing", 0L))),
    PublicationCancelPreparing,
  )
  assert_eq(
    prepare_publication_cancellation_step(
      Some(runtime_record("committing", 1L)),
    ),
    PublicationCancelCommitting,
  )
  assert_eq(
    prepare_publication_cancellation_step(
      Some(runtime_record("publication_unknown", 2L)),
    ),
    PublicationCancellationRethrow,
  )
}

///|
test "publication finalization distinguishes winner and superseded attempt" {
  let committing = runtime_record("committing", 1L)
  let unknown = runtime_record("publication_unknown", 2L)
  let succeeded = runtime_record("succeeded", 2L)
  let cancelled = runtime_record("cancelled", 2L)
  assert_eq(
    prepare_committed_publication_finalization(Some(committing)),
    PublicationAppendSucceeded,
  )
  assert_eq(
    prepare_committed_publication_finalization(Some(unknown)),
    PublicationAppendSucceeded,
  )
  assert_eq(
    prepare_committed_publication_finalization(Some(succeeded)),
    PublicationFinalizationFinished,
  )
  assert_eq(
    prepare_committed_publication_finalization(Some(cancelled)),
    PublicationFinalizationInvalid,
  )
  assert_eq(
    prepare_superseded_publication_finalization(Some(committing)),
    PublicationAppendSuperseded,
  )
  assert_eq(
    prepare_superseded_publication_finalization(Some(unknown)),
    PublicationAppendSuperseded,
  )
  assert_eq(
    prepare_superseded_publication_finalization(Some(cancelled)),
    PublicationSupersededConfirmed,
  )
  assert_eq(
    prepare_superseded_publication_finalization(None),
    PublicationFinalizationFinished,
  )
}

///|
test "publication commit failure reconciles before choosing an outcome" {
  assert_eq(
    prepare_publication_commit_failure_step(false, false, false, false),
    PublicationReconcileCommit,
  )
  assert_eq(
    prepare_publication_commit_failure_step(true, true, false, false),
    PublicationAppendUnknown,
  )
  assert_eq(
    prepare_publication_commit_failure_step(true, true, false, true),
    PublicationReturnUnknown,
  )
  assert_eq(
    prepare_publication_commit_failure_step(true, false, false, false),
    PublicationConfirmUncommittedFailure,
  )
  assert_eq(
    prepare_publication_commit_failure_step(true, false, true, false),
    PublicationAdoptCommittedIndex,
  )
  assert_eq(
    prepare_publication_commit_failure_step(false, true, false, false),
    PublicationCommitFailureInvalid,
  )
  assert_eq(
    prepare_publication_commit_failure_step(true, false, false, true),
    PublicationCommitFailureInvalid,
  )
}

///|
test "publication unknown retry reconciles before independent cleanup" {
  assert_eq(
    prepare_publication_unknown_retry_step(false, true, true, false),
    PublicationRetryReconcile,
  )
  assert_eq(
    prepare_publication_unknown_retry_step(true, true, true, false),
    PublicationRetryUpstreamCleanup,
  )
  assert_eq(
    prepare_publication_unknown_retry_step(true, true, true, true),
    PublicationUnknownRetryFinished,
  )
  assert_eq(
    prepare_publication_unknown_retry_step(true, true, false, false),
    PublicationUnknownRetryFinished,
  )
  assert_eq(
    prepare_publication_unknown_retry_step(false, true, true, true),
    PublicationUnknownRetryInvalid,
  )
}
