///|
fn managed_kintone_form_limits() -> @kintone_catalog.FormFieldLimits {
  {
    max_bytes: 8192,
    max_nodes: 1000,
    max_depth: 16,
    max_fields: 16,
    max_name_units: 512,
  }
}

///|
fn managed_kintone_page(id : String) -> Bytes {
  @utf8.encode(
    "{\"records\":[{\"$id\":{\"type\":\"__ID__\",\"value\":\"" +
    id +
    "\"},\"$revision\":{\"type\":\"__REVISION__\",\"value\":\"9\"},\"Subject\":{\"type\":\"SINGLE_LINE_TEXT\",\"value\":\"original\"},\"Tags\":{\"type\":\"MULTI_SELECT\",\"value\":[\"red\",\"東京\",\"red\"]}}],\"totalCount\":null}",
  )
}

///|
test "managed Kintone adopts exact Query original and supplies charged typed values without a second borrow" {
  let original = kintone_original_declaration()
  let prepared = kintone_read_preparation(original~)
  let acquisition = @kintone_host.record_read_acquisition(prepared)
  let adopt = fn(original) {
    @kintone_host.adopt_managed_record_query(
      original,
      acquisition,
      kintone_page_limits(),
      kintone_value_limits(),
      100,
      2,
    )
  }
  assert_true(adopt(kintone_original_declaration()) is Err(_))
  let read = adopt(original).unwrap()
  assert_true(@kintone_host.managed_record_query_matches(read, acquisition))
  let other = @kintone_host.record_read_acquisition(
    kintone_read_preparation(original~),
  )
  assert_false(@kintone_host.managed_record_query_matches(read, other))
  assert_true(@kintone_host.managed_record_page_request(read, 8192) is Err(_))
  assert_eq(
    @kintone_host.managed_record_form_request(read, 8192).unwrap(),
    "{\"app\":\"12\"}",
  )
  @kintone_host.managed_record_recheck_form(
    read,
    kintone_original_form_body(),
    managed_kintone_form_limits(),
  ).unwrap()
  let bytes = managed_kintone_page("9007199254740993")
  let ledger = @resources.create_ledger({
    planning_work: 100,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 16384L,
    retained_bytes: @row_host.row_acquisition_retained_capacity(acquisition),
    execution_bytes: @row_host.row_acquisition_execution_capacity(acquisition) +
    8192L,
  }).unwrap()
  let run = @row_host.start_accounted_row_acquisition(
    acquisition,
    "managed-original",
    _ => true,
    ledger,
    16384L,
    8192L,
  ).unwrap()
  @row_host.begin_row_run(run, 8192, 4, 4).unwrap()
  let borrow = @row_host.borrow_row_run_responses(run, acquisition).unwrap()
  let adopt_borrow = fn(declaration) {
    @kintone_host.adopt_managed_record_borrow(
      declaration,
      borrow,
      kintone_page_limits(),
      kintone_value_limits(),
      100,
      2,
    )
  }
  // An unbound cleanup duty cannot expose the retained original selection.
  assert_true(adopt_borrow(original) is Err(Host(InvalidState)))
  @row_host.bind_row_run_response_borrow_cleanup(borrow, () => true).unwrap()
  assert_true(adopt_borrow(kintone_original_declaration()) is Err(_))
  let borrowed_read = adopt_borrow(original).unwrap()
  assert_true(
    @kintone_host.managed_record_query_matches(borrowed_read, acquisition),
  )
  assert_true(
    @row_host.borrow_row_run_responses(run, acquisition) is Err(InvalidState),
  )
  @kintone_host.retire_managed_record(borrowed_read)
  // Generic-owner ordering: the caller charges once before native projection.
  let charge = @row_host.charge_row_run_page(run, bytes).unwrap()
  let rows = @kintone_host.managed_record_project_page(read, bytes).unwrap()
  assert_eq(
    @row_host.accept_charged_row_run_values(
      run,
      charge,
      @kintone_host.managed_record_columns(read),
      rows,
    ).unwrap(),
    1,
  )
  assert_false(@kintone_host.managed_record_complete(read))
  @kintone_host.managed_record_recheck_form(
    read,
    kintone_original_form_body(),
    managed_kintone_form_limits(),
  ).unwrap()
  assert_true(@kintone_host.managed_record_complete(read))
  let writer = @encode.writer(8192, 1000, 16)
  @admitted.emit_checked_wire_value(rows[0][0], writer)
  assert_eq(@encode.finish(writer), "\"9007199254740993\"")
  @kintone_host.retire_managed_record(read)
  assert_false(@kintone_host.managed_record_query_matches(read, acquisition))
  assert_true(@kintone_host.managed_record_project_page(read, bytes) is Err(_))
  kintone_assert_closed(run, ledger)
  assert_true(adopt_borrow(original) is Err(Host(InvalidState)))
}

