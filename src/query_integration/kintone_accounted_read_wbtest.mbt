///|
fn kintone_value_limits() -> @kintone_catalog.RecordValueLimits {
  {
    max_columns: 8,
    max_name_bytes: 128,
    max_nodes: 1000,
    max_depth: 16,
    max_text_bytes: 8192,
  }
}

///|
fn kintone_page_limits() -> @kintone_catalog.RecordPageLimits {
  {
    max_bytes: 8192,
    max_nodes: 1000,
    max_depth: 16,
    max_rows: 4,
    max_columns: 8,
    max_cells: 64,
    max_table_rows: 16,
  }
}

///|
fn kintone_original_form() -> @kintone_catalog.FormFieldCatalog {
  @kintone_catalog.project_form_fields(
    @utf8.encode(
      (
        #|{"revision":"7","properties":{"Subject":{"code":"Subject","type":"SINGLE_LINE_TEXT"},"Tags":{"code":"Tags","type":"MULTI_SELECT","options":{"red":{"label":"red","index":"0"},"東京":{"label":"東京","index":"1"}}},"Amount":{"code":"Amount","type":"NUMBER","displayScale":"2"}}}
      ),
    ),
    "12",
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_fields: 16,
      max_name_units: 512,
    },
  ).unwrap()
}

///|
fn kintone_original_declaration() -> @kintone_host.RecordDeclaration {
  @kintone_host.declare_records(
    kintone_original_form(),
    None,
    ["Subject", "Tags"],
    "kintone",
    "kintone/0.1",
    "inquiries",
    kintone_value_limits(),
    {
      max_bytes: 200000,
      max_nodes: 20000,
      max_depth: 32,
      max_views: 1,
      max_fields: 8,
    },
  ).unwrap()
}

///|
fn kintone_read_preparation(
  original? : @kintone_host.RecordDeclaration = kintone_original_declaration(),
) -> @kintone_host.PreparedRecordRead raise {
  let declaration = @kintone_host.record_declaration(original)
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
  let catalog = query_catalog_from_wire(complete, expected=cid)
  // The original Program supplies its own actual uniqueness check and order;
  // arrays are data columns, never an implicit publication ordering key.
  let checked = query_checked_program_fixture(
    catalog=Some(catalog),
    parameter_json="{}",
    program_text=Some(
      (
        #|{"version":"actql/0.1","id":"kintone-records","stages":[{"id":"a","inputs":{"remote":{"connector":"kintone","resource":"inquiries","view":"records"}},"steps":[{"filter":"Subject <> ''","as":"filtered"},{"select":["$id","Subject","Tags"],"as":"captured"},{"from":"captured","assert_rows":{"unique_by":["$id"]},"as":"unique_records"},{"from":"unique_records","sort":[{"$id":"asc"}],"as":"ordered_records"}],"results":{"r":{"from":"ordered_records","fields":["$id","Subject","Tags"]}}}],"results":{"records":{"from":{"stage":"a","result":"r"}}}}
      ),
    ),
  )
  // This existing broad RowRun port consumes the checked filter/select
  // acquisition prefix (steps 0 and 1). Keep the original later uniqueness
  // assertion and sort in the Program; they are not part of this reader's
  // residual/capture boundary and cannot run through its borrowed handle.
  let sequence = query_checked_sequence(checked, prefix_end=Some(1))
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(checked),
    { max_rows: 4, max_value_bytes: 1024, },
    query_material_limits(),
  ).unwrap()
  let (query, evidence) = query_evidence_test_bodies()
  @kintone_host.prepare_record_read(
    original,
    requirement,
    @identity.stringify_value(query, 100000, 10000, 100),
    @identity.stringify_value(evidence, 100000, 10000, 100),
  ).unwrap()
}

///|
fn kintone_host_run(
  nonce : String,
) -> (@kintone_host.PreparedRecordRead, @row_host.RowRun, @resources.Ledger) raise {
  let prepared = kintone_read_preparation()
  let acquisition = @kintone_host.record_read_acquisition(prepared)
  let ledger = @resources.create_ledger({
    planning_work: 100,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 16384L,
    retained_bytes: @row_host.row_acquisition_retained_capacity(acquisition),
    execution_bytes: @row_host.row_acquisition_execution_capacity(acquisition) +
    8192L,
  }).unwrap()
  // Controlled Common evidence observation only, not physical HTTP stop.
  let run = @row_host.start_accounted_row_acquisition(
    acquisition,
    nonce,
    _ => true,
    ledger,
    16384L,
    8192L,
  ).unwrap()
  @row_host.begin_row_run(run, 8192, 4, 4).unwrap()
  (prepared, run, ledger)
}

///|
fn kintone_borrow(
  prepared : @kintone_host.PreparedRecordRead,
  run : @row_host.RowRun,
  stopped : Ref[Bool],
  checks : Ref[Int],
) -> @kintone_host.RecordRead {
  let read = @kintone_host.borrow_record_read(
    prepared,
    run,
    kintone_page_limits(),
    kintone_value_limits(),
    100,
  ).unwrap()
  @kintone_host.bind_record_read_cleanup(read, () => {
    checks.val += 1
    stopped.val
  }).unwrap()
  read
}

