///|
fn cid(fill : String) -> String {
  "sha256:" + fill
}

///|
fn request(
  dispatch_id : String,
  attempt : Int,
  generation : Int,
  bundle : String,
) -> DispatchRequest {
  prepare_dispatch_request(
    "coordinator-a",
    cid("0000000000000000000000000000000000000000000000000000000000000000"),
    "task-a",
    attempt,
    dispatch_id,
    "site-a",
    generation,
    bundle,
    "local",
    "local/1",
    "strategy/1",
    cid("1111111111111111111111111111111111111111111111111111111111111111"),
    cid("2222222222222222222222222222222222222222222222222222222222222222"),
    cid("3333333333333333333333333333333333333333333333333333333333333333"),
    cid("4444444444444444444444444444444444444444444444444444444444444444"),
  ).unwrap()
}

///|
fn journal() -> SiteDispatchJournal {
  let site = @site.create_site(
    "site-a",
    1,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap()
}

///|
fn replacement_site(generation : Int, bundle : String) -> @site.ExecutionSite {
  @site.create_site("site-a", generation, bundle, 4, 4, 1048576L, 1048576L).unwrap()
}

///|
fn accept(
  state : SiteDispatchJournal,
  dispatch : DispatchRequest,
) -> (DispatchAcceptance, DispatchRecord) {
  let admission = prepare_dispatch_acceptance(state, dispatch).unwrap()
  commit_dispatch_acceptance(admission, true).unwrap()
}

///|
fn provision(record : DispatchRecord) -> Unit {
  commit_dispatch_transition(prepare_begin_provisioning(record).unwrap(), true).unwrap()
}

///|
fn execute(record : DispatchRecord) -> Unit {
  commit_dispatch_transition(
    prepare_begin_remote_execution(record).unwrap(),
    true,
  ).unwrap()
}

///|
fn settle(record : DispatchRecord) -> Unit {
  commit_dispatch_transition(
    prepare_confirm_native_settled(record).unwrap(),
    true,
  ).unwrap()
}

///|
test "dispatch retransmission reconciles without admitting another attempt" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let first = request("dispatch-a", 1, 1, bundle)
  assert_eq(
    dispatch_request_identity(first),
    "sha256:062578c246f6324b7750d8784d5f4db17dd25bd659a4374e6732ddfe01c61065",
  )
  let admission = prepare_dispatch_acceptance(state, first).unwrap()
  assert_eq(dispatch_admission_kind(admission), NewDispatch)
  assert_true(
    commit_dispatch_acceptance(admission, false) is Err(DurabilityUnconfirmed),
  )
  let (accepted, record) = commit_dispatch_acceptance(admission, true).unwrap()
  assert_eq(accepted, NewDispatch)
  let retry = prepare_dispatch_acceptance(state, first).unwrap()
  assert_eq(
    dispatch_admission_request_json(retry).unwrap(),
    dispatch_request_json(first).unwrap(),
  )
  let (reconciled, same) = commit_dispatch_acceptance(retry, true).unwrap()
  assert_eq(reconciled, ExistingDispatch)
  assert_true(physical_equal(record, same))
  let collision = admit_dispatch_request(
    "coordinator-a",
    cid("0000000000000000000000000000000000000000000000000000000000000000"),
    "task-a",
    1,
    "dispatch-a",
    cid("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
    "site-a",
    1,
    bundle,
    "local",
    "local/1",
    "strategy/1",
    cid("1111111111111111111111111111111111111111111111111111111111111111"),
    cid("2222222222222222222222222222222222222222222222222222222222222222"),
    cid("3333333333333333333333333333333333333333333333333333333333333333"),
    cid("4444444444444444444444444444444444444444444444444444444444444444"),
  )
  assert_true(collision is Err(DispatchIdentityMismatch))
  let different = prepare_dispatch_request(
    "coordinator-a",
    cid("0000000000000000000000000000000000000000000000000000000000000000"),
    "task-a",
    1,
    "dispatch-a",
    "site-a",
    1,
    bundle,
    "local",
    "local/2",
    "strategy/1",
    cid("1111111111111111111111111111111111111111111111111111111111111111"),
    cid("2222222222222222222222222222222222222222222222222222222222222222"),
    cid("3333333333333333333333333333333333333333333333333333333333333333"),
    cid("4444444444444444444444444444444444444444444444444444444444444444"),
  ).unwrap()
  assert_true(
    prepare_dispatch_acceptance(state, different) is Err(DispatchCollision),
  )
  let duplicate_attempt = request("dispatch-b", 1, 1, bundle)
  assert_true(
    prepare_dispatch_acceptance(state, duplicate_attempt)
    is Err(AttemptAlreadyDispatched),
  )
}

///|
test "execution evidence and cleanup advance independently" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, record) = accept(state, request("dispatch-a", 1, 1, bundle))
  provision(record)
  execute(record)
  settle(record)
  assert_false(remote_completion_evidence_available(record))
  commit_dispatch_transition(
    prepare_retain_remote_output(
      record,
      "material-generation-a",
      cid("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
    ).unwrap(),
    true,
  ).unwrap()
  assert_false(remote_completion_evidence_available(record))
  commit_dispatch_transition(
    prepare_durable_execution_evidence(
      record,
      cid("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"),
    ).unwrap(),
    true,
  ).unwrap()
  assert_true(remote_completion_evidence_available(record))
  commit_dispatch_transition(
    prepare_begin_remote_release(record).unwrap(),
    true,
  ).unwrap()
  assert_true(remote_completion_evidence_available(record))
  commit_dispatch_transition(
    prepare_confirm_remote_release(record).unwrap(),
    true,
  ).unwrap()
  assert_false(remote_completion_evidence_available(record))
}