///|
test "managed Kintone requires final Form and latches drift and duplicate seek IDs" {
  let original = kintone_original_declaration()
  let acquisition = @kintone_host.record_read_acquisition(
    kintone_read_preparation(original~),
  )
  let make = fn(per_page) {
    @kintone_host.adopt_managed_record_query(
      original,
      acquisition,
      kintone_page_limits(),
      kintone_value_limits(),
      100,
      per_page,
    ).unwrap()
  }
  let read = make(1)
  @kintone_host.managed_record_recheck_form(
    read,
    kintone_original_form_body(),
    managed_kintone_form_limits(),
  ).unwrap()
  @kintone_host.managed_record_project_page(
    read,
    managed_kintone_page("9007199254740993"),
  ).unwrap()
  |> ignore
  assert_true(@kintone_host.managed_record_page_request(read, 8192) is Err(_))
  @kintone_host.managed_record_recheck_form(
    read,
    kintone_original_form_body(),
    managed_kintone_form_limits(),
  ).unwrap()
  assert_true(
    @kintone_host.managed_record_page_request(read, 8192)
    .unwrap()
    .contains("$id > 9007199254740993"),
  )
  assert_true(
    @kintone_host.managed_record_project_page(
      read,
      managed_kintone_page("9007199254740993"),
    )
    is Err(_),
  )
  assert_true(@kintone_host.managed_record_form_request(read, 8192) is Err(_))
  let terminal = make(2)
  @kintone_host.managed_record_recheck_form(
    terminal,
    kintone_original_form_body(),
    managed_kintone_form_limits(),
  ).unwrap()
  @kintone_host.managed_record_project_page(
    terminal, b"{\"records\":[],\"totalCount\":null}",
  ).unwrap()
  |> ignore
  assert_false(@kintone_host.managed_record_complete(terminal))
  let drift = @utf8.encode(
    @utf8.decode(kintone_original_form_body()).replace(
      old="\"revision\":\"7\"",
      new="\"revision\":\"8\"",
    ),
  )
  assert_true(
    @kintone_host.managed_record_recheck_form(
      terminal,
      drift,
      managed_kintone_form_limits(),
    )
    is Err(_),
  )
  assert_false(@kintone_host.managed_record_complete(terminal))
  @kintone_host.retire_managed_record(read)
  @kintone_host.retire_managed_record(terminal)
}

///|
test "managed Kintone cumulative native response quote preserves the previous original capacity" {
  let original = kintone_original_declaration()
  let acquisition = @kintone_host.record_read_acquisition(
    kintone_read_preparation(original~),
  )
  let pages = kintone_page_limits()
  let values = kintone_value_limits()
  let read = @kintone_host.adopt_managed_record_query(
    original, acquisition, pages, values, 100, 2,
  ).unwrap()
  let initial = @kintone_host.managed_record_construction_capacity(
    original, pages, values, 100, 2, 8192,
  ).unwrap()
  let initial_bytes = @execution.execution_capacity_execution_bytes(initial)
  let form = kintone_original_form_body()
  let limits = managed_kintone_form_limits()
  assert_true(
    @kintone_host.managed_record_response_construction_capacity(
      read,
      initial,
      form.length(),
      false,
      limits,
    )
    is None,
  )
  let with_form = @kintone_host.managed_record_response_construction_capacity(
    read,
    initial,
    form.length(),
    true,
    limits,
  ).unwrap()
  let form_bytes = @execution.execution_capacity_execution_bytes(with_form)
  assert_true(form_bytes > initial_bytes)
  assert_eq(
    @execution.execution_capacity_execution_bytes(initial),
    initial_bytes,
  )
  // Quotation itself leaves the original protocol state unchanged.
  assert_true(@kintone_host.managed_record_form_request(read, 8192) is Ok(_))
  @kintone_host.managed_record_recheck_form(read, form, limits).unwrap()
  let page = managed_kintone_page("9007199254740993")
  let with_page = @kintone_host.managed_record_response_construction_capacity(
    read,
    with_form,
    page.length(),
    false,
    limits,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(with_page) > form_bytes,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(with_form),
    form_bytes,
  )
  assert_true(
    @kintone_host.managed_record_response_construction_capacity(
      read, with_page, -1, false, limits,
    )
    is None,
  )
  assert_true(
    @kintone_host.managed_record_response_construction_capacity(
      read,
      with_page,
      pages.max_bytes + 1,
      false,
      limits,
    )
    is None,
  )
  @kintone_host.retire_managed_record(read)
  assert_true(
    @kintone_host.managed_record_response_construction_capacity(
      read,
      with_page,
      page.length(),
      false,
      limits,
    )
    is None,
  )
}
