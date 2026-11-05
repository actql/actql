///|
fn completed_output_test_delegation(
  request : @remote.DispatchRequest,
) -> @resident.ResidentSiteDelegation {
  let scope = @remote.dispatch_request_execution_scope(request)
  {
    coordinator_authority: @remote.dispatch_request_journal_key(request)[0],
    site_key: scope[0],
    runtime_bundle_cid: scope[2],
    connector_registration: scope[3],
    connector_revision: scope[4],
    strategy_revision: scope[5],
    grant_cid: scope[6],
    evidence_issuer_capability_cid: scope[7],
    budget_cids: [@remote.dispatch_request_budget_cid(request)],
  }
}

///|
/// Formal handoff through the real Journal, not a physical cleanup ACK. The
/// Source process acceptance separately observes its original failure cleanup.
test "ended failed Source release retains the same formal cleanup and request duty" {
  let (_, journal, request, _, site) = cleanup_test_open(
    "ended-failed-source-release",
  )
  let delegation = completed_output_test_delegation(request)
  let (_, record) = journal.accept(request).unwrap()
  let scope = @remote.dispatch_request_execution_scope(request)
  let capability = @remote.register_remote_execution_capability(
    site,
    scope[2],
    scope[3],
    scope[4],
    scope[5],
    scope[6],
  ).unwrap()
  journal
  .commit_transition(
    @remote.prepare_begin_provisioning(record, capability).unwrap(),
  )
  .unwrap()
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  journal
  .commit_transition(@remote.prepare_confirm_execution_failed(record).unwrap())
  .unwrap()
  assert_eq(@remote.dispatch_record_state_codes(record), [4, 0, 0, 0, 0])
  let failed_revision = @remote.dispatch_record_revision(record)
  assert_false(begin_ended_holder_release(journal, delegation, 4, request))
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    failed_revision,
  )
  journal
  .commit_transition(@remote.prepare_begin_remote_release(record).unwrap())
  .unwrap()
  journal
  .commit_transition(@remote.prepare_confirm_remote_release(record).unwrap())
  .unwrap()
  assert_eq(@remote.dispatch_record_state_codes(record), [4, 0, 2, 0, 0])
  let released_revision = @remote.dispatch_record_revision(record)
  assert_true(
    @resident_host.begin_resident_output_release(
      journal, delegation, 4, request,
    )
    is Err(OutputUnavailable),
  )
  for _ in 0..<2 {
    assert_true(begin_ended_holder_release(journal, delegation, 4, request))
    assert_eq(
      @remote.dispatch_record_revision(journal.require(request).unwrap()),
      released_revision,
    )
  }
  assert_false(
    begin_ended_holder_release(
      journal,
      { ..delegation, grant_cid: cleanup_test_cid("0".repeat(64)), },
      4,
      request,
    ),
  )
  assert_eq(
    @remote.dispatch_record_state_codes(journal.require(request).unwrap()),
    [4, 0, 2, 0, 0],
  )
  assert_true(journal.close())
}

///|
/// These exercise the actual controller selection gate with its durable
/// journal. They do not claim restoration or public Result acceptance.
test "output reconstruction does not start missing accepted or running attempts" {
  let (_, journal, request, _, site) = cleanup_test_open("output-not-completed")
  let delegation = completed_output_test_delegation(request)
  let queue = @resident.ResidentAcceptedQueue::new(2).unwrap()
  let select = () => {
    queue_completed_output_holder(journal, delegation, 4, queue, request)
  }
  assert_false(select())
  let record = journal.accept(request).unwrap().1
  assert_false(select())
  let scope = @remote.dispatch_request_execution_scope(request)
  let capability = @remote.register_remote_execution_capability(
    site,
    scope[2],
    scope[3],
    scope[4],
    scope[5],
    scope[6],
  ).unwrap()
  assert_eq(
    journal
    .claim_start(
      @remote.prepare_begin_provisioning(record, capability).unwrap(),
      "original-output-holder",
    )
    .unwrap(),
    @journal.Won,
  )
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  |> ignore
  assert_false(select())
  let revision = @remote.dispatch_record_revision(
    journal.require(request).unwrap(),
  )
  assert_false(select())
  assert_eq(queue.length(), 0)
  assert_eq(
    journal.start_claimant(request).unwrap(),
    Some("original-output-holder"),
  )
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    revision,
  )
  assert_true(journal.close())
}

///|
test "output reconstruction rejects stale generation cancelled and released custody" {
  let (_, journal, request, _, _) = cleanup_test_open("output-cancelled")
  let delegation = completed_output_test_delegation(request)
  let queue = @resident.ResidentAcceptedQueue::new(2).unwrap()
  ignore(journal.accept(request).unwrap())
  assert_false(
    queue_completed_output_holder(journal, delegation, 3, queue, request),
  )
  ignore(journal.request_cancellation(request).unwrap())
  assert_false(
    queue_completed_output_holder(journal, delegation, 4, queue, request),
  )
  assert_true(confirm_unstarted_consumer_cleanup(journal, request))
  let revision = @remote.dispatch_record_revision(
    journal.require(request).unwrap(),
  )
  assert_false(
    queue_completed_output_holder(journal, delegation, 4, queue, request),
  )
  assert_eq(queue.length(), 0)
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    revision,
  )
  assert_true(journal.close())
}

