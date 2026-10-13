///|
// Independent declared Source facts, not keys inferred from the supplied pages.
fn source_relation_keys_declaration() -> @row_host.RowDeclaration {
  @row_host.generate_relation_row_declaration(
    "crm/main",
    "relation-key-fixture",
    "fixture",
    [{
      resource: "r",
      resource_kind: "table",
      schema_wire: "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
      schema_cid: "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513",
      request_schema_wire: None,
      facts_wire: Some("{\"relation_keys\":{\"candidate_keys\":[[\"id\"]]}}"),
      acquisition_wire: None,
    }],
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
fn source_relation_keys_requirement(
  declaration : @row_host.RowDeclaration,
  computed_projection? : Bool = false,
) -> @planning.QueryRequirement raise {
  let (schemas, capabilities) = @row_host.row_declaration_evidence_members(
    declaration,
  )
  let (wire, original_cid) = declaration_environment(
    [declaration.catalog],
    declaration.contracts,
    declaration.view_bodies,
    [],
    host_policy="{\"capacity\":{\"max_aggregate_array_items\":10000,\"max_artifact_bytes\":10000,\"max_artifact_rows\":10000,\"max_effect_items\":10000,\"max_graph_input_edges\":10000,\"max_graph_input_nodes\":10000,\"max_graph_output_rows\":10000,\"max_graph_paths\":10000,\"max_infer_items\":10000,\"max_model_input_tokens_per_item\":10000,\"max_model_request_bytes_per_item\":10000,\"max_model_total_duration_ms\":10000,\"max_nested_value_bytes\":10000,\"max_nested_value_depth\":10000,\"max_relation_output_rows\":10000,\"max_temporal_matches_per_key\":10000,\"max_temporal_output_rows\":10000,\"version\":\"actql-capacity-host-policy/0.1\"}}",
  )
  let body = wire
    .replace(old=",\"evidence_bundle_cid\":\"" + original_cid + "\"", new="")
    .replace(
      old="\"connector_capabilities\":[]",
      new="\"connector_capabilities\":[" + capabilities.join(",") + "]",
    )
    .replace(
      old="\"schema_snapshots\":[]",
      new="\"schema_snapshots\":[" + schemas.join(",") + "]",
    )
  let cid = text_cid(body)
  let complete = body.replace(
    old="\"host_policy_profile\":",
    new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
  )
  let projected_program =
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":{"value":"id + 0"},"as":"captured"}],"results":{"r":{"from":"captured","fields":["value"]}}}],"results":{"out":{"from":{"stage":"a","result":"r"}}}}
  let checked = query_checked_program_fixture(
    catalog=Some(query_catalog_from_wire(complete, expected=cid)),
    program_text=if computed_projection { Some(projected_program) } else { None },
  )
  let sequence = query_checked_sequence(checked)
  let preparation = @lower.bound_preparation(@query.query_sequence_owner(sequence))
  // The original SourceView input and its pending key obligation survive.
  assert_true(
    @pipeline.input_contract_at(@lower.pipeline(preparation), 0)
    is Some(@pipeline.SourceViewInput(_, _, _, _)),
  )
  assert_true(@lower.preparation_input_keys(preparation, 0) is Some(_))
  @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(checked),
    { max_rows: 2, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
}

///|
fn source_relation_keys_run(
  nonce : String,
  computed_projection? : Bool = false,
) -> (@row_host.RowRun, @resources.Ledger) raise {
  let declaration = source_relation_keys_declaration()
  let requirement = source_relation_keys_requirement(declaration, computed_projection~)
  let (query, evidence) = query_evidence_test_bodies()
  let acquisition = @row_host.prepare_row_acquisition(
    declaration,
    requirement,
    @identity.stringify_value(query, 100000, 10000, 100),
    @identity.stringify_value(evidence, 100000, 10000, 100),
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 100,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 1024L,
    retained_bytes: @row_host.row_acquisition_retained_capacity(acquisition),
    execution_bytes: @row_host.row_acquisition_execution_capacity(acquisition) + 128L,
  }).unwrap()
  let run = @row_host.start_accounted_row_acquisition(
    acquisition, nonce, _ => true, ledger, 1024L, 128L,
  ).unwrap()
  @row_host.begin_row_run(run, 128, 10, 10).unwrap()
  (run, ledger)
}

///|
test "SourceView declared key validates the complete two-page acquisition before capture" {
  let (run, ledger) = source_relation_keys_run("source-key-valid")
  for page in ["[{\"id\":2}]", "[{\"id\":3}]"] {
    assert_eq(@row_host.accept_row_run_page(run, @utf8.encode(page)).unwrap(), 1)
  }
  @row_host.finish_row_run(run).unwrap()
  let capture = @row_host.capture_row_run(run).unwrap()
  let source = @row_host.row_capture_source(capture).unwrap()
  assert_eq(@query.captured_source_statistics(source).unwrap().rows, 2)
  let usage = @resources.ledger_usage(ledger)
  // Re-reading the same live capture does not acquire or charge another page.
  assert_true(@row_host.row_capture_source(capture) is Ok(_))
  assert_eq(@resources.ledger_usage(ledger), usage)
  @row_host.close_accounted_row_run(run).unwrap()
  assert_true(@query.captured_source_statistics(source) is None)
  row_page_assert_closed(run, ledger)
}

///|
test "SourceView key rejects identical duplicate pages even when the filter removes both rows" {
  for id in [2, 0] {
    let (run, ledger) = source_relation_keys_run("source-key-duplicate-" + id.to_string())
    let page = @utf8.encode("[{\"id\":" + id.to_string() + "}]")
    for _ in 0..<2 {
      assert_eq(@row_host.accept_row_run_page(run, page).unwrap(), 1)
    }
    @row_host.finish_row_run(run).unwrap()
    assert_true(
      @row_host.capture_row_run(run)
      is Err(Evidence(Attempt(Residual(Execution(Execution(InputKey(0, DuplicateKey(0, 1)))))))),
    )
    row_page_assert_closed(run, ledger)
  }
}

///|
test "computed projection cannot discard the original SourceView key validation obligation" {
  let (run, ledger) = source_relation_keys_run("source-key-projection", computed_projection=true)
  assert_eq(@row_host.accept_row_run_page(run, @utf8.encode("[{\"id\":2},{\"id\":2}]")).unwrap(), 2)
  @row_host.finish_row_run(run).unwrap()
  assert_true(
    @row_host.capture_row_run(run)
    is Err(Evidence(Attempt(Residual(Execution(Execution(InputKey(0, DuplicateKey(0, 1)))))))),
  )
  row_page_assert_closed(run, ledger)
}

///|
test "SourceView key domain rejects NULL and missing input fields before capture" {
  let (null_run, null_ledger) = source_relation_keys_run("source-key-null")
  assert_true(
    @row_host.accept_row_run_page(null_run, @utf8.encode("[{\"id\":null}]"))
    is Err(Source(Value("id"))),
  )
  row_page_assert_closed(null_run, null_ledger)
  let (missing_run, missing_ledger) = source_relation_keys_run("source-key-missing")
  assert_true(
    @row_host.accept_row_run_page(missing_run, @utf8.encode("[{}]"))
    is Err(Source(MissingField("id"))),
  )
  row_page_assert_closed(missing_run, missing_ledger)
}

///|
test "cancelling a partial SourceView acquisition cannot issue a key-validated capture" {
  let (run, ledger) = source_relation_keys_run("source-key-cancel")
  @row_host.accept_row_run_page(run, @utf8.encode("[{\"id\":2}]")).unwrap() |> ignore
  @row_host.abort_row_run(run)
  row_page_assert_closed(run, ledger)
}

///|
test "installed bounded Source capture cannot publish duplicates hidden by its filter" {
  let (run, ledger) = source_relation_keys_run("source-key-bounded-duplicate")
  for _ in 0..<2 {
    @row_host.accept_row_run_page(run, @utf8.encode("[{\"id\":0}]")).unwrap() |> ignore
  }
  @row_host.finish_row_run(run).unwrap()
  @row_host.begin_row_capture(run).unwrap()
  let mut rejected = false
  let mut previous_work = 0L
  for _ in 0..<10000 {
    match @row_host.advance_row_capture(run, 1) {
      Err(Residual(Execution(InputKey(0, DuplicateKey(0, 1))))) => {
        rejected = true
        break
      }
      Ok((done, work)) => {
        assert_true(work >= previous_work)
        previous_work = work
        if done { break }
      }
      _ => fail("unexpected bounded Source capture failure"),
    }
  }
  assert_true(rejected, msg="a filtered subset is not proof of the declared input key")
  assert_true(@row_host.capture_row_run(run) is Err(_))
  @row_host.close_row_run(run)
  let mut closed = false
  for _ in 0..<10000 {
    if @row_host.advance_row_capture_cleanup(run, 1).unwrap() {
      closed = true
      break
    }
  }
  assert_true(closed)
  row_page_assert_closed(run, ledger)
}

///|
test "bounded Source capture cancellation keeps ownership until cleanup confirms" {
  let (run, ledger) = source_relation_keys_run("source-key-bounded-cancel")
  @row_host.accept_row_run_page(run, @utf8.encode("[{\"id\":2},{\"id\":3}]")).unwrap() |> ignore
  @row_host.finish_row_run(run).unwrap()
  @row_host.begin_row_capture(run).unwrap()
  assert_true(@row_host.advance_row_capture(run, 1) is Ok((false, _)))
  let reserved = @resources.ledger_usage(ledger).reserved_execution_bytes
  assert_true(reserved > 0L)
  @row_host.abort_row_run(run)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, reserved)
  assert_true(@row_host.capture_row_run(run) is Err(InvalidState))
  @row_host.close_row_run(run)
  let mut closed = false
  for _ in 0..<10000 {
    if @row_host.advance_row_capture_cleanup(run, 1).unwrap() {
      closed = true
      break
    }
  }
  assert_true(closed)
  row_page_assert_closed(run, ledger)
}

///|
test "native filtered acquisition refuses pending SourceView key validation before provider access" {
  let requirement = source_relation_keys_requirement(source_relation_keys_declaration())
  let sequence = @planning.query_material_owner(@planning.query_requirement_material(requirement))
  assert_true(
    @duckdb.compile_native_filter_select(
      @query.query_sequence_owner(sequence), "main", "records", native_compile_limits(),
    )
    is Err(UnsupportedShape),
  )
}
