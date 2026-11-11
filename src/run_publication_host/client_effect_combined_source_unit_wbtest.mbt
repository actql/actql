///|
// Actual checked same-Unit binary JOIN, original captures and completed local
// producer. Synthetic Source observations are not provider/Host acceptance.
fn combined_unit_whole_capture(
  prepared : PreparedClientEffectComputation,
  live : Ref[Bool],
  input_index : Int,
) -> (
  @query.CapturedInputSource,
  @query.CapturedSourceRelationIdentity,
  @acquisition.SourceAcquisition,
  @publication.RunEvidenceValue,
  @publication.RunEvidenceValue,
) {
  let graph = @strategy.checked_effect_computation_graph(prepared.graph)
  let acquisition = prepare_client_effect_source_acquisition(
    prepared, 0, input_index,
  ).unwrap()
  let owner = @strategy.graph_task_owner(graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(owner, run_materials_limits().sequence).unwrap()
  let rows = @execution.capture_input(
    owner,
    input_index,
    [scalar_profile_cursor("{\"amount\":7,\"id\":1}")],
    max_rows=1,
    string_try_number_execution_limits().rows.input_values,
  ).unwrap()
  let original = @execution.prepare_supplied_relation_read(
    owner,
    input_index,
    rows,
    () => live.val,
  ).unwrap()
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
    observed_at: "2026-11-11T00:00:01.000Z",
    snapshot_ref: "fixture-snapshot",
  }).unwrap()
  (captured, identity, acquisition, observation, input)
}