///|
fn kintone_original_page() -> Bytes {
  @utf8.encode(
    (
      #|{"records":[{"$id":{"type":"__ID__","value":"2"},"$revision":{"type":"__REVISION__","value":"9"},"Subject":{"type":"SINGLE_LINE_TEXT","value":"東京\r\nnext"},"Tags":{"type":"MULTI_SELECT","value":["red","東京","red"]}},{"$id":{"type":"__ID__","value":"1"},"$revision":{"type":"__REVISION__","value":"10"},"Subject":{"type":"SINGLE_LINE_TEXT","value":"first"},"Tags":{"type":"MULTI_SELECT","value":[]}}],"totalCount":"2"}
    ),
  )
}

///|
fn kintone_assert_closed(
  run : @row_host.RowRun,
  ledger : @resources.Ledger,
) -> Unit raise {
  @row_host.close_accounted_row_run(run).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "kintone same accounted RowRun charges original bytes and captures nominal checked arrays" {
  let (prepared, run, ledger) = kintone_host_run("kintone-original-capture")
  let stopped = Ref(true)
  let checks = Ref(0)
  let read = kintone_borrow(prepared, run, stopped, checks)
  let body = kintone_original_page()
  assert_eq(@kintone_host.accept_record_read_page(read, body).unwrap(), 2)
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    body.length().to_int64(),
  )
  let page = @kintone_host.record_read_original(read).unwrap()
  assert_eq(page.response_sha256, @sha.hex(body))
  assert_eq(page.total_count, Some("2"))
  @kintone_host.retire_record_read(read).unwrap()
  assert_eq(checks.val, 1)
  assert_true(@kintone_host.record_read_original(read) is None)
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  @row_host.finish_row_run(run).unwrap()
  // The installed Host uses the existing bounded capture of the original
  // acquisition prefix. The synchronous whole-pipeline helper cannot accept
  // the Program's later assertion/sort; do not execute or discard them here.
  @row_host.begin_row_capture(run).unwrap()
  let mut complete = false
  for _ in 0..<1000 {
    let (done, _) = @row_host.advance_row_capture(run, 1).unwrap()
    if done {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_host.capture_row_run(run).unwrap()
  let input = @query.captured_source_storage(
    @row_host.row_capture_source(capture).unwrap(),
    10000,
    10000,
  ).unwrap()
  assert_eq(@execution.producer_storage_row_count(input), 2)
  // Capture preserves input order; authored sorting remains the existing
  // Common residual/publication responsibility rather than this codec's.
  assert_true(
    @execution.producer_storage_cell(input, 0, 0) is Some(@execution.Text("2")),
  )
  assert_true(
    @execution.producer_storage_cell(input, 0, 1)
    is Some(@execution.Text("東京\r\nnext")),
  )
  guard @execution.producer_storage_cell(input, 0, 2)
    is Some(@execution.Captured(tags)) else {
    fail("original array cell")
  }
  let writer = @encode.writer(4096, 100, 16)
  @admitted.emit_wire_value(tags, writer)
  assert_eq(@encode.finish(writer), "[\"red\",\"東京\",\"red\"]")
  kintone_assert_closed(run, ledger)
  assert_eq(checks.val, 1)
  assert_false(@execution.producer_storage_available(input))
}

///|
test "kintone nominal borrow refuses equal foreign acquisition duplicate and invalid limits" {
  let (prepared, run, ledger) = kintone_host_run("kintone-foreign")
  let other = kintone_read_preparation()
  assert_true(
    @kintone_host.borrow_record_read(
      other,
      run,
      kintone_page_limits(),
      kintone_value_limits(),
      100,
    )
    is Err(@kintone_host.Host(@row_host.ForeignDeclaration)),
  )
  assert_true(
    @kintone_host.borrow_record_read(
      prepared,
      run,
      { ..kintone_page_limits(), max_table_rows: 0, },
      kintone_value_limits(),
      100,
    )
    is Err(@kintone_host.InvalidLimits),
  )
  let read = @kintone_host.borrow_record_read(
    prepared,
    run,
    kintone_page_limits(),
    kintone_value_limits(),
    100,
  ).unwrap()
  assert_true(
    @kintone_host.accept_record_read_page(read, kintone_original_page())
    is Err(@kintone_host.Closed),
  )
  assert_eq(@resources.ledger_usage(ledger).transferred_bytes, 0L)
  assert_true(
    @kintone_host.borrow_record_read(
      prepared,
      run,
      kintone_page_limits(),
      kintone_value_limits(),
      100,
    )
    is Err(@kintone_host.Host(@row_host.InvalidState)),
  )
  @kintone_host.bind_record_read_cleanup(read, () => true).unwrap()
  kintone_assert_closed(run, ledger)
}

///|
test "kintone malformed charged response retains same original reservation until physical stop" {
  let (prepared, run, ledger) = kintone_host_run("kintone-malformed-pending")
  let stopped = Ref(false)
  let checks = Ref(0)
  let read = kintone_borrow(prepared, run, stopped, checks)
  let bytes = @utf8.encode("{\"records\":[{}]}")
  assert_true(
    @kintone_host.accept_record_read_page(read, bytes)
    is Err(@kintone_host.Page(_)),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    bytes.length().to_int64(),
  )
  assert_true(@row_host.finish_row_run(run) is Err(_))
  assert_true(@row_host.capture_row_run(run) is Err(_))
  assert_true(
    @kintone_host.accept_record_read_page(read, kintone_original_page())
    is Err(@kintone_host.Closed),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    bytes.length().to_int64(),
  )
  assert_true(@row_host.close_accounted_row_run(run) is Err(_))
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  stopped.val = true
  kintone_assert_closed(run, ledger)
  let after = checks.val
  kintone_assert_closed(run, ledger)
  assert_eq(checks.val, after)
}

///|
test "kintone cancellation retains original page until actual cleanup and never reopens admission" {
  let (prepared, run, ledger) = kintone_host_run("kintone-cancel")
  let stopped = Ref(false)
  let checks = Ref(0)
  let read = kintone_borrow(prepared, run, stopped, checks)
  assert_eq(
    @kintone_host.accept_record_read_page(read, kintone_original_page()).unwrap(),
    2,
  )
  let original = @kintone_host.record_read_original(read).unwrap()
  @row_host.abort_row_run(run)
  assert_true(
    @kintone_host.accept_record_read_page(read, kintone_original_page())
    is Err(_),
  )
  assert_true(
    @kintone_host.retire_record_read(read)
    is Err(@kintone_host.TransportUnsettled),
  )
  assert_true(
    physical_equal(@kintone_host.record_read_original(read).unwrap(), original),
  )
  assert_true(@row_host.close_accounted_row_run(run) is Err(_))
  assert_true(@resources.ledger_usage(ledger).reserved_retention_bytes > 0L)
  stopped.val = true
  kintone_assert_closed(run, ledger)
  assert_true(@kintone_host.record_read_original(read) is None)
  assert_true(
    @kintone_host.accept_record_read_page(read, kintone_original_page())
    is Err(@kintone_host.Closed),
  )
}

///|
test "kintone declaration cannot infer numeric history or replace a field contract" {
  assert_true(
    @kintone_host.declare_records(
      kintone_original_form(),
      None,
      ["Amount"],
      "kintone",
      "kintone/0.1",
      "inquiries",
      kintone_value_limits(),
      {
        max_bytes: 200000,
        max_nodes: 20000,
        max_depth: 32,
        max_views: 1,
        max_fields: 8,
      },
    )
    is Err(@kintone_host.Catalog(@kintone_catalog.FieldUnavailable("Amount"))),
  )
  let page = @kintone_catalog.project_record_page(
    kintone_original_page(),
    kintone_original_form(),
    ["Subject", "Tags"],
    kintone_page_limits(),
  ).unwrap()
  let text = @value_contract.primitive(
    @value_contract.StringType,
    nullable=false,
  )
  assert_true(
    @kintone_catalog.admit_record_page_contracts(
      page,
      None,
      ["Subject", "Tags"],
      [text, text],
      kintone_value_limits(),
      100,
    )
    is Err(@kintone_catalog.InvalidValue("Tags")),
  )
  assert_true(
    @kintone_catalog.admit_record_page_contracts(
      page,
      None,
      ["Subject"],
      [text],
      kintone_value_limits(),
      100,
    )
    is Err(_),
  )
  assert_true(
    @kintone_catalog.admit_record_page_contracts(
      page,
      None,
      ["Subject", "Subject"],
      [text, text],
      kintone_value_limits(),
      100,
    )
    is Err(_),
  )
}

///|
test "kintone equal independently admitted checked values cannot replace original RowRun contracts" {
  let (prepared, run, ledger) = kintone_host_run("kintone-foreign-values")
  let stopped = Ref(false)
  let checks = Ref(0)
  let read = kintone_borrow(prepared, run, stopped, checks)
  let bytes = kintone_original_page()
  let charge = @row_host.charge_row_run_page(run, bytes).unwrap()
  let native = @kintone_catalog.project_record_page(
    bytes,
    kintone_original_form(),
    ["Subject", "Tags"],
    kintone_page_limits(),
  ).unwrap()
  let equal_values = @kintone_catalog.project_checked_record_page(
    native,
    None,
    kintone_value_limits(),
  ).unwrap()
  assert_true(
    @row_host.accept_charged_row_run_values(
      run,
      charge,
      @kintone_catalog.checked_record_columns(equal_values),
      @kintone_catalog.checked_record_rows(equal_values),
    )
    is Err(@row_host.Source(@row_host.Capture(_))),
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    bytes.length().to_int64(),
  )
  assert_true(@row_host.finish_row_run(run) is Err(_))
  assert_true(@row_host.close_accounted_row_run(run) is Err(_))
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  stopped.val = true
  kintone_assert_closed(run, ledger)
  assert_true(@kintone_host.record_read_original(read) is None)
}
