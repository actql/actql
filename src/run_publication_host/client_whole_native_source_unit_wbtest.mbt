///|
// Real checked ownership and complete captured-input ports; explicit synthetic
// metadata observations only. No Host, physical Source, Model or Store ACK is
// claimed by this fixture. The ordinary Native caller remains a separate case.
test "whole Source Unit evidence keeps original producer and refuses foreign or retired capture" {
  let (compilation, _, _, _, _) = bound_effect_source_fixture()
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
    observed_at: "2026-10-12T00:00:00.000Z",
    snapshot_ref: "fixture-snapshot",
  }).unwrap()
  let retention = product_expiry_original_retention(product_test_originals())
  let acquired = issue_client_whole_native_effect_source_unit(
    prepared, direct, 0, captured, identity, acquisition, input, observation, authority,
    retention, 16384, 1024, 20,
  ).unwrap()
  assert_true(acquired.purpose is SingleSourceUnit)
  assert_true(physical_equal(acquired.identity, identity))
  assert_true(physical_equal(acquired.captured, captured))
  assert_true(physical_equal(acquired.observation, observation))
  assert_true(
    client_effect_local_invocation_matches(acquired.invocation, prepared, 0),
  )
  let (foreign, _, _, _, _) = bound_effect_source_fixture()
  assert_true(
    issue_client_whole_native_effect_source_unit(
      client_effect_compilation_owner(foreign),
      direct,
      0,
      captured,
      identity,
      acquisition,
      input,
      observation,
      authority,
      retention,
      16384,
      1024,
      20,
    )
    is Err(Invocation(ForeignCapturedInput)),
  )
  assert_true(
    issue_client_whole_native_effect_source_unit(
      prepared, direct, 1, captured, identity, acquisition, input, observation, authority,
      retention, 16384, 1024, 20,
    )
    is Err(Invocation(ForeignCapturedInput)),
  )
  assert_true(
    issue_client_whole_native_effect_source_unit(
      prepared,
      direct,
      0,
      captured,
      identity,
      acquisition,
      input,
      observation,
      "sha256:" + "c".repeat(64),
      retention,
      16384,
      1024,
      20,
    )
    is Err(Invocation(ForeignSourceObservation)),
  )
  live.val = false
  assert_true(
    issue_client_whole_native_effect_source_unit(
      prepared, direct, 0, captured, identity, acquisition, input, observation, authority,
      retention, 16384, 1024, 20,
    )
    is Err(Invocation(ForeignCapturedInput)),
  )
}

///|
test "Source-only Unit provenance refuses the original inline Model pipeline" {
  let (prepared, _, _, _) = selected_infer_original_fixture()
  let occurrence = prepared_client_effect_infer_occurrence(prepared).unwrap()
  let program = @checked.effect_program_static_checked_computation(
    prepared.candidate,
  )
  let pipeline = @checked.unit_pipeline(program, occurrence.stage).unwrap()
  assert_false(client_effect_source_unit_without_model(pipeline))
}
