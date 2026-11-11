///|
// Actual checked mixed imported/local Source inputs. Observation metadata is
// synthetic; these component cases establish no provider or Host acceptance.
fn mixed_whole_infer_test_program() -> PreparedClientProgram raise {
  let document =
    #|{"version":"actql/0.1","id":"mixed-whole-model","stages":[{"id":"source","inputs":{"original":{"connector":"crm/main","resource":"r"}},"steps":[{"derive":{"adjusted":{"add":[{"field":"amount"},{"literal":1}]}}},{"select":["id",{"amount":"adjusted"}],"as":"rows"}],"results":{"rows":{"from":"rows","fields":["id","amount"]}}},{"id":"review","inputs":{"imported":{"result":{"stage":"source","result":"rows"}},"local":{"connector":"crm/right","resource":"r"}},"from":"imported","steps":[{"join":{"with":"local","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":2,"select":{"id":"left.id","amount":"left.amount"}}},{"derive":{"text":{"literal":"hello"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"assessed"}],"results":{"rows":{"from":"assessed","fields":["id","outcome","value"]}}},{"id":"confirm","inputs":{"reviewed":{"result":{"stage":"review","result":"rows"}}},"steps":[{"derive":{"text":{"literal":"confirm"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"confirmed"}],"results":{"rows":{"from":"confirmed","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"confirm","result":"rows"}}}}
  prepare_effect_free_client_program(
    document,
    Json,
    client_composed_effect_test_environment(source_input_program_environment()),
    None,
    client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
fn mixed_whole_infer_capture(
  prepared : PreparedClientProgram,
  slot : Int,
  live : Ref[Bool],
) -> (
  @query.CapturedInputSource,
  @query.CapturedSourceRelationIdentity,
  @acquisition.SourceAcquisition,
  @publication.RunEvidenceValue,
  @publication.RunEvidenceValue,
) {
  let graph = prepared.graph
  let direct = select_client_direct_acquisition_occurrences(prepared, 1000000).unwrap()
  let (stage, input, task) = client_direct_acquisition_occurrence_at(
    direct, slot,
  ).unwrap()
  let acquisition = prepare_client_source_acquisition(prepared, stage, input).unwrap()
  let owner = @strategy.graph_task_owner(graph, task).unwrap()
  let sequence = @lower.prepare_sequence_prefix(
    owner,
    0,
    run_materials_limits().sequence,
  ).unwrap()
  guard @acquisition.source_acquisition_input(acquisition)
    is @pipeline.Input(index) else {
    abort("original Whole input")
  }
  let rows = @execution.capture_input(
    owner,
    index,
    [scalar_profile_cursor("{\"amount\":7,\"id\":1}")],
    max_rows=1,
    string_try_number_execution_limits().rows.input_values,
  ).unwrap()
  let original = @execution.prepare_supplied_relation_read(owner, index, rows, () => {
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
  let source = @query.capture_verified_source_input(port, proof).unwrap()
  let wire : @execution.RowWireLimits = {
    max_columns: 2,
    max_order_work: 10000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let identity = @query.identify_captured_source_relation(
    source,
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
  let logical = issue_captured_whole_source_input_logical(
    graph,
    source,
    identity,
    acquisition,
    task~,
  ).unwrap()
  let facts = @planning.source_acquisition_evidence_facts(acquisition).unwrap()
  let observation = @publication.seal_completed_source_observation({
    input: logical,
    source_ref: facts.source_ref,
    source_contract_cid: facts.source_contract_cid,
    schema_evidence_cid: facts.carrier_schema_contract_cid,
    capability_evidence_cid: "sha256:" + "b".repeat(64),
    authority_scope_cid: "sha256:" + "a".repeat(64),
    source_data_policy_cid: facts.source_data_policy_cid,
    data_classification: facts.data_classification,
    source_view_contract_cid: facts.source_view_contract_cid,
    observed_at: "2026-11-12T00:00:01.000Z",
    snapshot_ref: "fixture-snapshot",
  }).unwrap()
  (source, identity, acquisition, logical, observation)
}

///|
test "mixed Whole Model sources retain imported producer and local ordinal through downstream Model" {
  let prepared = mixed_whole_infer_test_program()
  let models = prepared_client_composed_infer_occurrences(prepared).unwrap()
  assert_eq(models.length(), 2)
  let live = Ref(true)
  let left = mixed_whole_infer_capture(prepared, 0, live)
  let right = mixed_whole_infer_capture(prepared, 1, live)
  let sources = admit_client_infer_composed_whole_sources(
    models[0],
    [left.0, right.0],
    [left.1, right.1],
    [left.2, right.2],
    [left.3, right.3],
    [left.4, right.4],
    "sha256:" + "a".repeat(64),
    "2026-11-12T00:00:00.000Z",
    "2026-11-12T00:00:02.000Z",
  ).unwrap()
  assert_eq(sources.inputs.map(input => input.name), ["imported", "local"])
  assert_true(client_infer_composed_sources_matches(sources, models[0]))
  assert_true(client_infer_composed_sources_matches(sources, models[1]))
  let expected = infer_scope_expected_sources(models[1]).unwrap()
  assert_eq(expected.map(entry => entry.0), ["imported", "local"])
  live.val = false
  assert_false(client_infer_composed_sources_matches(sources, models[0]))
  assert_false(client_infer_composed_sources_matches(sources, models[1]))
}

///|
test "mixed Whole Model sources reject equal foreign Plan and swapped or missing original captures" {
  let prepared = mixed_whole_infer_test_program()
  let models = prepared_client_composed_infer_occurrences(prepared).unwrap()
  let left = mixed_whole_infer_capture(prepared, 0, Ref(true))
  let right = mixed_whole_infer_capture(prepared, 1, Ref(true))
  let foreign = mixed_whole_infer_test_program()
  let other = mixed_whole_infer_capture(foreign, 0, Ref(true))
  for
    (captures, identities, originals, logicals, evidence) in [
      (
        [right.0, left.0],
        [right.1, left.1],
        [right.2, left.2],
        [right.3, left.3],
        [right.4, left.4],
      ),
      (
        [other.0, right.0],
        [other.1, right.1],
        [other.2, right.2],
        [other.3, right.3],
        [other.4, right.4],
      ),
      ([left.0], [left.1], [left.2], [left.3], [left.4]),
    ] {
    assert_true(
      admit_client_infer_composed_whole_sources(
        models[0],
        captures,
        identities,
        originals,
        logicals,
        evidence,
        "sha256:" + "a".repeat(64),
        "2026-11-12T00:00:00.000Z",
        "2026-11-12T00:00:02.000Z",
      )
      is Err(ForeignInput),
    )
  }
}

///|
fn mixed_whole_infer_execute(
  sequence : @lower.PreparedSequence,
  inputs : Array[@execution.ProducerRead],
) -> @execution.CompletedOutput raise {
  let generated = local_group_generated(sequence)
  let execution = string_try_number_execution_limits()
  let provider = @local.local_bounded_relation_provider(
    execution,
    { max_work: 100000, max_bytes: 20000, max_nodes: 10000, max_depth: 20, },
    generated,
  ).unwrap()
  let child = @local.start_managed_provider_with_inputs_and_execution(
    provider,
    generated,
    inputs.map(@local.managed_provider_relation_input),
    100,
    20000,
    execution,
  ).unwrap()
  for _ in 0..<10000 {
    match @local.advance_managed_provider(child, 31).unwrap() {
      @local.Complete(output, ..) => return output
      @local.Continue(..) | @local.Settling(_, ..) => ()
      _ => fail("original mixed prefix must complete")
    }
  }
  fail("bounded original mixed prefix")
}

///|
fn mixed_whole_infer_completed_prefix(
  prepared : PreparedClientProgram,
  captures : Array[@query.CapturedInputSource],
) -> @execution.CompletedOutput raise {
  let models = prepared_client_composed_infer_occurrences(prepared).unwrap()
  let root = @strategy.graph_task_owner(prepared.graph, 0).unwrap()
  let source_sequence = @lower.prepare_sequence(
    root,
    run_materials_limits().sequence,
  ).unwrap()
  let source_read = @execution.prepare_producer_read(
    root,
    @query.bind_captured_source_operation(captures[0], root, 0, 0).unwrap(),
    10000,
    20000,
  ).unwrap()
  let completed_source = mixed_whole_infer_execute(source_sequence, [
    source_read,
  ])
  let consumer = models[0].preparation
  let prefix = @lower.prepare_sequence_prefix(
    consumer,
    models[0].step - 1,
    run_materials_limits().sequence,
  ).unwrap()
  let imported = @execution.prepare_producer_read(
    consumer,
    @execution.bind_completed_input(consumer, 0, root, completed_source).unwrap(),
    10000,
    20000,
  ).unwrap()
  let local_read = @execution.prepare_producer_read(
    consumer,
    @query.bind_captured_source_operation(captures[1], consumer, 0, 1).unwrap(),
    10000,
    20000,
  ).unwrap()
  mixed_whole_infer_execute(prefix, [imported, local_read])
}

///|
fn mixed_whole_infer_receipt(
  output : @execution.CompletedOutput,
) -> @execution.CompletedRelationExportReceipt {
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 20,
    max_work: 1000000,
  }
  let workspace = @execution.completed_relation_identity_scan_workspace_slots(
    output, values, wire, wire,
  ).unwrap()
  let scan = @execution.start_completed_relation_identity_scan(
    output,
    10,
    values,
    wire,
    wire,
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    20000,
    workspace,
  ).unwrap()
  for _ in 0..<10000 {
    if @execution.advance_completed_relation_identity_scan(scan, 31).unwrap().0 {
      return @execution.finish_completed_relation_identity_scan(scan).unwrap()
    }
  }
  abort("bounded original prefix identity")
}

///|
test "mixed Whole Model transformed completion refuses equal foreign completion receipt and coordinate" {
  let prepared = mixed_whole_infer_test_program()
  let models = prepared_client_composed_infer_occurrences(prepared).unwrap()
  let left = mixed_whole_infer_capture(prepared, 0, Ref(true))
  let right = mixed_whole_infer_capture(prepared, 1, Ref(true))
  let sources = admit_client_infer_composed_whole_sources(
    models[0],
    [left.0, right.0],
    [left.1, right.1],
    [left.2, right.2],
    [left.3, right.3],
    [left.4, right.4],
    "sha256:" + "a".repeat(64),
    "2026-11-12T00:00:00.000Z",
    "2026-11-12T00:00:02.000Z",
  ).unwrap()
  let output = mixed_whole_infer_completed_prefix(prepared, [left.0, right.0])
  let mut amount = -1
  for index in 0..<@execution.completed_column_count(output) {
    if @execution.completed_column_name(output, index) == Some("amount") {
      amount = index
    }
  }
  assert_true(amount >= 0)
  assert_true(@execution.completed_cell(output, 0, amount) is Some(Number(8.0)))
  let receipt = mixed_whole_infer_receipt(output)
  let graph = issue_prepared_client_composed_infer_plan_graph(
    models[0],
    client_infer_graph_test_execution(prepared, occurrence=Some(models[0])),
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
    include_results=false,
  ).unwrap()
  assert_true(
    issue_client_infer_occurrence_call_scope(
      models[0],
      graph,
      output,
      receipt,
      100000,
      10000,
      100,
      sources=Some(sources),
    )
    is Ok(_),
  )
  let foreign = mixed_whole_infer_test_program()
  let other_left = mixed_whole_infer_capture(foreign, 0, Ref(true))
  let other_right = mixed_whole_infer_capture(foreign, 1, Ref(true))
  let other_output = mixed_whole_infer_completed_prefix(foreign, [
    other_left.0,
    other_right.0,
  ])
  let other_receipt = mixed_whole_infer_receipt(other_output)
  assert_true(
    @execution.completed_cell(other_output, 0, amount) is Some(Number(8.0)),
  )
  assert_true(
    issue_client_infer_occurrence_call_scope(
      models[0],
      graph,
      other_output,
      other_receipt,
      100000,
      10000,
      100,
      sources=Some(sources),
    )
    is Err(ForeignInput),
  )
  assert_true(
    issue_client_infer_occurrence_call_scope(
      models[0],
      graph,
      output,
      other_receipt,
      100000,
      10000,
      100,
      sources=Some(sources),
    )
    is Err(ForeignInput),
  )
  let changed = { ..models[0], task: 0, }
  assert_false(client_infer_composed_sources_matches(sources, changed))
  assert_true(
    admit_client_infer_composed_whole_sources(
      changed,
      [left.0, right.0],
      [left.1, right.1],
      [left.2, right.2],
      [left.3, right.3],
      [left.4, right.4],
      "sha256:" + "a".repeat(64),
      "2026-11-12T00:00:00.000Z",
      "2026-11-12T00:00:02.000Z",
    )
    is Err(ForeignInput),
  )
}
