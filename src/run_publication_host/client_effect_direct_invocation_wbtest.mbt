///|
// Actual checked Whole capture, compilation, admission and Definition. Source
// observation DATA is synthetic; no provider read, Host or physical ACK claim.
test "Whole Effect invocation retains complete originals without Query evidence" {
  let (compilation, allowed, definition, _, _) = bound_effect_source_fixture()
  let prepared = client_effect_compilation_owner(compilation)
  let graph = @strategy.checked_effect_computation_graph(prepared.graph)
  let direct = select_client_effect_direct_acquisition_occurrences(
    prepared, 1000000,
  ).unwrap()
  let acquisition = prepare_client_effect_source_acquisition(prepared, 0, 0).unwrap()
  let owner = @strategy.graph_task_owner(graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(owner, run_materials_limits().sequence).unwrap()
  let rows = @execution.capture_input(
    owner,
    0,
    [scalar_profile_cursor("{\"amount\":7,\"id\":1}")],
    max_rows=1,
    string_try_number_execution_limits().rows.input_values,
  ).unwrap()
  let live = Ref(true)
  let original = @execution.prepare_supplied_relation_read(owner, 0, rows, () => {
    live.val
  }).unwrap()
  let proof = Ref(original)
  let port = @query.prepare_trusted_source_input_capture_port(
    whole_source_capture_contracts(),
    sequence,
    acquisition,
    @checked.source_identity(@strategy.graph_program(graph)),
    2,
    8,
    fn(actual : Ref[@execution.SuppliedRelationRead]) {
      if physical_equal(actual, proof) && live.val {
        Some((actual.val, 41))
      } else {
        None
      }
    },
  ).unwrap()
  let captured = @query.capture_verified_source_input(port, proof).unwrap()
  let wire : @execution.RowWireLimits = {
    max_columns: 2,
    max_order_work: 10000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let identity = @query.identify_captured_source_relation(
    captured,
    1,
    {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 20,
      max_work: 1000000,
    },
    wire,
    wire,
    { max_fields: 2, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    20000,
  ).unwrap()
  let input = issue_captured_whole_source_input_logical(
    graph, captured, identity, acquisition,
  ).unwrap()
  let facts = @planning.source_acquisition_evidence_facts(acquisition).unwrap()
  let authority = "sha256:" + "a".repeat(64)
  let observation = @publication.seal_completed_source_observation({
    input,
    source_ref: facts.source_ref,
    source_contract_cid: facts.source_contract_cid,
    schema_evidence_cid: facts.carrier_schema_contract_cid,
    capability_evidence_cid: "sha256:" + "b".repeat(64),
    authority_scope_cid: authority,
    source_data_policy_cid: facts.source_data_policy_cid,
    data_classification: facts.data_classification,
    source_view_contract_cid: facts.source_view_contract_cid,
    observed_at: "2026-10-09T00:00:00.000Z",
    snapshot_ref: "fixture-snapshot",
  }).unwrap()
  let policy = prepared_client_effect_publication_data_policy_cid(prepared).unwrap()
  let admission = client_effect_allowed_run_admission(allowed)
  let invoke = fn(actual, origins, source_values) {
    issue_client_effect_direct_sources_invocation(
      prepared,
      actual,
      admission,
      definition,
      direct,
      [captured],
      [identity],
      origins,
      source_values,
      [input],
      authority,
      policy,
      "2026-10-09T00:00:00.000Z",
      "2026-10-09T00:00:00.000Z",
      16384,
      1024,
      20,
    )
  }
  let (observations, invocation) = invoke(
    compilation,
    [WholeSourceOriginal(acquisition)],
    [observation],
  ).unwrap()
  assert_true(
    @publication.run_evidence_value_json(observations).contains(
      @publication.run_evidence_value_identity(observation),
    ),
  )
  assert_true(
    @publication.publication_contract_json(invocation).contains(
      @publication.run_evidence_value_identity(observations),
    ),
  )
  assert_true(invoke(compilation, [], [observation]) is Err(_))
  assert_true(
    invoke(compilation, [WholeSourceOriginal(acquisition)], []) is Err(_),
  )
  let (foreign, _, _, _, _) = bound_effect_source_fixture()
  assert_true(
    invoke(foreign, [WholeSourceOriginal(acquisition)], [observation]) is Err(_),
  )
  live.val = false
  assert_true(
    invoke(compilation, [WholeSourceOriginal(acquisition)], [observation])
    is Err(_),
  )
}
