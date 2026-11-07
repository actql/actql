///|
fn whole_listing_selection(
  paths : Array[String],
  examined? : Int = 9,
) -> @row_host.RowInputAcquisition raise {
  let fields : Json = {
    "resource": {
      "type": "resource_ref",
      "resource_kind": "file",
      "nullable": false,
    },
    "name": { "type": "string", "nullable": false },
    "version": { "type": "string", "nullable": false },
    "path": { "type": "string", "nullable": true },
    "media_type": { "type": "string", "nullable": true },
    "size_bytes": { "type": "number", "nullable": true },
    "modified_at": { "type": "timestamp", "nullable": true },
  }
  let canonical = @canonical.from_json(fields, 1000, 32, 100000)
  let spec : @row_host.RowRelationViewSpec = {
    resource: "files",
    resource_kind: "file",
    schema_wire: @canonical.stringify_value(canonical, 100000, 1000, 32),
    schema_cid: @canonical.cid_value(canonical, 100000, 1000, 32),
    request_schema_wire: Some(
      (
        #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"paths":{"type":"array","nullable":true,"items":{"type":"string","nullable":false}},"glob":{"type":"string","nullable":true}}}
      ),
    ),
    facts_wire: None,
    acquisition_wire: None,
  }
  let limits : @row_host.RowDeclarationLimits = {
    max_bytes: 200000,
    max_nodes: 20000,
    max_depth: 32,
    max_views: 1,
    max_fields: 7,
  }
  let base = @row_host.generate_relation_row_declaration(
    "fixture",
    "rest",
    "rest/0.1",
    [spec],
    limits,
  ).unwrap()
  let profile : Json = {
    "file_listing": {
      "version": "actql-file-list/0.1",
      "kind": "file_listing",
      "selectable": ["paths", "glob"],
      "allow_unfiltered_listing": true,
      "admitted_scope_contract_cid": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "listing_schema_contract_cid": base.views[0].carrier_schema_cid,
      "version_capability": {
        "contract_cid": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "required_nonnull": true,
      },
      "max_listing_items": 3,
      "max_examined_items": examined,
      "max_listing_pages": 4,
      "max_request_attempts": 4,
      "max_listing_bytes": 20000,
      "max_listing_duration_ms": 100,
      "maximum_path_length": 128,
    },
  }
  let declaration = @row_host.generate_relation_row_declaration(
    "fixture",
    "rest",
    "rest/0.1",
    [{ ..spec, facts_wire: Some(profile.stringify()), }],
    limits,
  ).unwrap()
  let request : Json = { "paths": paths, "glob": null }
  let program = "{\"version\":\"actql/0.1\",\"id\":\"whole-listing\",\"stages\":[{\"id\":\"read\",\"inputs\":{\"remote\":{\"connector\":\"fixture\",\"resource\":\"files\",\"request\":" +
    request.stringify() +
    "}},\"steps\":[{\"select\":[\"name\"],\"as\":\"selected\"}],\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"name\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"read\",\"result\":\"out\"}}}}"
  let (_, _, client_limits) = client_composed_effect_base_fixture()
  let prepared = prepare_effect_free_client_program(
    program,
    Json,
    whole_row_environment(declaration),
    None,
    client_limits.program,
  ).unwrap()
  let original = prepare_client_source_acquisition(prepared, 0, 0).unwrap()
  let sequence = @lower.prepare_sequence(
    @strategy.graph_task_owner(prepared.graph, 0).unwrap(),
    run_materials_limits().sequence,
  ).unwrap()
  @row_host.prepare_row_input_acquisition(
    original,
    @checked.source_identity(@strategy.graph_program(prepared.graph)),
    sequence,
    whole_source_capture_contracts(),
    declaration,
    {
      max_rows: 3,
      page: { max_bytes: 20000, max_nodes: 1000, max_depth: 20, max_rows: 3, },
      retention: {
        max_nodes: 10000,
        max_text_bytes: 20000,
        max_depth: 20,
        max_work: 1000000,
      },
      wire: {
        max_columns: 7,
        max_order_work: 10000,
        max_bytes: 20000,
        max_nodes: 10000,
        max_depth: 20,
      },
    },
  ).unwrap()
}

