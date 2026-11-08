///|
fn update_construction_form_body() -> Bytes {
  b"{\"revision\":\"7\",\"properties\":{\"Subject\":{\"code\":\"Subject\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\",\"required\":true},\"Tags\":{\"code\":\"Tags\",\"type\":\"MULTI_SELECT\",\"required\":false},\"Computed\":{\"code\":\"Computed\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\\\"server\\\"\"}}}"
}

///|
test "UPDATE proposal splits returned Values from shared admission and parser workspace" {
  let mapping = update_execution_mapping()
  let write = create_construction_write(16)
  let limits = create_construction_request()
  let inventory = record_update_proposal_construction_inventory(
    mapping, 8192, write, limits,
  ).unwrap()
  let capacity = record_update_proposal_construction_capacity(
    mapping, 8192, write, limits,
  ).unwrap()
  assert_true(inventory.retained.record_headers > 0L)
  assert_true(
    inventory.workspace.record_headers > inventory.retained.record_headers,
  )
  assert_true(@execution.execution_capacity_retained_bytes(capacity) > 0L)
  assert_true(
    @execution.execution_capacity_execution_bytes(capacity) >
    @execution.execution_capacity_retained_bytes(capacity),
  )
  let proposal = prepare_record_update_proposal(
    mapping,
    "9007199254740993",
    update_execution_values(),
    8192,
    write,
    limits,
  ).unwrap()
  assert_eq(record_update_proposal_identity(proposal), "9007199254740993")
  assert_eq(
    record_update_proposal_value_wire(proposal),
    "{\"Subject\":\"next 東京\",\"Tags\":[\"東京\",\"red\",\"東京\"]}",
  )
  assert_true(
    prepare_record_update_proposal(
      mapping, "9007199254740993", b"{\"Subject\":\"next\",\"Tags\":[],\"Computed\":\"unmapped\"}",
      8192, write, limits,
    )
    is Err(_),
  )
  println(
    "UPDATE proposal retained=\{@execution.execution_capacity_retained_bytes(capacity)} peak=\{@execution.execution_capacity_execution_bytes(capacity)}",
  )
}

///|
test "UPDATE Form Unit output keeps no successful parser or metadata workspace" {
  let mapping = update_execution_mapping()
  let body = update_construction_form_body()
  let limits = create_protocol_form_limits()
  let capacity = record_update_form_construction_capacity(
    mapping,
    body.length(),
    limits,
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(capacity), 0L)
  assert_true(@execution.execution_capacity_execution_bytes(capacity) > 0L)
  assert_true(
    record_update_mapping_recheck_form(mapping, body, limits) is Ok(_),
  )
  assert_true(
    record_update_mapping_recheck_form(
      mapping, b"{\"revision\":\"7\",\"properties\":{}}", limits,
    )
    is Err(_),
  )
  let tiny = record_update_form_construction_capacity(mapping, 2, limits).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(tiny) <
    @execution.execution_capacity_execution_bytes(capacity),
  )
  let widened = record_update_form_construction_capacity(
    mapping,
    body.length(),
    { ..limits, max_bytes: 2147483647, },
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(capacity),
    @execution.execution_capacity_execution_bytes(widened),
  )
}

///|
test "UPDATE target keeps complete original before and version while excluding ended parse controls" {
  let mapping = update_execution_mapping()
  let body = update_execution_target()
  let limits = create_construction_request()
  let capacity = record_update_target_construction_capacity(
    mapping,
    body.length(),
    update_execution_pages(),
    update_execution_value_limits(),
    limits,
  ).unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(capacity) > 0L)
  assert_true(
    @execution.execution_capacity_execution_bytes(capacity) >
    @execution.execution_capacity_retained_bytes(capacity),
  )
  let proposal = update_execution_proposal(mapping)
  let preview = update_execution_preview(proposal)
  assert_true(record_update_preview_matches(preview, proposal))
  assert_eq(record_update_preview_revision(preview), "9007199254740994")
  assert_true(
    record_update_preview_before_wire(preview).contains(
      "\"$id\":\"9007199254740993\"",
    ),
  )
  assert_true(
    record_update_preview_before_wire(preview).contains(
      "\"Computed\":\"server\"",
    ),
  )
  assert_true(
    prepare_record_update_preview(
      proposal,
      b"{\"records\":[],\"totalCount\":null}",
      update_execution_pages(),
      update_execution_value_limits(),
      limits,
    )
    is Err(TargetMismatch),
  )
  let quote = fn(maximum) {
    record_update_target_construction_capacity(
      mapping,
      body.length(),
      update_execution_pages(),
      update_execution_value_limits(),
      { ..limits, max_output_bytes: maximum, },
    ).unwrap()
  }
  let enough = quote(1000000)
  let wider = quote(2147483647)
  assert_eq(
    @execution.execution_capacity_execution_bytes(enough),
    @execution.execution_capacity_execution_bytes(wider),
  )
  assert_eq(
    @execution.execution_capacity_retained_bytes(enough),
    @execution.execution_capacity_retained_bytes(wider),
  )
  println(
    "UPDATE target retained=\{@execution.execution_capacity_retained_bytes(capacity)} peak=\{@execution.execution_capacity_execution_bytes(capacity)}",
  )
}

