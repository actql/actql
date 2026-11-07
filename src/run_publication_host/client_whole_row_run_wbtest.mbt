///|
fn whole_row_declaration() -> @row_host.RowDeclaration {
  @row_host.generate_relation_row_declaration(
    "fixture",
    "rest",
    "rest/0.1",
    [
      {
        resource: "records",
        resource_kind: "table",
        schema_wire: "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
        schema_cid: "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513",
        request_schema_wire: Some(
          "{\"additional_properties\":false,\"fields\":{\"selector\":{\"nullable\":false,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"}",
        ),
        facts_wire: Some("{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"),
        acquisition_wire: None,
      },
    ],
    {
      max_bytes: 200000,
      max_nodes: 20000,
      max_depth: 32,
      max_views: 1,
      max_fields: 1,
    },
  ).unwrap()
}

///|
fn whole_row_environment(
  declaration : @row_host.RowDeclaration,
) -> @checked.CheckEnvironment raise {
  fn sorted(bodies : Array[String]) -> String {
    let bodies = bodies.copy()
    bodies.sort_by((a, b) => {
      @sha.hex(@utf8.encode(a)).compare(@sha.hex(@utf8.encode(b)))
    })
    "[" + bodies.join(",") + "]"
  }
  let (schemas, capabilities) = @row_host.row_declaration_evidence_members(
    declaration,
  )
  let head = "{\"command_contracts\":[],\"connector_capabilities\":" +
    sorted(capabilities) +
    ",\"connector_catalogs\":[" +
    declaration.catalog +
    "],\"connector_manifest\":{\"connectors\":[" +
    declaration.manifest_entry +
    "],\"version\":\"actql-connectors/0.1\"},\"contract_registry\":" +
    sorted(declaration.contracts)
  let tail = ",\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":1000,\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"}},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":" +
    sorted(schemas) +
    ",\"source_views\":" +
    sorted(declaration.view_bodies) +
    ",\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(head + tail))
  admit_client_check_environment(
    head + ",\"evidence_bundle_cid\":\"" + cid + "\"" + tail,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn whole_row_selection(
  input_limits? : @row_host.RowInputLimits? = None,
) -> (
  PreparedClientProgram,
  @acquisition.SourceAcquisition,
  @row_host.RowInputAcquisition,
) raise {
  let declaration = whole_row_declaration()
  let (_, _, limits) = client_composed_effect_base_fixture()
  let prepared = prepare_effect_free_client_program(
    (
      #|{"version":"actql/0.1","id":"whole-input","params":{"selection":{"type":"string","nullable":false}},"stages":[{"id":"read","inputs":{"remote":{"connector":"fixture","resource":"records","request":{"selector":{"$param":"selection"}}}},"steps":[{"select":["id"],"as":"selected"},{"sort":[{"id":"asc"}],"as":"sorted"}],"results":{"out":{"from":"sorted","fields":["id"]}}}],"results":{"out":{"from":{"stage":"read","result":"out"}}}}
    ),
    Json,
    whole_row_environment(declaration),
    Some(scalar_profile_cursor("{\"selection\":\"original\"}")),
    limits.program,
  ).unwrap()
  let acquisition = prepare_client_source_acquisition(prepared, 0, 0).unwrap()
  let sequence = @lower.prepare_sequence(
    @strategy.graph_task_owner(prepared.graph, 0).unwrap(),
    run_materials_limits().sequence,
  ).unwrap()
  let selected = @row_host.prepare_row_input_acquisition(
    acquisition,
    @checked.source_identity(@strategy.graph_program(prepared.graph)),
    sequence,
    whole_source_capture_contracts(),
    declaration,
    match input_limits {
      Some(value) => value
      None =>
        {
          max_rows: 128,
          page: {
            max_bytes: 20000,
            max_nodes: 10000,
            max_depth: 20,
            max_rows: 128,
          },
          retention: {
            max_nodes: 10000,
            max_text_bytes: 10000,
            max_depth: 20,
            max_work: 1000000,
          },
          wire: {
            max_columns: 1,
            max_order_work: 10000,
            max_bytes: 20000,
            max_nodes: 10000,
            max_depth: 20,
          },
        }
    },
  ).unwrap()
  assert_eq(
    @row_host.row_input_acquisition_request_wire(selected).unwrap(),
    "{\"selector\":\"original\"}",
  )
  (prepared, acquisition, selected)
}

///|
fn whole_row_run(
  selected : @row_host.RowInputAcquisition,
  settled : Ref[Bool],
  stopped : Ref[Bool],
) -> (@row_host.RowRun, @resources.Ledger) raise {
  let provider = @execution.execution_capacity(1024L, 2048L)
  let capacity = @row_host.row_input_acquisition_capacity(selected, provider).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(capacity) < 16777216L,
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(capacity) + 20000L < 33554432L,
  )
  let ledger = @resources.create_ledger({
    planning_work: 100,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 20000L,
    retained_bytes: 16777216L,
    execution_bytes: 33554432L,
  }).unwrap()
  let run = @row_host.start_accounted_row_input_acquisition(
    selected,
    provider,
    "whole-row",
    _ => settled.val,
    ledger,
    20000L,
    20000L,
  ).unwrap()
  @row_host.begin_row_run_with_page_limits(
    run,
    { max_bytes: 20000, max_nodes: 10000, max_depth: 20, max_rows: 128, },
    128,
  ).unwrap()
  let borrow = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => stopped.val).unwrap()
  (run, ledger)
}