///|
fn whole_listing_run(
  selected : @row_host.RowInputAcquisition,
  current : Ref[Bool],
  stopped : Ref[Bool],
) -> (@row_host.RowRun, @resources.Ledger) {
  let ledger = @resources.create_ledger({
    planning_work: 100,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 20000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  let run = @row_host.start_accounted_row_input_acquisition(
    selected,
    None,
    "whole-listing",
    _ => current.val,
    ledger,
    20000L,
    20000L,
  ).unwrap()
  let issuer = @values.bind_reference_issuer((_, _) => true, _ => current.val)
  @row_host.begin_row_run_with_page_limits(
    run,
    { max_bytes: 20000, max_nodes: 1000, max_depth: 20, max_rows: 3, },
    3,
    reference_issuer=Some(issuer),
  ).unwrap()
  let borrow = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => stopped.val).unwrap()
  (run, ledger)
}

///|
fn whole_listing_item(
  identity : String,
  path : String,
  version? : String = "v1",
) -> String {
  let cid = "sha256:" + identity.repeat(64)
  let reference : Json = {
    "$actql_ref": "resource",
    "version": "actql-resource-ref/0.1",
    "resource_kind": "file",
    "provider_namespace": "fixture",
    "provider_identity_cid": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "authority_scope_cid": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "boundary_cid": "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    "identity_cid": cid,
  }
  (
    {
      "resource": reference,
      "name": path,
      "path": path,
      "version": version,
      "media_type": null,
      "size_bytes": 3,
      "modified_at": null,
    } : Json).stringify()
}

///|
fn whole_listing_page(
  run : @row_host.RowRun,
  rows : Array[String],
  request : String?,
  next : String?,
) -> Result[Unit, @row_host.RowHostIssue] raise {
  let token = value => {
    match value {
      Some(value) => Json::string(value).stringify()
      None => "null"
    }
  }
  let body = @utf8.encode(
    "{\"items\":[" +
    rows.join(",") +
    "],\"request_token\":" +
    token(request) +
    ",\"next_token\":" +
    token(next) +
    "}",
  )
  let charge = match @row_host.charge_row_run_page(run, body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @row_host.begin_charged_row_run_listing_page(run, charge, body, 1L) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  for _ in 0..<100000 {
    match @row_host.advance_row_run_listing_page(run, 1, 1L) {
      Ok(ListingPageContinue(_)) => ()
      Ok(ListingPageComplete(_)) => return Ok(())
      Err(issue) => return Err(issue)
    }
  }
  fail("listing did not settle")
}

///|
test "whole input listing keeps original selection completeness and duplicate identity" {
  let selected = whole_listing_selection(["a.txt"])
  assert_true(@row_host.row_input_acquisition_is_listing(selected))
  let stopped = Ref(false)
  let (run, ledger) = whole_listing_run(selected, Ref(true), stopped)
  @row_host.begin_row_run_listing_request(run, None, 0L).unwrap()
  whole_listing_page(
    run,
    [whole_listing_item("e", "excluded.txt")],
    None,
    Some("p1"),
  ).unwrap()
  @row_host.begin_row_run_listing_request(run, Some("p1"), 1L).unwrap()
  whole_listing_page(
    run,
    [whole_listing_item("d", "a.txt"), whole_listing_item("d", "a.txt")],
    Some("p1"),
    None,
  ).unwrap()
  @row_host.finish_row_run(run).unwrap()
  assert_true(whole_row_validate(run))
  let capture = @row_host.capture_row_run(run).unwrap()
  let source = @row_host.row_capture_source(capture).unwrap()
  assert_eq(@query.captured_source_row_count(source), Some(1))
  assert_true(@row_host.close_accounted_row_run(run) is Err(_))
  assert_false(@query.captured_source_available(source))
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "whole input listing rejects incomplete missing conflicting and revoked observations" {
  for mode in 0..<4 {
    let selected = whole_listing_selection(["a.txt"])
    let current = Ref(true)
    let (run, ledger) = whole_listing_run(selected, current, Ref(true))
    @row_host.begin_row_run_listing_request(run, None, 0L).unwrap()
    if mode == 0 {
      whole_listing_page(run, [], None, Some("p1")).unwrap()
      assert_true(
        @row_host.finish_row_run(run) is Err(Source(ListingIncomplete)),
      )
    } else if mode == 1 {
      assert_true(
        whole_listing_page(run, [], None, None)
        is Err(Source(ListingMissingPath("a.txt"))),
      )
    } else if mode == 2 {
      assert_true(
        whole_listing_page(
          run,
          [
            whole_listing_item("d", "a.txt"),
            whole_listing_item("d", "a.txt", version="v2"),
          ],
          None,
          None,
        )
        is Err(Source(ListingConflictingResource(_))),
      )
    } else {
      current.val = false
      assert_true(
        whole_listing_page(run, [whole_listing_item("d", "a.txt")], None, None)
        is Err(_),
      )
    }
    assert_true(@row_host.capture_row_run(run) is Err(_))
    @row_host.close_accounted_row_run(run).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}

///|
test "whole input listing binds each charged page once and rejects token loops after cancel" {
  let selected = whole_listing_selection(["a.txt"])
  for reuse in [false, true] {
    let (run, ledger) = whole_listing_run(selected, Ref(true), Ref(true))
    @row_host.begin_row_run_listing_request(run, None, 0L).unwrap()
    let body = @utf8.encode(
      "{\"items\":[],\"request_token\":null,\"next_token\":\"p1\"}",
    )
    let charge = @row_host.charge_row_run_page(run, body).unwrap()
    @row_host.begin_charged_row_run_listing_page(run, charge, body, 1L).unwrap()
    assert_eq(
      @resources.ledger_usage(ledger).transferred_bytes,
      body.length().to_int64(),
    )
    if reuse {
      // Reusing a consumed ticket fails closed for the original attempt.
      assert_true(
        @row_host.begin_charged_row_run_listing_page(run, charge, body, 1L)
        is Err(_),
      )
      assert_true(@row_host.advance_row_run_listing_page(run, 1, 1L) is Err(_))
    } else {
      while @row_host.advance_row_run_listing_page(run, 1, 1L).unwrap()
            is ListingPageContinue(_) {

      }
      @row_host.begin_row_run_listing_request(run, Some("p1"), 2L).unwrap()
      assert_true(
        whole_listing_page(run, [], Some("p1"), Some("p1"))
        is Err(Source(ListingProtocol)),
      )
    }
    assert_true(@row_host.capture_row_run(run) is Err(_))
    @row_host.close_accounted_row_run(run).unwrap()
    assert_true(
      @row_host.begin_row_run_listing_request(run, Some("p1"), 3L) is Err(_),
    )
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}

///|
test "whole input listing reserves metadata before attempt and refuses either dimension one short" {
  let selected = whole_listing_selection(["a.txt"])
  let capacity = @row_host.row_input_acquisition_capacity(selected, None).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  let execution = @execution.execution_capacity_execution_bytes(capacity) +
    20000L
  for short in 0..<3 {
    let ledger = @resources.create_ledger({
      planning_work: 100,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 20000L,
      retained_bytes: retained - (if short == 1 { 1L } else { 0L }),
      execution_bytes: execution - (if short == 2 { 1L } else { 0L }),
    }).unwrap()
    let before = @resources.ledger_usage(ledger)
    let result = @row_host.start_accounted_row_input_acquisition(
      selected,
      None,
      "listing-resource-boundary",
      _ => true,
      ledger,
      20000L,
      20000L,
    )
    if short == 0 {
      let run = result.unwrap()
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        retained,
      )
      assert_eq(
        @resources.ledger_usage(ledger).reserved_execution_bytes,
        execution,
      )
      @row_host.close_accounted_row_run(run).unwrap()
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
    } else {
      assert_true(
        if short == 1 {
          result is Err(Physical(RetentionLimit))
        } else {
          result is Err(Physical(ExecutionLimit))
        },
      )
      assert_eq(@resources.ledger_usage(ledger), before)
    }
  }
}

///|
test "whole listing grows only actual page demand on the original reservation and retains refusal cleanup" {
  let selected = whole_listing_selection(["a.txt"])
  let initial = @row_host.row_input_acquisition_capacity(selected, None).unwrap()
  let r = @execution.execution_capacity_retained_bytes(initial)
  let e = @execution.execution_capacity_execution_bytes(initial) + 20000L
  // A large unchanged policy does not become initial demand. Only the
  // actually received page can request growth from this same Ledger.
  for allow_growth in [false, true] {
    let ledger = @resources.create_ledger({
      planning_work: 100,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 20000L,
      retained_bytes: if allow_growth {
        536870912L
      } else {
        r
      },
      execution_bytes: if allow_growth {
        536870912L
      } else {
        e
      },
    }).unwrap()
    let run = @row_host.start_accounted_row_input_acquisition(
      selected,
      None,
      "listing-growth",
      _ => true,
      ledger,
      20000L,
      20000L,
    ).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, r)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, e)
    let issuer = @values.bind_reference_issuer((_, _) => true, _ => true)
    @row_host.begin_row_run_with_page_limits(
      run,
      { max_bytes: 20000, max_nodes: 1000, max_depth: 20, max_rows: 3, },
      3,
      reference_issuer=Some(issuer),
    ).unwrap()
    let stopped = Ref(false)
    let borrow = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
    @row_host.bind_row_run_response_borrow_cleanup(borrow, () => stopped.val).unwrap()
    @row_host.begin_row_run_listing_request(run, None, 0L).unwrap()
    let result = whole_listing_page(
      run,
      [whole_listing_item("d", "a.txt")],
      None,
      None,
    )
    if allow_growth {
      result.unwrap()
      assert_true(@resources.ledger_usage(ledger).reserved_retention_bytes > r)
      @row_host.finish_row_run(run).unwrap()
      assert_true(whole_row_validate(run))
      assert_true(@row_host.capture_row_run(run) is Ok(_))
    } else {
      assert_true(result is Err(Physical(_)))
      assert_true(@row_host.capture_row_run(run) is Err(_))
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, r)
    }
    assert_true(@row_host.close_accounted_row_run(run) is Err(_))
    assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
    stopped.val = true
    @row_host.close_accounted_row_run(run).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}

///|
test "whole listing future examined policy is not initial reservation demand" {
  let small = whole_listing_selection(["a.txt"])
  let large = whole_listing_selection(["a.txt"], examined=1000000)
  let first = @row_host.row_input_acquisition_capacity(small, None).unwrap()
  let second = @row_host.row_input_acquisition_capacity(large, None).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(first),
    @execution.execution_capacity_retained_bytes(second),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(first),
    @execution.execution_capacity_execution_bytes(second),
  )
  let (run, ledger) = whole_listing_run(large, Ref(true), Ref(true))
  @row_host.begin_row_run_listing_request(run, None, 0L).unwrap()
  whole_listing_page(run, [whole_listing_item("d", "a.txt")], None, None).unwrap()
  @row_host.finish_row_run(run).unwrap()
  assert_true(whole_row_validate(run))
  let capture = @row_host.capture_row_run(run).unwrap()
  assert_eq(
    @query.captured_source_row_count(
      @row_host.row_capture_source(capture).unwrap(),
    ),
    Some(1),
  )
  @row_host.close_accounted_row_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