///|
test "UPDATE finalization and acknowledgement keep exact original body and correlated result" {
  let mapping = update_execution_mapping()
  let limits = create_construction_request()
  let finalization = record_update_finalization_construction_capacity(
    mapping, limits,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(finalization) >
    @execution.execution_capacity_retained_bytes(finalization),
  )
  let proposal = update_execution_proposal(mapping)
  let preview = update_execution_preview(proposal)
  let request = finalize_record_update_request(proposal, preview, limits).unwrap()
  assert_true(record_update_execution_matches(proposal, preview, request))
  assert_true(
    @catalog.record_update_request_body(request).contains(
      "\"revision\":\"9007199254740994\"",
    ),
  )
  let bytes = b"{\"records\":[{\"id\":\"9007199254740993\",\"revision\":\"9007199254740995\"}]}"
  let response = record_update_response_construction_capacity(
    mapping,
    bytes.length(),
    limits,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(response) >
    @execution.execution_capacity_retained_bytes(response),
  )
  let acknowledged = @catalog.project_record_update_acknowledgement(
    request, 200, bytes, limits,
  ).unwrap()
  let outcome = @catalog.project_record_update_effect_outcome(
    request, acknowledged, limits,
  ).unwrap()
  assert_eq(
    @catalog.record_update_effect_outcome_wire(outcome),
    "{\"result\":{\"record_id\":\"9007199254740993\",\"revision\":\"9007199254740995\"},\"state\":\"applied\"}",
  )
  assert_true(
    @catalog.record_update_effect_outcome_matches_request(outcome, request),
  )
  assert_true(
    @catalog.project_record_update_acknowledgement(
      request, 200, b"{\"records\":[{\"id\":\"other\",\"revision\":\"9\"}]}", limits,
    )
    is Err(_),
  )
  assert_true(
    @catalog.project_record_update_acknowledgement(request, 503, bytes, limits)
    is Err(_),
  )
}

///|
test "UPDATE constructor quantities refuse copied Mapping invalid limits oversized bodies and batch substitution" {
  let mapping = update_execution_mapping()
  let copied : RecordUpdateMapping = { ..mapping, }
  let write = create_construction_write(16)
  let limits = create_construction_request()
  let form = create_protocol_form_limits()
  let pages = update_execution_pages()
  let values = update_execution_value_limits()
  assert_true(
    record_update_proposal_construction_capacity(copied, 8192, write, limits)
    is None,
  )
  assert_true(
    record_update_form_construction_capacity(copied, 100, form) is None,
  )
  assert_true(
    record_update_target_construction_capacity(
      copied, 100, pages, values, limits,
    )
    is None,
  )
  assert_true(
    record_update_finalization_construction_capacity(copied, limits) is None,
  )
  assert_true(
    record_update_response_construction_capacity(copied, 100, limits) is None,
  )
  assert_true(
    record_update_proposal_construction_capacity(mapping, 0, write, limits)
    is None,
  )
  assert_true(
    record_update_form_construction_capacity(mapping, form.max_bytes + 1, form)
    is None,
  )
  assert_true(
    record_update_target_construction_capacity(
      mapping,
      pages.max_bytes + 1,
      pages,
      values,
      limits,
    )
    is None,
  )
  assert_true(
    record_update_response_construction_capacity(
      mapping,
      limits.max_output_bytes + 1,
      limits,
    )
    is None,
  )
  assert_true(
    record_update_finalization_construction_capacity(mapping, {
      ..limits,
      max_records: 2,
    })
    is None,
  )
  assert_true(
    record_update_target_construction_capacity(
      mapping,
      100,
      { ..pages, max_rows: 2, },
      values,
      limits,
    )
    is None,
  )
  assert_true(
    record_update_form_construction_capacity(mapping, 100, {
      ..form,
      max_depth: 0,
    })
    is None,
  )
  assert_true(
    record_update_response_construction_capacity(mapping, -1, limits) is None,
  )
}
