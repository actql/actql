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
    cid("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
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
fn issuer(state : SiteDispatchJournal) -> RemoteEvidenceIssuer {
  ignore(state)
  let site = @site.create_site(
    "site-a",
    1,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  register_remote_evidence_issuer(
    site,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    "local",
    "local/1",
    "strategy/1",
    "actql.remote.physical-output/0.1",
    cid("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
  ).unwrap()
}

///|
fn managed_output_issuer() -> RemoteEvidenceIssuer {
  let site = @site.create_site(
    "site-a",
    1,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  register_remote_evidence_issuer(
    site,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    "local",
    "local/1",
    "strategy/1",
    remote_managed_output_evidence_kind(),
    cid("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
  ).unwrap()
}

///|
fn managed_output_measurement() -> RemoteManagedOutputMeasurement {
  prepare_remote_managed_output_measurement(
    2,
    0,
    0,
    0,
    [2],
    [2],
    [2],
    [1],
    [0],
    [10],
  ).unwrap()
}

///|
fn execution_capability() -> RemoteExecutionCapability {
  let site = @site.create_site(
    "site-a",
    1,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  register_remote_execution_capability(
    site,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    "local",
    "local/1",
    "strategy/1",
    cid("4444444444444444444444444444444444444444444444444444444444444444"),
  ).unwrap()
}

///|
test "managed output measurement is canonical bounded and independently admitted" {
  let measurement = managed_output_measurement()
  let body = remote_managed_output_measurement_json(measurement).unwrap()
  assert_eq(
    body, "{\"admission_nodes\":0,\"admission_text_bytes\":0,\"admission_work\":0,\"columns\":[{\"admitted_depth\":10,\"bytes\":2,\"max_value_bytes\":1,\"nodes\":2,\"null_rows\":0,\"rows\":2}],\"row_count\":2,\"version\":\"actql-remote-managed-output-measurement/0.1\"}",
  )
  let projection = remote_managed_output_measurement_projection(measurement)
  assert_eq(projection, [[2, 0, 0, 0], [2], [2], [2], [1], [0], [10]])
  assert_true(
    admit_remote_managed_output_measurement(
      2,
      0,
      0,
      0,
      [2],
      [2],
      [2],
      [1],
      [0],
      [10],
      remote_managed_output_measurement_cid(measurement),
    )
    is Ok(_),
  )
  assert_true(
    prepare_remote_managed_output_measurement(
      2,
      0,
      0,
      0,
      [1],
      [2],
      [2],
      [1],
      [0],
      [10],
    )
    is Err(InvalidDispatch),
  )
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
  commit_dispatch_transition(
    prepare_begin_provisioning(record, execution_capability()).unwrap(),
    true,
  ).unwrap()
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
fn restart(
  state : SiteDispatchJournal,
  replacement : @site.ExecutionSite,
) -> Int {
  commit_site_generation_restart(
    prepare_site_generation_restart(state, replacement).unwrap(),
    true,
  ).unwrap()
}

///|
test "dispatch budget has exact portable capacity identity" {
  let budget = prepare_remote_dispatch_budget(7L, 3L).unwrap()
  assert_eq(
    remote_dispatch_budget_cid(budget),
    "sha256:0ce75ae8786ca7a9136f6a4e7158ea77a5b67b948d9b2540502936dd7115215b",
  )
  assert_eq(
    remote_dispatch_budget_json(budget).unwrap(),
    "{\"execution_bytes\":\"3\",\"retained_bytes\":\"7\",\"version\":\"actql-remote-dispatch-budget/0.1\"}",
  )
  assert_eq(remote_dispatch_budget_capacity(budget), (7L, 3L))
  assert_true(prepare_remote_dispatch_budget(-1L, 0L) is Err(InvalidDispatch))
  assert_true(
    admit_remote_dispatch_budget(7L, 4L, remote_dispatch_budget_cid(budget))
    is Err(DispatchIdentityMismatch),
  )
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
    "sha256:64b3898a97352d0e8c2daec377af6335bc51a06b471e9118677c6d1facc3a5ba",
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
    cid("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
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
    cid("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
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
      issue_remote_execution_evidence(
        issuer(state),
        record,
        cid("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"),
      ).unwrap(),
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
test "unknown execution is reconciled only after cleanup confirmation" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, failed) = accept(state, request("dispatch-a", 1, 1, bundle))
  provision(failed)
  execute(failed)
  assert_true(
    prepare_reconcile_failed_execution(failed) is Err(InvalidTransition),
  )
  commit_dispatch_transition(
    prepare_mark_execution_unknown(failed).unwrap(),
    true,
  ).unwrap()
  commit_dispatch_transition(
    prepare_reconcile_failed_execution(failed).unwrap(),
    true,
  ).unwrap()
  let (failed_execution, _, failed_cleanup, _, _) = dispatch_record_state(
    failed,
  )
  assert_eq(failed_execution, ExecutionFailed)
  assert_eq(failed_cleanup, CleanupUnknown)
  let (_, cancelled) = accept(state, request("dispatch-b", 2, 1, bundle))
  provision(cancelled)
  execute(cancelled)
  commit_dispatch_transition(
    prepare_mark_execution_unknown(cancelled).unwrap(),
    true,
  ).unwrap()
  commit_dispatch_transition(
    prepare_reconcile_cancelled_execution(cancelled).unwrap(),
    true,
  ).unwrap()
  let (cancelled_execution, _, cancelled_cleanup, _, _) = dispatch_record_state(
    cancelled,
  )
  assert_eq(cancelled_execution, ExecutionCancelled)
  assert_eq(cancelled_cleanup, CleanupUnknown)
}

///|
test "registered issuer binds evidence to exact dispatch and material" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, record) = accept(state, request("dispatch-a", 1, 1, bundle))
  let wrong_issuer = register_remote_evidence_issuer(
    replacement_site(1, bundle),
    bundle,
    "local",
    "local/1",
    "strategy/1",
    remote_managed_output_evidence_kind(),
    cid("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"),
  ).unwrap()
  assert_true(
    prepare_begin_managed_provisioning(
      record,
      execution_capability(),
      wrong_issuer,
    )
    is Err(InvalidDispatch),
  )
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
  let evidence = issue_remote_execution_evidence(
    issuer(state),
    record,
    cid("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"),
  ).unwrap()
  assert_eq(
    remote_execution_evidence_cid(evidence),
    "sha256:b3ee413eb44ae2a6b688c4406bde6ca0c64335e49b3aa4764d303ae794572704",
  )
  assert_eq(
    remote_execution_evidence_json(evidence).unwrap(),
    "{\"connector_registration\":\"local\",\"connector_revision\":\"local/1\",\"dispatch_request_cid\":\"sha256:64b3898a97352d0e8c2daec377af6335bc51a06b471e9118677c6d1facc3a5ba\",\"evidence_kind\":\"actql.remote.physical-output/0.1\",\"evidence_subject_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"holding_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"issuer_capability_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"material_generation\":\"material-generation-a\",\"obligations_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"runtime_bundle_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"site_generation\":1,\"site_key\":\"site-a\",\"strategy_revision\":\"strategy/1\",\"version\":\"actql-remote-execution-evidence/0.1\"}",
  )
  let foreign_site = replacement_site(1, bundle)
  let wrong = register_remote_evidence_issuer(
    foreign_site,
    bundle,
    "local",
    "local/2",
    "strategy/1",
    "actql.remote.physical-output/0.1",
    cid("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
  ).unwrap()
  assert_true(
    issue_remote_execution_evidence(
      wrong,
      record,
      cid("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"),
    )
    is Err(InvalidDispatch),
  )
}

///|
test "managed output subject has an independent canonical identity" {
  let dispatch = request(
    "dispatch-a",
    1,
    1,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  let measurement = managed_output_measurement()
  let subject = prepare_remote_managed_output_subject(
    dispatch_request_identity(dispatch),
    "material-generation-a",
    cid("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
    cid("3333333333333333333333333333333333333333333333333333333333333333"),
    cid("4444444444444444444444444444444444444444444444444444444444444444"),
    cid("5555555555555555555555555555555555555555555555555555555555555555"),
    cid("6666666666666666666666666666666666666666666666666666666666666666"),
    cid("7777777777777777777777777777777777777777777777777777777777777777"),
    remote_managed_output_measurement_cid(measurement),
    2,
    8L,
  ).unwrap()
  assert_eq(
    remote_managed_output_subject_json(subject).unwrap(),
    "{\"dispatch_request_cid\":\"sha256:64b3898a97352d0e8c2daec377af6335bc51a06b471e9118677c6d1facc3a5ba\",\"holding_evidence_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"logical_view_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"managed_profile_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"material_generation\":\"material-generation-a\",\"measurement_evidence_cid\":\"sha256:eecf2bab4ef5dc77dc89eee5b6bcc3c5d75d457d9d28d58fac85d5c0a6306a51\",\"physical_manifest_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"representation_codec_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"result_schema_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"retained_bytes\":\"8\",\"row_count\":2,\"version\":\"actql-remote-managed-output-subject/0.2\"}",
  )
  assert_eq(
    remote_managed_output_subject_cid(subject),
    "sha256:086791f0ee077bdb887ff9f796816323ae0f6aebde77c189a503504c0b9d90f2",
  )
  assert_true(remote_managed_output_subject_matches_dispatch(subject, dispatch))
  assert_true(
    admit_remote_managed_output_subject(
      dispatch_request_identity(dispatch),
      "material-generation-a",
      cid("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
      cid("3333333333333333333333333333333333333333333333333333333333333333"),
      cid("4444444444444444444444444444444444444444444444444444444444444444"),
      cid("5555555555555555555555555555555555555555555555555555555555555555"),
      cid("6666666666666666666666666666666666666666666666666666666666666666"),
      cid("7777777777777777777777777777777777777777777777777777777777777777"),
      remote_managed_output_measurement_cid(measurement),
      3,
      8L,
      remote_managed_output_subject_cid(subject),
    )
    is Err(DispatchIdentityMismatch),
  )
}

///|
test "managed output evidence accepts only its typed retained subject" {
  let state = journal()
  let dispatch = request(
    "dispatch-a",
    1,
    1,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  let (_, record) = accept(state, dispatch)
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
  let measurement = managed_output_measurement()
  let subject = prepare_remote_managed_output_subject(
    dispatch_request_identity(dispatch),
    "material-generation-a",
    cid("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
    cid("3333333333333333333333333333333333333333333333333333333333333333"),
    cid("4444444444444444444444444444444444444444444444444444444444444444"),
    cid("5555555555555555555555555555555555555555555555555555555555555555"),
    cid("6666666666666666666666666666666666666666666666666666666666666666"),
    cid("7777777777777777777777777777777777777777777777777777777777777777"),
    remote_managed_output_measurement_cid(measurement),
    2,
    8L,
  ).unwrap()
  let evidence = issue_remote_managed_output_evidence(
    managed_output_issuer(),
    record,
    subject,
  ).unwrap()
  assert_eq(
    remote_execution_evidence_cid(evidence),
    "sha256:39bc9a762f4e87674d3700ae3d762652d857052a387a62a860034e19f5245dae",
  )
  assert_true(
    remote_managed_output_subject_matches_evidence(subject, evidence, dispatch),
  )
  assert_true(
    remote_managed_output_subject_matches_measurement(subject, measurement),
  )
  let foreign = prepare_remote_managed_output_subject(
    dispatch_request_identity(dispatch),
    "material-generation-b",
    cid("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
    cid("3333333333333333333333333333333333333333333333333333333333333333"),
    cid("4444444444444444444444444444444444444444444444444444444444444444"),
    cid("5555555555555555555555555555555555555555555555555555555555555555"),
    cid("6666666666666666666666666666666666666666666666666666666666666666"),
    cid("7777777777777777777777777777777777777777777777777777777777777777"),
    remote_managed_output_measurement_cid(measurement),
    2,
    8L,
  ).unwrap()
  assert_false(
    remote_managed_output_subject_matches_evidence(foreign, evidence, dispatch),
  )
  assert_true(
    issue_remote_managed_output_evidence(
      managed_output_issuer(),
      record,
      foreign,
    )
    is Err(InvalidDispatch),
  )
}

///|
test "execution transition requires durable exact CAS" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, record) = accept(state, request("dispatch-a", 1, 1, bundle))
  let first = prepare_begin_provisioning(record, execution_capability()).unwrap()
  assert_eq(dispatch_record_revision(record), 0)
  assert_eq(dispatch_transition_projection(first), [
    "0", "0", "0", "0", "0", "0", "", "", "", "1", "1", "0", "0", "0", "0", "", "",
    "",
  ])
  assert_eq(
    commit_dispatch_transition(first, false),
    Err(DurabilityUnconfirmed),
  )
  let competing = prepare_begin_provisioning(record, execution_capability()).unwrap()
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
    restart(
      state,
      replacement_site(
        2,
        cid("cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"),
      ),
    ),
    1,
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
      issue_remote_execution_evidence(
        issuer(state),
        record,
        cid("dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"),
      ).unwrap(),
    ).unwrap(),
    true,
  ).unwrap()
  ignore(
    restart(
      state,
      replacement_site(
        2,
        cid("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
      ),
    ),
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
    cid("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
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
  assert_true(
    prepare_site_generation_restart(
      state,
      replacement_site(
        2,
        cid("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
      ),
    )
    is Err(QuarantinedCapacity),
  )
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
  assert_true(
    prepare_site_generation_restart(
      state,
      replacement_site(
        2,
        cid("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
      ),
    )
    is Err(QuarantinedCapacity),
  )
}

///|
test "runtime failure planning owns settlement ordering" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, record) = accept(state, request("dispatch-runtime-a", 20, 1, bundle))
  provision(record)
  execute(record)
  let failed = prepare_remote_runtime_failure(record, false, true).unwrap()
  assert_eq(remote_runtime_step_action_code(failed), 2)
  commit_dispatch_transition(
    remote_runtime_step_transition(failed).unwrap(),
    true,
  ).unwrap()
  let (execution, evidence, cleanup, available, quarantined) = dispatch_record_state(
    record,
  )
  assert_eq(execution, ExecutionFailed)
  assert_eq(evidence, NoEvidence)
  assert_eq(cleanup, CleanupActive)
  assert_false(available)
  assert_false(quarantined)
}

///|
test "runtime cleanup waits for stop then advances one durable fact at a time" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, record) = accept(state, request("dispatch-runtime-b", 21, 1, bundle))
  provision(record)
  execute(record)
  let uncertain = prepare_remote_runtime_failure(record, false, false).unwrap()
  assert_eq(remote_runtime_step_action_code(uncertain), 1)
  commit_dispatch_transition(
    remote_runtime_step_transition(uncertain).unwrap(),
    true,
  ).unwrap()
  let waiting = prepare_remote_runtime_cleanup(record, false, false, false).unwrap()
  assert_eq(remote_runtime_step_action_code(waiting), 0)
  assert_true(remote_runtime_step_transition(waiting) is Err(InvalidTransition))
  let stopped = prepare_remote_runtime_cleanup(record, false, true, false).unwrap()
  assert_eq(remote_runtime_step_action_code(stopped), 2)
  commit_dispatch_transition(
    remote_runtime_step_transition(stopped).unwrap(),
    true,
  ).unwrap()
  let releasing = prepare_remote_runtime_cleanup(record, false, true, false).unwrap()
  assert_eq(remote_runtime_step_action_code(releasing), 1)
  commit_dispatch_transition(
    remote_runtime_step_transition(releasing).unwrap(),
    true,
  ).unwrap()
  let reclaim = prepare_remote_runtime_cleanup(record, false, true, false).unwrap()
  assert_eq(remote_runtime_step_action_code(reclaim), 3)
  let reclaimed = prepare_remote_runtime_cleanup(record, false, true, true).unwrap()
  assert_eq(remote_runtime_step_action_code(reclaimed), 1)
  commit_dispatch_transition(
    remote_runtime_step_transition(reclaimed).unwrap(),
    true,
  ).unwrap()
  let finished = prepare_remote_runtime_cleanup(record, false, true, true).unwrap()
  assert_eq(remote_runtime_step_action_code(finished), 4)
  assert_true(
    remote_runtime_step_transition(finished) is Err(InvalidTransition),
  )
}

///|
test "runtime cancellation and evidence rejection use common progress" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, cancelled) = accept(
    state,
    request("dispatch-runtime-c", 22, 1, bundle),
  )
  assert_true(remote_runtime_record_startable(cancelled))
  let cancel = prepare_remote_runtime_failure(cancelled, true, false).unwrap()
  assert_eq(remote_runtime_step_action_code(cancel), 1)
  commit_dispatch_transition(
    remote_runtime_step_transition(cancel).unwrap(),
    true,
  ).unwrap()
  assert_false(remote_runtime_record_startable(cancelled))
  let (_, rejected) = accept(
    state,
    request("dispatch-runtime-d", 23, 1, bundle),
  )
  provision(rejected)
  execute(rejected)
  settle(rejected)
  let reject = prepare_remote_runtime_failure(rejected, false, true).unwrap()
  assert_eq(remote_runtime_step_action_code(reject), 1)
  commit_dispatch_transition(
    remote_runtime_step_transition(reject).unwrap(),
    true,
  ).unwrap()
  let (_, evidence, _, available, _) = dispatch_record_state(rejected)
  assert_eq(evidence, EvidenceRejected)
  assert_false(available)
}

///|
test "runtime reclaim failure remains retryable without releasing responsibility" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, record) = accept(state, request("dispatch-runtime-e", 24, 1, bundle))
  provision(record)
  execute(record)
  settle(record)
  commit_dispatch_transition(
    prepare_begin_remote_release(record).unwrap(),
    true,
  ).unwrap()
  let uncertain = prepare_remote_runtime_reclaim_unknown(record).unwrap()
  assert_eq(remote_runtime_step_action_code(uncertain), 1)
  commit_dispatch_transition(
    remote_runtime_step_transition(uncertain).unwrap(),
    true,
  ).unwrap()
  let retry = prepare_remote_runtime_cleanup(record, false, true, false).unwrap()
  assert_eq(remote_runtime_step_action_code(retry), 1)
  commit_dispatch_transition(
    remote_runtime_step_transition(retry).unwrap(),
    true,
  ).unwrap()
  assert_eq(
    remote_runtime_step_action_code(
      prepare_remote_runtime_cleanup(record, false, true, false).unwrap(),
    ),
    3,
  )
}