///|
let completed_output_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
let completed_output_document : String =
  #|{"version":"actql/0.1","id":"completed-output","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":3}]},"as":"out"}],"results":{"rows":{"from":"out","fields":["id"]}}},{"id":"compute","inputs":{"x":{"result":{"stage":"source","result":"rows"}}},"steps":[{"filter":"id > 2"},{"as":"out","select":["id"]}],"results":{"rows":{"from":"out","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"compute","result":"rows"}}}}

///|
fn completed_output_materials_fixture(
  document? : String = completed_output_document,
) -> (@remote.DispatchRequest, String, @remote.RemoteInputBinding) {
  let environment = @host.admit_client_check_environment(
    completed_output_environment,
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = @host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @host.issue_prepared_client_task_compilation(
    prepared,
    manifests,
    @host.client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_compiled_run_definition(
    allowed, "resident-source", "original-run", "2026-10-05T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let caller = @host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-caller",
  ).unwrap()
  let request = @host.prepare_client_task_dispatch(
    prepared,
    compilation,
    @host.client_compiled_run_admission(allowed),
    definition,
    caller,
    0,
    1,
    "original-producer",
    {
      site_key: "retained-native",
      site_generation: 1,
      runtime_bundle_cid: "sha256:" + "d".repeat(64),
      connector_registration: "local",
      connector_revision: "local/1",
      strategy_revision: "strategy/1",
      obligations_cid: "sha256:" + "2".repeat(64),
      budget_cid: "sha256:" + "3".repeat(64),
      evidence_issuer_capability_cid: "sha256:" + "4".repeat(64),
      grant_cid: "sha256:" + "5".repeat(64),
    },
  ).unwrap()
  let materials = @host.issue_client_task_run_materials(
    prepared,
    compilation,
    @host.client_compiled_run_admission(allowed),
    definition,
    environment,
    completed_output_environment,
    document,
    None,
  ).unwrap()
  (
    request,
    materials,
    @host.prepare_client_task_input_binding(prepared, 0).unwrap(),
  )
}

///|
fn completed_output_custody_fixture(
  name : String,
  file_custody? : Bool = true,
) -> (
  @journal.Journal,
  @remote.DispatchRequest,
  @remote.DispatchRecord,
  @resident.ResidentSiteDelegation,
  @sqlite.Library,
  String,
  @site.ExecutionSite,
) raise {
  let (request, materials, binding) = completed_output_materials_fixture()
  let scope = @remote.dispatch_request_execution_scope(request)
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/" +
    name +
    ".sqlite3"
  let site = @site.create_site(scope[0], 1, scope[2], 4, 4, 1048576L, 1048576L).unwrap()
  let journal = @journal.open_journal(
    library,
    path,
    1048576L,
    @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap(),
  ).unwrap()
  journal
  .retain_dispatch_envelope(
    request,
    @remote.remote_poll_dispatch_materials_json(request, binding, materials).unwrap(),
  )
  .unwrap()
  let record = journal.accept(request).unwrap().1
  let capability = @remote.register_remote_execution_capability(
    site,
    scope[2],
    scope[3],
    scope[4],
    scope[5],
    scope[6],
  ).unwrap()
  assert_eq(
    journal
    .claim_start(
      @remote.prepare_begin_provisioning(record, capability).unwrap(),
      "original-completed-holder",
    )
    .unwrap(),
    @journal.Won,
  )
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  |> ignore
  journal
  .commit_transition(@remote.prepare_confirm_native_settled(record).unwrap())
  .unwrap()
  |> ignore
  let cid = cleanup_test_cid("6".repeat(64))
  let manifest = @output_manifest.admit(
    "actql-managed-physical-manifest/0.1",
    cid,
    cid,
    cid,
    1,
    [cid],
    [1L],
    [1],
    1,
    4096,
    1L,
  ).unwrap()
  let generation = "original-completed-output"
  let holding = @remote.remote_output_holding_evidence_cid(
    request, generation, 1L,
  ).unwrap()
  journal
  .commit_transition(
    @remote.prepare_retain_remote_output(record, generation, holding).unwrap(),
  )
  .unwrap()
  |> ignore
  let measurement = @remote.prepare_remote_managed_output_measurement(
    1,
    0,
    0,
    0,
    [1],
    [1],
    [1],
    [1],
    [0],
    [1],
  ).unwrap()
  let subject = @remote.prepare_remote_managed_output_subject(
    @remote.dispatch_request_identity(request),
    generation,
    holding,
    cid,
    cid,
    cid,
    cid,
    @output_manifest.manifest_cid(manifest),
    @remote.remote_managed_output_measurement_cid(measurement),
    1,
    1L,
  ).unwrap()
  let issuer = @remote.register_remote_evidence_issuer(
    site,
    scope[2],
    scope[3],
    scope[4],
    scope[5],
    @remote.remote_managed_output_evidence_kind(),
    scope[7],
  ).unwrap()
  let evidence = @remote.issue_remote_managed_output_evidence(
    issuer, record, subject,
  ).unwrap()
  let custody = @journal.prepare_native_output_file_custody(
    request,
    "original-output",
    { device: 1UL, inode: 2UL, size: 1L, },
    cid,
    generation,
    manifest,
  ).unwrap()
  journal
  .commit_evidence_transition(
    @remote.prepare_durable_execution_evidence(record, evidence).unwrap(),
    evidence,
    subject,
    measurement,
    file_custody=if file_custody { Some(custody) } else { None },
  )
  .unwrap()
  |> ignore
  (
    journal,
    request,
    record,
    completed_output_test_delegation(request),
    library,
    path,
    site,
  )
}

///|
test "completed output selection survives journal reopen without another start claim" {
  let (journal, request, _, delegation, library, path, site) = completed_output_custody_fixture(
    "output-completed-reopen",
  )
  let queue = @resident.ResidentAcceptedQueue::new(2).unwrap()
  let select = current => {
    queue_completed_output_holder(current, delegation, 1, queue, request)
  }
  let revision = @remote.dispatch_record_revision(
    journal.require(request).unwrap(),
  )
  assert_true(select(journal))
  assert_true(select(journal))
  let attempt = @remote.dispatch_request_attempt_identity(request).unwrap()
  assert_eq(queue.length(), 1)
  assert_eq(queue.next(), Some(attempt))
  assert_true(journal.close())
  let reopened = @journal.open_journal(
    library,
    path,
    1048576L,
    @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap(),
  ).unwrap()
  assert_true(select(reopened))
  assert_eq(queue.length(), 1)
  assert_eq(
    @remote.dispatch_record_revision(reopened.require(request).unwrap()),
    revision,
  )
  assert_eq(
    reopened.start_claimant(request).unwrap(),
    Some("original-completed-holder"),
  )
  assert_true(queue.remove(attempt))
  queue.reserve("another-attempt").unwrap()
  assert_false(select(reopened))
  assert_eq(queue.next(), Some("another-attempt"))
  assert_true(reopened.close())
}

///|
test "completed output selection preserves cleanup pending and rejects changed delegation" {
  let (journal, request, record, delegation, _, _, _) = completed_output_custody_fixture(
    "output-completed-cleanup",
  )
  let queue = @resident.ResidentAcceptedQueue::new(2).unwrap()
  assert_false(
    queue_completed_output_holder(
      journal,
      { ..delegation, grant_cid: cleanup_test_cid("9".repeat(64)), },
      1,
      queue,
      request,
    ),
  )
  assert_false(
    queue_completed_output_holder(journal, delegation, 2, queue, request),
  )
  journal
  .commit_transition(@remote.prepare_begin_remote_release(record).unwrap())
  .unwrap()
  |> ignore
  let revision = @remote.dispatch_record_revision(
    journal.require(request).unwrap(),
  )
  assert_false(
    queue_completed_output_holder(journal, delegation, 1, queue, request),
  )
  assert_eq(queue.length(), 0)
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    revision,
  )
  assert_true(journal.close())
}

///|
test "completed output without saved file custody remains pending without a queued start" {
  let (journal, request, _, delegation, _, _, _) = completed_output_custody_fixture(
    "output-completed-missing-custody",
    file_custody=false,
  )
  let queue = @resident.ResidentAcceptedQueue::new(2).unwrap()
  let revision = @remote.dispatch_record_revision(
    journal.require(request).unwrap(),
  )
  assert_false(
    queue_completed_output_holder(journal, delegation, 1, queue, request),
  )
  assert_eq(queue.length(), 0)
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    revision,
  )
  assert_eq(
    journal.start_claimant(request).unwrap(),
    Some("original-completed-holder"),
  )
  assert_true(journal.close())
}

///|
test "completed output cancellation does not turn completed work into another start" {
  let (journal, request, _, delegation, _, _, _) = completed_output_custody_fixture(
    "output-completed-cancelled",
  )
  let queue = @resident.ResidentAcceptedQueue::new(2).unwrap()
  ignore(journal.request_cancellation(request).unwrap())
  let record = journal.require(request).unwrap()
  assert_eq(@remote.dispatch_record_state_codes(record)[0], 3)
  let revision = @remote.dispatch_record_revision(record)
  assert_false(
    queue_completed_output_holder(journal, delegation, 1, queue, request),
  )
  assert_eq(queue.length(), 0)
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    revision,
  )
  assert_true(journal.close())
}