///|
fn combined_source_unit_completed_fixture(
  foreign_controls? : Bool = false,
) -> Unit raise {
  let document =
    #|{"version":"actql/0.1","id":"combined-source-unit","stages":[{"id":"joined","inputs":{"left_rows":{"connector":"crm/main","resource":"r"},"right_rows":{"connector":"crm/right","resource":"r"}},"from":"left_rows","steps":[{"join":{"with":"right_rows","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":4,"select":{"value":"left.id"}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"joined":{"from":{"stage":"joined","result":"out"}}}}
  let environment = admit_client_check_environment(
    bound_effect_source_environment,
    "sha256:e3da0e91ef758728bdf6e58957c09fe044d97d1fa2a21c9c19e3bdf5109bf45b",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    client_standard_effect_computation_limits(),
  ).unwrap()
  let bounds = run_materials_limits()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "combined-unit", "original-combined-run", "2026-11-11T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let direct = select_client_effect_direct_acquisition_occurrences(
    prepared, 1000000,
  ).unwrap()
  assert_eq(direct.coordinates, [(0, 0, 0), (0, 1, 0)])
  let left_live = Ref(true)
  let right_live = Ref(true)
  let left = combined_unit_whole_capture(prepared, left_live, 0)
  let right = combined_unit_whole_capture(prepared, right_live, 1)
  let captures = [left.0, right.0]
  let identities = [left.1, right.1]
  let originals = [WholeSourceOriginal(left.2), WholeSourceOriginal(right.2)]
  let sources = [left.3, right.3]
  let logical = [left.4, right.4]
  let authority = "sha256:" + "a".repeat(64)
  let policy = prepared_client_effect_publication_data_policy_cid(prepared).unwrap()
  let admission = client_effect_allowed_run_admission(allowed)
  let publication = prepare_client_effect_direct_sources_publication(
    prepared, compilation, admission, definition, direct, captures, identities, originals,
    sources, logical, authority, policy, "2026-11-11T00:00:01.000Z", "2026-11-11T00:00:02.000Z",
    100000, 10000, 100,
  ).unwrap()
  let retention = @publication.issue_result_retention_for_data_policy(
    product_expiry_original_retention(product_test_originals()),
    policy,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(
    issue_client_whole_native_effect_source_unit(
      prepared,
      direct,
      0,
      left.0,
      left.1,
      left.2,
      left.4,
      left.3,
      authority,
      retention,
      100000,
      10000,
      100,
    )
    is Err(Invocation(MissingUnit)),
  )
  let combined = prepare_client_effect_combined_source_unit(
    publication, 0, retention, 100000, 10000, 100,
  ).unwrap()
  assert_eq(combined.contributions.length(), 2)
  assert_eq(combined.contributions.map(value => value.slot), [0, 1])
  assert_true(
    prepare_client_effect_combined_source_unit(
      publication, 1, retention, 100000, 10000, 100,
    )
    is Err(_),
  )
  assert_true(
    prepare_client_effect_direct_sources_publication(
      prepared,
      compilation,
      admission,
      definition,
      direct,
      [right.0, left.0],
      identities,
      originals,
      sources,
      logical,
      authority,
      policy,
      "2026-11-11T00:00:01.000Z",
      "2026-11-11T00:00:02.000Z",
      100000,
      10000,
      100,
    )
    is Err(_),
  )
  assert_true(
    prepare_client_effect_direct_sources_publication(
      prepared,
      compilation,
      admission,
      definition,
      direct,
      [left.0],
      [left.1],
      [originals[0]],
      [left.3],
      [left.4],
      authority,
      policy,
      "2026-11-11T00:00:01.000Z",
      "2026-11-11T00:00:02.000Z",
      100000,
      10000,
      100,
    )
    is Err(_),
  )
  let graph = @strategy.checked_effect_computation_graph(prepared.graph)
  let root = @strategy.graph_task_owner(graph, 0).unwrap()
  let assets = client_local_product_assets()
  let contracts = @local_query_time.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let sequences = @local_query_time.prepare_client_effect_local_sequences(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let sequence = sequences[0]
  let execution = string_try_number_execution_limits()
  let measure : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let reads = captures.mapi((index, captured) => {
    let bound = @query.bind_captured_source_operation(captured, root, 0, index).unwrap()
    @execution.prepare_producer_read(root, bound, 10000, 20000).unwrap()
  })
  let provider = @local.local_bounded_relation_provider(
    execution, measure, sequence,
  ).unwrap()
  let child = @local.start_managed_provider_with_inputs_and_execution(
    provider,
    sequence,
    reads.map(@local.managed_provider_relation_input),
    100,
    20000,
    execution,
  ).unwrap()
  let mut completed = None
  for _ in 0..<10000 {
    match @local.advance_managed_provider(child, 31).unwrap() {
      @local.Complete(output, ..) => {
        completed = Some(output)
        break
      }
      @local.Continue(..) | @local.Settling(_, ..) => ()
      _ => fail("same original JOIN must complete")
    }
  }
  let output = completed.unwrap()
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(1.0)))
  let bindings = [(0, 0, reads[0]), (0, 1, reads[1])]
  let proof = @execution.retain_completed_segment_inputs(
    output, sequence, bindings, 100000,
  ).unwrap()
  let bound = bind_prepared_client_effect_run(prepared, admission, definition).unwrap()
  let selected = @strategy.prepare_source_inputs_dag(graph, [left.2, right.2]).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 100000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 10000000L,
    retained_bytes: 10000000L,
    execution_bytes: 10000000L,
  }).unwrap()
  let run = @strategy.open_source_inputs_effect_run_dag(
    prepared_client_effect_run_graph(bound),
    selected,
    captures,
    ledger,
    source_results=[(0, sequence, bindings, proof)],
  ).unwrap()
  assert_true(
    @strategy.captured_task_completed(@strategy.captured_effect_run_dag(run), 0),
  )
  let inputs = @strategy.pin_captured_effect_sources(run, 10).unwrap()
  let wire : @execution.RowWireLimits = {
    max_columns: 2,
    max_order_work: 10000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let exported = @strategy.start_captured_effect_local_result_export(
    inputs,
    0,
    {
      max_fields: 2,
      max_mapping_work: 1000,
      max_order_work: 10000,
      max_workspace_entries: 20,
    },
    10,
    execution.rows.input_values,
    wire,
    wire,
    { max_fields: 2, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    1000,
  ).unwrap()
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  for _ in 0..<100 {
    if @execution.advance_completed_result_relation_export(preparation, 64).unwrap().0 {
      break
    }
  }
  let stream = @execution.finish_completed_result_relation_export_preparation(
    preparation,
  ).unwrap()
  while @execution.next_completed_output_export_canonical_row(
          stream, 1000, 20, 1000,
        ).unwrap()
        is Some(_) {

  }
  let (receipt, _) = @execution.finish_completed_relation_export(stream).unwrap()
  let local_definition = issue_client_effect_local_result_definition(
    prepared, 0, "out", 100000, 10000, 100,
  ).unwrap()
  if foreign_controls {
    let foreign_definition = issue_client_effect_run_definition(
      allowed, "combined-unit", "foreign-combined-run", "2026-11-11T00:00:00.000Z",
      "2027-01-01T00:00:00.000Z",
    ).unwrap()
    assert_true(
      issue_combined_source_client_effect_local_result_artifact(
        prepared,
        inputs,
        exported,
        combined,
        local_definition,
        receipt,
        admission,
        foreign_definition,
        publication.source.invocation,
        publication.source.observation,
        100000,
        10000,
        100,
      )
      is Err(ForeignRun),
    )
    let other_export = @strategy.start_captured_effect_local_result_export(
      inputs,
      0,
      {
        max_fields: 2,
        max_mapping_work: 1000,
        max_order_work: 10000,
        max_workspace_entries: 20,
      },
      10,
      execution.rows.input_values,
      wire,
      wire,
      { max_fields: 2, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
      1000,
    ).unwrap()
    let other_preparation = @strategy.captured_effect_local_result_export_preparation(
      other_export,
    )
    for _ in 0..<100 {
      if @execution.advance_completed_result_relation_export(
          other_preparation, 64,
        ).unwrap().0 {
        break
      }
    }
    let other_stream = @execution.finish_completed_result_relation_export_preparation(
      other_preparation,
    ).unwrap()
    while @execution.next_completed_output_export_canonical_row(
            other_stream, 1000, 20, 1000,
          ).unwrap()
          is Some(_) {

    }
    let (other_receipt, _) = @execution.finish_completed_relation_export(
      other_stream,
    ).unwrap()
    assert_true(
      issue_combined_source_client_effect_local_result_artifact(
        prepared,
        inputs,
        exported,
        combined,
        local_definition,
        other_receipt,
        admission,
        definition,
        publication.source.invocation,
        publication.source.observation,
        100000,
        10000,
        100,
      )
      is Err(ForeignExport),
    )
  } else {
    let artifact = issue_combined_source_client_effect_local_result_artifact(
      prepared,
      inputs,
      exported,
      combined,
      local_definition,
      receipt,
      admission,
      definition,
      publication.source.invocation,
      publication.source.observation,
      100000,
      10000,
      100,
    ).unwrap()
    assert_eq(
      client_effect_local_artifact_invocation_cid(artifact),
      combined.invocation.cid,
    )
    right_live.val = false
    assert_true(
      issue_combined_source_client_effect_local_result_artifact(
        prepared,
        inputs,
        exported,
        combined,
        local_definition,
        receipt,
        admission,
        definition,
        publication.source.invocation,
        publication.source.observation,
        100000,
        10000,
        100,
      )
      is Err(ForeignOwner),
    )
  }
  @strategy.release_captured_effect_inputs(inputs) |> ignore
  @local.cancel_managed_provider(child) |> ignore
  assert_true(@local.cleanup_managed_provider(child) is Ok(true))
}

///|
test "combined Source Unit keeps both original inputs and requires its actual completed producer" {
  combined_source_unit_completed_fixture()
}

///|
test "combined Source Unit refuses a foreign Run and another actual export receipt" {
  combined_source_unit_completed_fixture(foreign_controls=true)
}
