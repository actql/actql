///|
// Real checked Whole input and serialization components. Source observations
// are synthetic DATA; physical provider, publication and close acceptance are
// separately exercised by the ordinary Host consumer.
fn serialization_whole_capture_document(effect : Bool) -> String {
  let capture =
    #|{"id":"capture","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}}
  let content =
    #|{"id":"content","inputs":{"rows":{"result":{"stage":"capture","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"serialize":{"format":"jsonl","fields":["id","amount"],"order_by":[{"id":"asc"}],"name":"out.jsonl","bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"}],"results":{"file":{"from":"attachment","fields":["name","content"]}}}
  let apply =
    #|{"id":"apply","inputs":{"attachment":{"result":{"stage":"content","result":"file"}}},"steps":[{"derive":{"value":{"literal":1}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}
  "{\"version\":\"actql/0.1\",\"id\":\"whole-content\",\"stages\":[" +
  capture +
  "," +
  content +
  (if effect { "," + apply } else { "" }) +
  "],\"results\":{\"file\":{\"from\":{\"stage\":\"content\",\"result\":\"file\"}}}}"
}

///|
fn serialization_whole_effect_run() -> (
  PreparedClientEffectComputation,
  ClientCompiledRun,
) raise {
  let (_, _, limits) = client_composed_effect_base_fixture()
  let base = admit_client_check_environment(
    local_normalization_environment_wire,
    "sha256:afebeb63f2e0e48434bf005f65ab0af8a0c2704f0afb5a8c70df72e91b26e86e",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let owner = prepare_client_effect_computation(
    serialization_whole_capture_document(true),
    Json,
    client_composed_effect_test_environment(base),
    None,
    [],
    { ..limits, program: client_standard_program_preparation_limits(), },
  ).unwrap()
  let compilation = issue_prepared_client_effect_compilation(
    owner,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  (owner, client_effect_allowed_serialization_run(allowed).unwrap())
}

///|
test "Whole serialization retains the original direct Source without a Query requirement" {
  let owner = multi_source_prepared(serialization_whole_capture_document(false))
  let component = issue_prepared_client_acquired_serialization_plan_graph(
    owner,
    1,
    1,
    2,
    128,
    10000,
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  let captured = mixed_whole_infer_capture(owner, 0, Ref(true))
  let admitted = admit_client_serialization_whole_captured_input(
    owner,
    component,
    captured.0,
    captured.1,
    captured.2,
    captured.3,
    captured.4,
    "sha256:" + "a".repeat(64),
    "2026-11-12T00:00:00.000Z",
    "2026-11-12T00:00:02.000Z",
  ).unwrap()
  assert_true(physical_equal(admitted.owner, owner))
  assert_true(physical_equal(admitted.source, captured.0))
  assert_true(physical_equal(admitted.identity, captured.1))
  assert_eq((admitted.task, admitted.step), (1, 1))
  assert_eq(admitted.named_sources.length(), 1)
  assert_eq(admitted.named_sources[0].0, "remote")
  assert_true(admitted.keyed is None)
}

///|
test "Whole Effect serialization uses the retained original compiled component" {
  let (owner, run) = serialization_whole_effect_run()
  let live = Ref(true)
  let captured = mixed_whole_infer_capture(run.owner, 0, live)
  let admitted = admit_client_effect_serialization_whole_captured_input(
    run,
    owner,
    captured.0,
    captured.1,
    captured.2,
    captured.3,
    captured.4,
    "sha256:" + "a".repeat(64),
    "2026-11-12T00:00:00.000Z",
    "2026-11-12T00:00:02.000Z",
  ).unwrap()
  assert_true(physical_equal(admitted.owner, run.owner))
  assert_true(physical_equal(admitted.source, captured.0))
  assert_true(physical_equal(admitted.identity, captured.1))
  assert_eq(admitted.named_sources[0].0, "remote")
  assert_eq(admitted.named_sources.length(), 1)
  assert_true(admitted.keyed is None)
  live.val = false
  assert_true(
    admit_client_effect_serialization_whole_captured_input(
      run,
      owner,
      captured.0,
      captured.1,
      captured.2,
      captured.3,
      captured.4,
      "sha256:" + "a".repeat(64),
      "2026-11-12T00:00:00.000Z",
      "2026-11-12T00:00:02.000Z",
    )
    is Err(
      @publication.RunEvidenceReferenceMismatch("content_whole_source_owner")
    ),
  )
}

///|
test "Whole serialization refuses foreign owner capacity identity and observation" {
  let (owner, run) = serialization_whole_effect_run()
  let (foreign_owner, foreign_run) = serialization_whole_effect_run()
  let captured = mixed_whole_infer_capture(run.owner, 0, Ref(true))
  let foreign = mixed_whole_infer_capture(foreign_run.owner, 0, Ref(true))
  assert_true(
    admit_client_effect_serialization_whole_captured_input(
      run,
      foreign_owner,
      captured.0,
      captured.1,
      captured.2,
      captured.3,
      captured.4,
      "sha256:" + "a".repeat(64),
      "2026-11-12T00:00:00.000Z",
      "2026-11-12T00:00:02.000Z",
    )
    is Err(@publication.RunEvidenceReferenceMismatch("content_effect_owner")),
  )
  for
    (source, identity, capacity) in [
      (captured.0, captured.1, foreign.2),
      (foreign.0, captured.1, captured.2),
      (captured.0, foreign.1, captured.2),
    ] {
    assert_true(
      admit_client_effect_serialization_whole_captured_input(
        run,
        owner,
        source,
        identity,
        capacity,
        captured.3,
        captured.4,
        "sha256:" + "a".repeat(64),
        "2026-11-12T00:00:00.000Z",
        "2026-11-12T00:00:02.000Z",
      )
      is Err(
        @publication.RunEvidenceReferenceMismatch("content_whole_source_owner")
      ),
    )
  }
  assert_true(
    admit_client_effect_serialization_whole_captured_input(
      run,
      owner,
      captured.0,
      captured.1,
      captured.2,
      captured.3,
      captured.4,
      "sha256:" + "c".repeat(64),
      "2026-11-12T00:00:00.000Z",
      "2026-11-12T00:00:02.000Z",
    )
    is Err(_),
  )
  assert_true(
    admit_client_effect_serialization_whole_captured_input(
      run,
      owner,
      captured.0,
      captured.1,
      captured.2,
      captured.4,
      captured.3,
      "sha256:" + "a".repeat(64),
      "2026-11-12T00:00:00.000Z",
      "2026-11-12T00:00:02.000Z",
    )
    is Err(@publication.RunEvidenceReferenceMismatch("content_source_input")),
  )
}

///|
test "Query serialization still retains its genuine Query capture and cannot become Whole" {
  let owner = multi_source_prepared(
    serialization_whole_capture_document(false).replace(
      old="\"steps\":[{\"select\":[\"id\",\"amount\"]",
      new="\"steps\":[{\"filter\":\"id >= 0\"},{\"select\":[\"id\",\"amount\"]",
    ),
  )
  let component = issue_prepared_client_acquired_serialization_plan_graph(
    owner,
    1,
    1,
    2,
    128,
    10000,
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  let captured = pure_three_source_capture(owner, 0, Ref(true))
  let admitted = admit_client_serialization_captured_input(
    owner,
    component,
    captured.0,
    captured.1,
    captured.2,
    captured.4,
    captured.3,
    "sha256:" + "a".repeat(64),
    "2026-11-11T00:00:00.000Z",
    "2026-11-11T00:00:02.000Z",
  ).unwrap()
  assert_true(physical_equal(admitted.source, captured.0))
  assert_eq(admitted.named_sources[0].0, "remote")
  assert_true(
    admit_client_serialization_whole_captured_input(
      owner,
      component,
      captured.0,
      captured.1,
      prepare_client_source_acquisition(owner, 0, 0).unwrap(),
      captured.4,
      captured.3,
      "sha256:" + "a".repeat(64),
      "2026-11-11T00:00:00.000Z",
      "2026-11-11T00:00:02.000Z",
    )
    is Err(
      @publication.RunEvidenceReferenceMismatch("content_whole_source_owner")
    ),
  )
}

///|
fn check_plural_serialization_originals(cross_stage : Bool) -> Unit raise {
  let declaration = @row_host.generate_relation_row_declaration(
    "fixture",
    "rest",
    "rest/0.1",
    ["records", "other_records"].map(resource => {
      resource,
      resource_kind: "table",
      schema_wire: "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
      schema_cid: "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513",
      request_schema_wire: None,
      facts_wire: Some("{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"),
      acquisition_wire: None,
    }),
    {
      max_bytes: 200000,
      max_nodes: 20000,
      max_depth: 32,
      max_views: 2,
      max_fields: 1,
    },
  ).unwrap()
  let stages = if cross_stage {
    (
      #|{"id":"read_left","inputs":{"remote":{"connector":"fixture","resource":"records"}},"steps":[{"select":["id"],"as":"rows"}],"results":{"rows":{"from":"rows","fields":["id"]}}},
      #|{"id":"read_right","inputs":{"remote":{"connector":"fixture","resource":"other_records"}},"steps":[{"select":["id"],"as":"rows"}],"results":{"rows":{"from":"rows","fields":["id"]}}},
    )
  } else {
    ""
  }
  let input = if cross_stage {
    (
      #|{"left_rows":{"result":{"stage":"read_left","result":"rows"}},"right_rows":{"result":{"stage":"read_right","result":"rows"}}}
    )
  } else {
    (
      #|{"left_rows":{"connector":"fixture","resource":"records"},"right_rows":{"connector":"fixture","resource":"other_records"}}
    )
  }
  let joined =
    #|{"id":"joined","inputs":INPUT,"steps":[{"from":"left_rows","join":{"with":"right_rows","kind":"inner","max_output_rows":10,"on":[{"left":"id","right":"id"}],"select":{"id":"left.id","right_id":"right.id"}}},{"as":"unique","assert_rows":{"unique_by":["id","right_id"]}},{"as":"attachment","serialize":{"format":"jsonl","fields":["id","right_id"],"name":"joined.jsonl","order_by":[{"id":"asc"},{"right_id":"asc"}],"bounds":{"max_rows":10,"max_bytes":512}}}],"results":{"file":{"from":"attachment","fields":["name","content","media_type","size_bytes","row_count"]}}}
  let document = "{\"version\":\"actql/0.1\",\"id\":\"whole-join-content\",\"stages\":[" +
    stages +
    joined.replace(old="INPUT", new=input) +
    "],\"results\":{\"file\":{\"from\":{\"stage\":\"joined\",\"result\":\"file\"}}}}"
  let owner = prepare_effect_free_client_program(
    document,
    Json,
    whole_row_environment(declaration),
    None,
    client_standard_program_preparation_limits(),
  ).unwrap()
  let stage = if cross_stage { 2 } else { 0 }
  let task = @strategy.graph_stage_operation_task(owner.graph, stage, 2).unwrap()
  let component = match
    issue_prepared_client_acquired_serialization_plan_component(
      owner,
      task,
      2,
      10,
      512,
      10000,
      run_materials_limits().sequence,
      1000000,
      100000,
      100,
    ) {
    Ok(value) => value
    Err(InvalidLimits) => fail("component InvalidLimits")
    Err(UnsupportedGraph) => fail("component UnsupportedGraph")
    Err(UnsupportedOrder) => fail("component UnsupportedOrder")
    Err(Policy(_)) => fail("component Policy")
    Err(PolicyClosure(_)) => fail("component PolicyClosure")
    Err(SourcePolicy(_)) => fail("component SourcePolicy")
    Err(Preparation(_)) => fail("component Preparation")
    Err(Input(_)) => fail("component Input")
    Err(Root(_)) => fail("component Root")
    Err(Encoding) => fail("component Encoding")
  }
  let occurrences = client_serialization_plan_direct_occurrences(
    component, owner,
  ).unwrap()
  assert_eq(client_direct_acquisition_occurrence_count(occurrences), 2)
  let storage_limits : @resources.LedgerLimits = {
    planning_work: 100000,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 40000L,
    retained_bytes: 33554432L,
    execution_bytes: 67108864L,
  }
  let ledger = @resources.create_ledger(storage_limits).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 1L, 1L).unwrap()
  @resources.begin_original_ledger_inventory(ledger, bootstrap, 20, 2, 0).unwrap()
  |> ignore
  let wire : @execution.RowWireLimits = {
    max_columns: 1,
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
  let pages : @row_host.RowInputLimits = {
    max_rows: 128,
    page: { max_bytes: 20000, max_nodes: 10000, max_depth: 20, max_rows: 128, },
    retention: values,
    wire,
  }
  let scope = "sha256:" + "a".repeat(64)
  let inputs : Array[ClientSerializationWholeCapture] = []
  let runs : Array[@row_host.RowRun] = []
  for index in 0..<2 {
    let (stage, input, source_task) = client_direct_acquisition_occurrence_at(
      occurrences, index,
    ).unwrap()
    let original = prepare_client_source_acquisition(owner, stage, input).unwrap()
    let sequence = @lower.prepare_sequence_prefix(
      @strategy.graph_task_owner(owner.graph, source_task).unwrap(),
      0,
      run_materials_limits().sequence,
    ).unwrap()
    let selected = @row_host.prepare_row_input_acquisition(
      original,
      @checked.source_identity(@strategy.graph_program(owner.graph)),
      sequence,
      whole_source_capture_contracts(),
      declaration,
      pages,
    ).unwrap()
    let run = @row_host.start_accounted_row_input_acquisition(
      selected,
      @execution.execution_capacity(1024L, 2048L),
      "joined-" + index.to_string(),
      _ => true,
      ledger,
      20000L,
      20000L,
    ).unwrap()
    @row_host.begin_row_run_with_page_limits(run, pages.page, 128).unwrap()
    let borrow = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
    @row_host.bind_row_run_response_borrow_cleanup(borrow, () => true).unwrap()
    let body = @utf8.encode("[{\"id\":" + index.to_string() + "}]")
    let charge = @row_host.charge_row_run_page(run, body).unwrap()
    @row_host.accept_charged_row_run_page(run, charge, body).unwrap() |> ignore
    @row_host.finish_row_run(run).unwrap()
    assert_true(whole_row_validate(run))
    let capture = @row_host.capture_row_run(run).unwrap()
    let source = @row_host.row_capture_source(capture).unwrap()
    let identity = @query.identify_captured_source_relation(
      source,
      128,
      values,
      wire,
      wire,
      { max_fields: 1, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
      20000,
    ).unwrap()
    let logical = issue_captured_whole_source_input_logical(
      owner.graph,
      source,
      identity,
      original,
      task=source_task,
    ).unwrap()
    let started_at = "2026-10-30T00:00:00.000Z"
    let completed_at = "2026-10-30T00:00:01.000Z"
    let facts = @planning.source_acquisition_evidence_facts(original).unwrap()
    let source_evidence = @row_host.issue_row_input_source_evidence(
      selected,
      capture,
      identity,
      logical,
      scope,
      facts.source_data_policy_cid,
      completed_at,
    ).unwrap()
    inputs.push({
      capture,
      identity,
      logical,
      source_evidence,
      started_at,
      completed_at,
    })
    runs.push(run)
  }
  let admitted = admit_client_serialization_whole_captured_inputs(
    owner, component, ledger, inputs, scope, 10000,
  ).unwrap()
  assert_eq(
    admitted.named_sources.map(item => item.0),
    if cross_stage {
      ["remote", "remote"]
    } else {
      ["left_rows", "right_rows"]
    },
  )
  assert_true(client_serialization_whole_captures_live(admitted))
  for
    invalid in [[], [inputs[0]], [inputs[1], inputs[0]], [inputs[0], inputs[0]]] {
    assert_true(
      admit_client_serialization_whole_captured_inputs(
        owner, component, ledger, invalid, scope, 10000,
      )
      is Err(
        @publication.RunEvidenceReferenceMismatch("content_whole_source_owner")
      ),
    )
  }
  let foreign_ledger = @resources.create_ledger(storage_limits).unwrap()
  assert_true(
    admit_client_serialization_whole_captured_inputs(
      owner, component, foreign_ledger, inputs, scope, 10000,
    )
    is Err(
      @publication.RunEvidenceReferenceMismatch("content_whole_source_owner")
    ),
  )
  @row_host.close_accounted_row_run(runs[1]).unwrap()
  assert_false(client_serialization_whole_captures_live(admitted))
  @row_host.close_accounted_row_run(runs[0]).unwrap()
}

///|
test "plural SERIALIZE requires both ordered live Whole originals on one Ledger" {
  check_plural_serialization_originals(false)
}

///|
test "cross-stage SERIALIZE binds Whole originals even when their local names match" {
  check_plural_serialization_originals(true)
}