///|
fn whole_row_validate(run : @row_host.RowRun) -> Bool {
  if @row_host.begin_row_capture(run) is Err(_) {
    return false
  }
  let mut previous = 0L
  for _ in 0..<100000 {
    match @row_host.advance_row_capture(run, 1) {
      Ok((done, work)) => {
        if work < previous {
          return false
        }
        previous = work
        if done {
          return true
        }
      }
      Err(_) => return false
    }
  }
  false
}

///|
test "whole Source RowRun retains 101 original input rows before Select Sort and physical close" {
  let (_, original, selected) = whole_row_selection()
  let settled = Ref(false)
  let stopped = Ref(false)
  let (run, ledger) = whole_row_run(selected, settled, stopped)
  let values = []
  for index in 0..<101 {
    values.push("{\"id\":" + (101 - index).to_string() + "}")
  }
  let body = @utf8.encode("[" + values.join(",") + "]")
  let charge = @row_host.charge_row_run_page(run, body).unwrap()
  assert_eq(
    @row_host.accept_charged_row_run_page(run, charge, body).unwrap(),
    101,
  )
  @row_host.finish_row_run(run).unwrap()
  assert_true(
    @row_host.begin_row_capture(run) is Err(Evidence(UnverifiedTransport)),
  )
  settled.val = true
  assert_true(whole_row_validate(run))
  let capture = @row_host.capture_row_run(run).unwrap()
  let source = @row_host.row_capture_source(capture).unwrap()
  assert_true(
    @query.captured_source_matches_input_acquisition(source, original),
  )
  assert_eq(@query.captured_source_row_count(source), Some(101))
  let storage = @query.captured_source_storage(source, 1, 20).unwrap()
  assert_true(
    @execution.producer_storage_cell(storage, 0, 0) is Some(Number(101.0)),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  assert_true(@row_host.close_accounted_row_run(run) is Err(_))
  assert_false(@query.captured_source_available(source))
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  stopped.val = true
  let mut closed = false
  for _ in 0..<10000 {
    if @row_host.close_accounted_row_run(run) is Ok(_) {
      closed = true
      break
    }
  }
  assert_true(closed)
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
}

///|
test "whole Source validates original input keys and retains cancelled validation until cleanup" {
  let (_, _, selected) = whole_row_selection()
  for cancel in [false, true] {
    let (run, ledger) = whole_row_run(selected, Ref(true), Ref(true))
    let body = @utf8.encode("[{\"id\":7},{\"id\":7}]")
    let charge = @row_host.charge_row_run_page(run, body).unwrap()
    @row_host.accept_charged_row_run_page(run, charge, body).unwrap() |> ignore
    @row_host.finish_row_run(run).unwrap()
    if cancel {
      @row_host.begin_row_capture(run).unwrap()
      @row_host.advance_row_capture(run, 1).unwrap() |> ignore
      @row_host.abort_row_run(run)
    } else {
      assert_false(whole_row_validate(run))
    }
    assert_true(@row_host.capture_row_run(run) is Err(_))
    let mut closed = false
    for _ in 0..<10000 {
      if @row_host.close_accounted_row_run(run) is Ok(_) {
        closed = true
        break
      }
    }
    assert_true(closed)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}

///|
test "whole Source evidence and Compute root keep original input distinct from task completion" {
  let (prepared, original, selected) = whole_row_selection()
  let (run, ledger) = whole_row_run(selected, Ref(true), Ref(true))
  let body = @utf8.encode("[{\"id\":2},{\"id\":1}]")
  let charge = @row_host.charge_row_run_page(run, body).unwrap()
  @row_host.accept_charged_row_run_page(run, charge, body).unwrap() |> ignore
  @row_host.finish_row_run(run).unwrap()
  assert_true(whole_row_validate(run))
  let capture = @row_host.capture_row_run(run).unwrap()
  let source = @row_host.row_capture_source(capture).unwrap()
  let graph = @strategy.prepare_source_input_dag(prepared.graph, original).unwrap()
  assert_eq(@strategy.graph_captured_prefix(prepared.graph), 1)
  assert_eq(@strategy.graph_captured_prefix(graph), 0)
  let dag = @strategy.open_source_input_dag(graph, source, ledger).unwrap()
  assert_false(@strategy.captured_task_completed(dag, 0))
  assert_eq(@strategy.next_captured_task(dag), Some(0))
  let wire : @execution.RowWireLimits = {
    max_columns: 1,
    max_order_work: 10000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let identity = match
    @query.identify_captured_source_relation(
      source,
      128,
      {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 20,
        max_work: 1000000,
      },
      wire,
      wire,
      { max_fields: 1, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
      20000,
    ) {
    Ok(value) => value
    Err(Export(InvalidTarget)) =>
      fail("complete original input export: invalid target")
    Err(_) => fail("complete original input export refused")
  }
  let logical = issue_captured_whole_source_input_logical(
    graph, source, identity, original,
  ).unwrap()
  let facts = @planning.source_acquisition_evidence_facts(original).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let evidence = @row_host.issue_row_input_source_evidence(
    selected,
    capture,
    identity,
    logical,
    scope,
    facts.source_data_policy_cid,
    "2026-10-30T00:00:00.000Z",
  ).unwrap()
  assert_true(
    @publication.admit_completed_source_observation_binding(
      evidence,
      logical,
      facts.source_ref,
      facts.source_contract_cid,
      scope,
      facts.source_data_policy_cid,
      32768,
      256,
      16,
    )
    is Ok(_),
  )
  @row_host.close_accounted_row_run(run).unwrap()
  assert_true(
    @row_host.issue_row_input_source_evidence(
      selected,
      capture,
      identity,
      logical,
      scope,
      facts.source_data_policy_cid,
      "2026-10-30T00:00:00.000Z",
    )
    is Err(_),
  )
}
