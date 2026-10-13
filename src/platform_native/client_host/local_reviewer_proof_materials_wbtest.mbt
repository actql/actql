///|
fn reviewer_proof_same_row(
  actual : @sqlite.NativeJournalValue,
  expected : @sqlite.NativeJournalValue,
) -> Unit raise {
  assert_eq(actual.revision, expected.revision)
  assert_eq(actual.body, expected.body)
}

///|
// Matching Native definitions only until allocated. The real journal fixture
// authenticates its rows; its explicit setup authority is transaction-test
// scaffolding, not a test of Reviewer authorization or public Effect Approval.
test "Reviewer proof snapshot reads the exact original journal without changing its Run" {
  let (host, _, request, artifact) = local_checkpoint_lookup_fixture(
    "reviewer-proof-snapshot-original",
  )
  let before = host.database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  let original = local_reviewer_proof_snapshot(
    host.journal,
    request,
    artifact.checkpoint.run_definition_cid().unwrap(),
    artifact.checkpoint_cid,
  ).unwrap()
  assert_eq(original.artifact, artifact)
  assert_eq(original.state.status, @publication.WaitingCheckpoint)
  assert_false(original.cancellation_requested)
  assert_eq(original.reported_unknown_effect_count, 0)
  reviewer_proof_same_row(
    host.database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap(),
    before,
  )
  let repeated = local_reviewer_proof_snapshot(
    host.journal,
    request,
    artifact.checkpoint.run_definition_cid().unwrap(),
    artifact.checkpoint_cid,
  ).unwrap()
  assert_true(repeated == original)
  host.close().unwrap()
}

///|
test "Reviewer proof snapshot rejects foreign original Run Checkpoint and unknown request without repair" {
  let (host, _, request, artifact) = local_checkpoint_lookup_fixture(
    "reviewer-proof-snapshot-foreign",
  )
  for
    (run, checkpoint) in [
      ("sha256:" + "f".repeat(64), artifact.checkpoint_cid),
      (
        artifact.checkpoint.run_definition_cid().unwrap(),
        "sha256:" + "f".repeat(64),
      ),
    ] {
    assert_true(
      local_reviewer_proof_snapshot(host.journal, request, run, checkpoint)
      is Err(ForeignRun),
    )
  }
  let (other, _, other_request, _) = local_checkpoint_lookup_fixture(
    "reviewer-proof-snapshot-other",
  )
  // The foreign Host's authenticated row is not sought or copied here.
  assert_true(
    local_reviewer_proof_snapshot(
      host.journal,
      other_request,
      artifact.checkpoint.run_definition_cid().unwrap(),
      artifact.checkpoint_cid,
    )
    is Err(CustodyLost),
  )
  other.close().unwrap()
  host.close().unwrap()
}

///|
test "Reviewer proof snapshot missing waiting material does not create a Checkpoint" {
  let (host, _, request, artifact) = local_checkpoint_lookup_fixture(
    "reviewer-proof-snapshot-missing",
    waiting=false,
  )
  let before = host.database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap()
  assert_true(
    local_reviewer_proof_snapshot(
      host.journal,
      request,
      artifact.checkpoint.run_definition_cid().unwrap(),
      artifact.checkpoint_cid,
    )
    is Err(Checkpoint(NeedsOriginalContinuation)),
  )
  reviewer_proof_same_row(
    host.database
    .read("client_runs", @host.client_request_scope_cid(request))
    .unwrap(),
    before,
  )
  assert_true(
    host.journal.retained(request).unwrap().unwrap().checkpoint is None,
  )
  host.close().unwrap()
}

///|
test "Reviewer proof snapshot preserves cancellation revision and uncertain Effect facts" {
  let (host, _, request, artifact) = local_checkpoint_lookup_fixture(
    "reviewer-proof-snapshot-cancel",
  )
  let original = local_reviewer_proof_snapshot(
    host.journal,
    request,
    artifact.checkpoint.run_definition_cid().unwrap(),
    artifact.checkpoint_cid,
  ).unwrap()
  // Existing journal mutation only, preserving the original artifact and no
  // signature/admission/dispatch. This does not pretend cancellation settled.
  host.journal
  .transaction(() => {
    let record = host.journal.retained(request).unwrap().unwrap()
    let checkpoint = record.checkpoint.unwrap()
    let changed : NativeClientRunRecord = {
      ..record,
      revision: record.revision + 1L,
      cancellation_requested: true,
      checkpoint: Some({
        ..checkpoint,
        unknown_effects: ["unresolved-write"],
        settlement_only: false,
      }),
    }
    guard host.journal.database
      .compare_exchange(
        "client_runs",
        @host.client_request_scope_cid(request),
        record.revision,
        run_record_body(changed).unwrap(),
      )
      .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
      is Ok(next) &&
      next == record.revision + 1L else {
      return Err(Checkpoint(StaleRevision))
    }
    Ok(())
  })
  .unwrap()
  let changed = local_reviewer_proof_snapshot(
    host.journal,
    request,
    artifact.checkpoint.run_definition_cid().unwrap(),
    artifact.checkpoint_cid,
  ).unwrap()
  assert_eq(changed.artifact, original.artifact)
  assert_eq(changed.revision, original.revision + 1L)
  assert_true(changed.cancellation_requested)
  assert_eq(changed.reported_unknown_effect_count, 1)
  assert_false(changed.settlement_only)
  assert_true(changed != original)
  host.close().unwrap()
}