///|
test "execution transition requires durable exact CAS" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, record) = accept(state, request("dispatch-a", 1, 1, bundle))
  let first = prepare_begin_provisioning(record).unwrap()
  assert_eq(dispatch_record_revision(record), 0)
  assert_eq(dispatch_transition_projection(first), [
    "0", "0", "0", "0", "0", "0", "", "", "", "1", "1", "0", "0", "0", "0", "", "",
    "",
  ])
  assert_eq(
    commit_dispatch_transition(first, false),
    Err(DurabilityUnconfirmed),
  )
  let competing = prepare_begin_provisioning(record).unwrap()
  commit_dispatch_transition(first, true).unwrap()
  assert_eq(dispatch_record_revision(record), 1)
  assert_eq(commit_dispatch_transition(competing, true), Err(StateCollision))
}

///|
test "restart changes generation without reviving old authority" {
  let state = journal()
  let old_bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, record) = accept(state, request("dispatch-a", 1, 1, old_bundle))
  provision(record)
  execute(record)
  assert_eq(
    restart_site_generation(
      state,
      replacement_site(
        2,
        cid("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
      ),
    ),
    Ok(1),
  )
  let (execution, _, cleanup, available, _) = dispatch_record_state(record)
  assert_eq(execution, ExecutionUnknown)
  assert_eq(cleanup, CleanupUnknown)
  assert_false(available)
  assert_true(
    prepare_dispatch_acceptance(
      state,
      request("dispatch-old", 2, 1, old_bundle),
    )
    is Err(StaleSiteGeneration),
  )
}

///|
test "restart preserves settled history but requires current availability" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, record) = accept(state, request("dispatch-a", 1, 1, bundle))
  provision(record)
  execute(record)
  settle(record)
  commit_dispatch_transition(
    prepare_retain_remote_output(
      record,
      "material-generation-a",
      cid("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
    ).unwrap(),
    true,
  ).unwrap()
  commit_dispatch_transition(
    prepare_durable_execution_evidence(
      record,
      cid("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"),
    ).unwrap(),
    true,
  ).unwrap()
  ignore(
    restart_site_generation(
      state,
      replacement_site(
        2,
        cid("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
      ),
    ).unwrap(),
  )
  let (execution, evidence, cleanup, available, _) = dispatch_record_state(
    record,
  )
  assert_eq(execution, NativeSettled)
  assert_true(evidence is EvidenceDurable(_, _, _))
  assert_eq(cleanup, CleanupUnknown)
  assert_false(available)
  assert_false(remote_completion_evidence_available(record))
}

///|
test "dispatch admission validates every bound identity" {
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let invalid = prepare_dispatch_request(
    "coordinator-a",
    "not-a-cid",
    "task-a",
    1,
    "dispatch-a",
    "site-a",
    1,
    bundle,
    "local",
    "local/1",
    "strategy/1",
    cid("1111111111111111111111111111111111111111111111111111111111111111"),
    cid("2222222222222222222222222222222222222222222222222222222222222222"),
    cid("3333333333333333333333333333333333333333333333333333333333333333"),
    cid("4444444444444444444444444444444444444444444444444444444444444444"),
  )
  assert_true(invalid is Err(InvalidDispatch))
  let site = replacement_site(1, bundle)
  assert_true(
    create_site_dispatch_journal(site, "remote-site/1") is Err(InvalidJournal),
  )
}

///|
test "force loss quarantines capacity until exact late cleanup" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, record) = accept(state, request("dispatch-a", 1, 1, bundle))
  assert_true(
    prepare_force_loss(state, record, false) is Err(UnauthorizedForceLoss),
  )
  commit_force_loss(prepare_force_loss(state, record, true).unwrap(), true).unwrap()
  let (execution, _, cleanup, available, quarantined) = dispatch_record_state(
    record,
  )
  assert_eq(execution, ExecutionUnknown)
  assert_eq(cleanup, CleanupForceLost)
  assert_false(available)
  assert_true(quarantined)
  commit_dispatch_transition(
    prepare_reconcile_cleanup_after_loss(record).unwrap(),
    true,
  ).unwrap()
  let (_, _, reconciled, restored, still_quarantined) = dispatch_record_state(
    record,
  )
  assert_eq(reconciled, CleanupRecoveredAfterLoss)
  assert_false(restored)
  assert_false(still_quarantined)
  assert_false(remote_completion_evidence_available(record))
}
