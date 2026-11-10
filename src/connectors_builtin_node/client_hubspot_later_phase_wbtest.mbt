///|
test "HubSpot later response phase fits same-policy Ledger without dropping prefixes" {
  let protocol = [
    524288, 65536, 32, 256, 6003, 2, 4, 6, 2, 256, 128, 16384, 65536, 262144, 16384,
    32,
  ]
  let reader = [
    524288, 3145728, 65536, 32, 2, 4, 6, 2, 128, 524288, 37264, 16384, 65536, 262144,
    16384, 32,
  ]
  // Independently authored same-scale metadata. Unknown members still spend
  // the full parser/admission budgets; no real provider/state material is read.
  let properties = Array::makei(245, index => {
    "{\"name\":\"field_" +
    index.to_string() +
    "\",\"type\":\"string\",\"fieldType\":\"text\",\"description\":\"" +
    String::make(1050, 'x') +
    "\",\"shape\":[" +
    Array::make(11, "{\"a\":0,\"b\":0,\"c\":0,\"d\":0,\"e\":0}").join(",") +
    "]}"
  })
  let body = @utf8.encode("{\"results\":[" + properties.join(",") + "]}")
  assert_true(body.length() > 300000 && body.length() < protocol[0])
  let account = b"{\"portalId\":41}"
  let path = "/crm/v3/properties/companies"
  let property_limits : @hubspot_catalog.PropertyLimits = {
    max_bytes: protocol[0],
    max_nodes: protocol[1],
    max_depth: protocol[2],
    max_properties: protocol[3],
    max_name_units: protocol[4],
  }
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 10000000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  // Original observed caller base + other live reservations. This component
  // does not classify their inner owners, retire them, or claim runtime gain.
  let baseline = @resources.reserve_capacity(
    ledger,
    26408064L + 41714360L,
    41948480L + 64854808L,
  ).unwrap()
  let initial = client_program_hubspot_source_reader_observed_capacity(
    reader,
    256,
    4096,
    protocol,
    37264,
    [],
    [],
  ).unwrap()
  let reservation = @resources.reserve_attempt(
    ledger,
    1000000L,
    @execution.execution_capacity_retained_bytes(initial),
    @execution.execution_capacity_execution_bytes(initial),
  ).unwrap()
  @resources.consume_reserved_attempt(ledger, reservation).unwrap()
  let staged = @hubspot_catalog.prepare_property_response_source(
    body, path, "companies", property_limits,
  )
  let geometry = @hubspot_catalog.property_response_source_geometry_data(staged)
  assert_eq(geometry.length(), 12)
  let prefix = [account.length(), body.length()]
  let metadata = client_program_hubspot_source_reader_observed_capacity(
    reader, 256, 4096, protocol, 37264, prefix, geometry,
  ).unwrap()
  @resources.grow_execution_reservation_capacity(
    ledger,
    reservation,
    @execution.execution_capacity_retained_bytes(metadata),
    @execution.execution_capacity_execution_bytes(metadata),
  ).unwrap()
  let catalog = @hubspot_catalog.consume_property_response_source(
    staged, path, body,
  ).unwrap()
  @hubspot_catalog.recheck_property_catalog(catalog, catalog, 256).unwrap()
  let page = @utf8.encode(
    "{\"results\":[{\"id\":\"a\",\"archived\":false,\"properties\":{\"field_0\":\"one\"}}],\"unknown\":\"" +
    String::make(20000, 'x') +
    "\"}",
  )
  prefix.push(page.length())
  let quote = client_program_hubspot_source_reader_observed_capacity(
    reader, 256, 4096, protocol, 37264, prefix, geometry,
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quote)
  let execution = @execution.execution_capacity_execution_bytes(quote)
  println(
    "HubSpot later phase body=\{body.length()} page=\{page.length()} R=\{retained} E=\{execution}",
  )
  assert_true(retained > @execution.execution_capacity_retained_bytes(metadata))
  @resources.grow_execution_reservation_capacity(
    ledger, reservation, retained, execution,
  ).unwrap()
  let projected = @hubspot_catalog.project_object_page(
    page,
    catalog,
    ["field_0"],
    {
      max_bytes: protocol[0],
      max_nodes: protocol[1],
      max_depth: protocol[2],
      max_rows: protocol[8],
      max_columns: protocol[9],
      max_cursor_units: protocol[10],
      max_value_nodes: protocol[11],
      max_value_text_bytes: protocol[12],
    },
  ).unwrap()
  assert_eq(
    @hubspot_catalog.encode_object_page_rows(projected, 262144, 16384, 32).unwrap(),
    "[{\"id\":\"a\",\"field_0\":\"one\"}]",
  )
  // A later failed response is still a new charged prefix, not a refund of
  // the complete metadata or page maximum. The parser still rejects duplicate
  // normalized keys inside unknown data before any object projection succeeds.
  let malformed = @utf8.encode(
    "{\"results\":[],\"unknown\":{\"\\u00e9\":0,\"e\\u0301\":1}}",
  )
  let failed_prefix = prefix.copy()
  failed_prefix.push(malformed.length())
  let failed_quote = client_program_hubspot_source_reader_observed_capacity(
    reader, 256, 4096, protocol, 37264, failed_prefix, geometry,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(failed_quote) > execution,
  )
  assert_true(
    @hubspot_catalog.project_object_page(malformed, catalog, ["field_0"], {
      max_bytes: protocol[0],
      max_nodes: protocol[1],
      max_depth: protocol[2],
      max_rows: protocol[8],
      max_columns: protocol[9],
      max_cursor_units: protocol[10],
      max_value_nodes: protocol[11],
      max_value_text_bytes: protocol[12],
    })
    is Err(_),
  )
  let too_small = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 10000000L,
    retained_bytes: retained,
    execution_bytes: execution - 1L,
  }).unwrap()
  let before = @resources.ledger_usage(too_small)
  assert_true(
    @resources.reserve_capacity(too_small, retained, execution)
    is Err(ExecutionLimit),
  )
  assert_eq(@resources.ledger_usage(too_small), before)
  @hubspot_catalog.retire_property_response_source(staged)
  @resources.settle_reservation(ledger, reservation).unwrap()
  @resources.settle_capacity(ledger, baseline).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "HubSpot wide selection survives parser phase with one allowed cell" {
  let protocol = [
    524288, 65536, 32, 256, 6003, 2, 4, 6, 2, 256, 128, 1, 65536, 262144, 16384,
    32,
  ]
  let reader = [
    524288, 3145728, 65536, 32, 2, 4, 6, 2, 128, 524288, 37264, 1, 65536, 262144,
    16384, 32,
  ]
  let names = Array::makei(245, index => "wide_" + index.to_string())
  let metadata = @utf8.encode(
    "{\"results\":[" +
    names
    .map(name => {
      "{\"name\":\"" + name + "\",\"type\":\"string\",\"fieldType\":\"text\"}"
    })
    .join(",") +
    "]}",
  )
  let property_limits : @hubspot_catalog.PropertyLimits = {
    max_bytes: 524288,
    max_nodes: 65536,
    max_depth: 32,
    max_properties: 256,
    max_name_units: 6003,
  }
  let staged = @hubspot_catalog.prepare_property_response_source(
    metadata, "/crm/v3/properties/companies", "companies", property_limits,
  )
  let geometry = @hubspot_catalog.property_response_source_geometry_data(staged)
  let catalog = @hubspot_catalog.consume_property_response_source(
    staged, "/crm/v3/properties/companies", metadata,
  ).unwrap()
  // The one-cell limit does not bound the 245 selected tuples/contracts or
  // seen Map: they exist before parsing, including this long unknown key.
  let page = @utf8.encode(
    "{\"results\":[],\"" + String::make(400000, 'k') + "\":0}",
  )
  let prefix = [15, metadata.length(), page.length()]
  let quote = client_program_hubspot_source_reader_observed_capacity(
    reader, 256, 4096, protocol, 37264, prefix, geometry,
  ).unwrap()
  let wider = protocol.copy()
  wider[9] = 512
  let wide_quote = client_program_hubspot_source_reader_observed_capacity(
    reader, 512, 4096, wider, 37264, prefix, geometry,
  ).unwrap()
  let delta = @execution.execution_capacity_execution_bytes(wide_quote) -
    @execution.execution_capacity_execution_bytes(quote)
  // Existing sequence controls contribute twelve backing references/column.
  // Each selected string additionally owns at least Contract, Text Shape,
  // TextLimits and tuple headers before the parser; ignore their other
  // words/refs and selection Array/Map here to form an independent floor.
  let floor = @execution.preparation_representation_cost({
    record_headers: 4L * 256L,
    reference_slots: 12L * 256L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  println("HubSpot parser selection delta=\{delta} independentFloor=\{floor}")
  assert_true(delta >= floor)
  let retained = @execution.execution_capacity_retained_bytes(quote)
  let execution = @execution.execution_capacity_execution_bytes(quote)
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 10000000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  let reservation = @resources.reserve_capacity(ledger, retained, execution).unwrap()
  let projected = @hubspot_catalog.project_object_page(page, catalog, names, {
    max_bytes: 524288,
    max_nodes: 65536,
    max_depth: 32,
    max_rows: 2,
    max_columns: 256,
    max_cursor_units: 128,
    max_value_nodes: 1,
    max_value_text_bytes: 65536,
  }).unwrap()
  assert_eq(@hubspot_catalog.object_page_row_count(projected), 0)
  assert_eq(@hubspot_catalog.object_page_columns(projected), names)
  @hubspot_catalog.retire_property_response_source(staged)
  @resources.settle_capacity(ledger, reservation).unwrap()
}

///|
test "HubSpot final Properties phase fits same-policy Ledger without dropping prefixes" {
  let protocol = [
    524288, 65536, 32, 256, 6003, 2, 4, 6, 2, 256, 128, 16384, 65536, 262144, 16384,
    32,
  ]
  let reader = [
    524288, 3145728, 65536, 32, 2, 4, 6, 2, 128, 524288, 37264, 16384, 65536, 262144,
    16384, 32,
  ]
  // Independently authored same-scale metadata. Unknown members still spend
  // the full parser/admission budgets; no real provider/state material is read.
  let properties = Array::makei(245, index => {
    "{\"name\":\"field_" +
    index.to_string() +
    "\",\"type\":\"string\",\"fieldType\":\"text\",\"description\":\"" +
    String::make(1050, 'x') +
    "\",\"shape\":[" +
    Array::make(11, "{\"a\":0,\"b\":0,\"c\":0,\"d\":0,\"e\":0}").join(",") +
    "]}"
  })
  let body = @utf8.encode("{\"results\":[" + properties.join(",") + "]}")
  assert_true(body.length() > 300000 && body.length() < protocol[0])
  let account = b"{\"portalId\":41}"
  let path = "/crm/v3/properties/companies"
  let property_limits : @hubspot_catalog.PropertyLimits = {
    max_bytes: protocol[0],
    max_nodes: protocol[1],
    max_depth: protocol[2],
    max_properties: protocol[3],
    max_name_units: protocol[4],
  }
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 10000000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  // Original observed caller base + other live reservations. This component
  // does not classify their inner owners, retire them, or claim runtime gain.
  let baseline = @resources.reserve_capacity(
    ledger,
    26408064L + 41714360L,
    41948480L + 64854808L,
  ).unwrap()
  let initial = client_program_hubspot_source_reader_observed_capacity(
    reader,
    256,
    4096,
    protocol,
    37264,
    [],
    [],
  ).unwrap()
  let reservation = @resources.reserve_attempt(
    ledger,
    1000000L,
    @execution.execution_capacity_retained_bytes(initial),
    @execution.execution_capacity_execution_bytes(initial),
  ).unwrap()
  @resources.consume_reserved_attempt(ledger, reservation).unwrap()
  let staged = @hubspot_catalog.prepare_property_response_source(
    body, path, "companies", property_limits,
  )
  let geometry = @hubspot_catalog.property_response_source_geometry_data(staged)
  assert_eq(geometry.length(), 12)
  let prefix = [account.length(), body.length()]
  let metadata = client_program_hubspot_source_reader_observed_capacity(
    reader, 256, 4096, protocol, 37264, prefix, geometry,
  ).unwrap()
  @resources.grow_execution_reservation_capacity(
    ledger,
    reservation,
    @execution.execution_capacity_retained_bytes(metadata),
    @execution.execution_capacity_execution_bytes(metadata),
  ).unwrap()
  let catalog = @hubspot_catalog.consume_property_response_source(
    staged, path, body,
  ).unwrap()
  @hubspot_catalog.recheck_property_catalog(catalog, catalog, 256).unwrap()
  let page = @utf8.encode(
    "{\"results\":[{\"id\":\"a\",\"archived\":false,\"properties\":{\"field_0\":\"one\"}}],\"unknown\":\"" +
    String::make(20000, 'x') +
    "\"}",
  )
  prefix.push(page.length())
  let quote = client_program_hubspot_source_reader_observed_capacity(
    reader, 256, 4096, protocol, 37264, prefix, geometry,
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quote)
  let execution = @execution.execution_capacity_execution_bytes(quote)
  println(
    "HubSpot later phase body=\{body.length()} page=\{page.length()} R=\{retained} E=\{execution}",
  )
  assert_true(retained > @execution.execution_capacity_retained_bytes(metadata))
  @resources.grow_execution_reservation_capacity(
    ledger, reservation, retained, execution,
  ).unwrap()
  let projected = @hubspot_catalog.project_object_page(
    page,
    catalog,
    ["field_0"],
    {
      max_bytes: protocol[0],
      max_nodes: protocol[1],
      max_depth: protocol[2],
      max_rows: protocol[8],
      max_columns: protocol[9],
      max_cursor_units: protocol[10],
      max_value_nodes: protocol[11],
      max_value_text_bytes: protocol[12],
    },
  ).unwrap()
  assert_eq(
    @hubspot_catalog.encode_object_page_rows(projected, 262144, 16384, 32).unwrap(),
    "[{\"id\":\"a\",\"field_0\":\"one\"}]",
  )
  let final_body = @utf8.encode("{\"results\":[" + properties.join(",") + "]}")
  let final_prefix = prefix.copy()
  final_prefix.push(final_body.length())
  let final_quote = client_program_hubspot_source_reader_observed_capacity(
    reader, 256, 4096, protocol, 37264, final_prefix, geometry,
  ).unwrap()
  let final_retained = @execution.execution_capacity_retained_bytes(final_quote)
  let final_execution = @execution.execution_capacity_execution_bytes(
    final_quote,
  )
  println(
    "HubSpot FINAL phase body=\{final_body.length()} R=\{final_retained} E=\{final_execution}",
  )
  @resources.grow_execution_reservation_capacity(
    ledger, reservation, final_retained, final_execution,
  ).unwrap()
  let final_catalog = @hubspot_catalog.project_properties(
    final_body, "companies", property_limits,
  ).unwrap()
  @hubspot_catalog.recheck_property_catalog(catalog, final_catalog, 256).unwrap()
  // A later failed response is still a new charged prefix, not a refund of
  // the complete metadata or page maximum. The parser still rejects duplicate
  // normalized keys inside unknown data before any object projection succeeds.
  let malformed = @utf8.encode(
    "{\"results\":[],\"unknown\":{\"\\u00e9\":0,\"e\\u0301\":1}}",
  )
  let failed_prefix = final_prefix.copy()
  failed_prefix.push(malformed.length())
  let failed_quote = client_program_hubspot_source_reader_observed_capacity(
    reader, 256, 4096, protocol, 37264, failed_prefix, geometry,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(failed_quote) >
    final_execution,
  )
  assert_true(
    @hubspot_catalog.project_object_page(malformed, catalog, ["field_0"], {
      max_bytes: protocol[0],
      max_nodes: protocol[1],
      max_depth: protocol[2],
      max_rows: protocol[8],
      max_columns: protocol[9],
      max_cursor_units: protocol[10],
      max_value_nodes: protocol[11],
      max_value_text_bytes: protocol[12],
    })
    is Err(_),
  )
  let too_small = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 10000000L,
    retained_bytes: retained,
    execution_bytes: execution - 1L,
  }).unwrap()
  let before = @resources.ledger_usage(too_small)
  assert_true(
    @resources.reserve_capacity(too_small, retained, execution)
    is Err(ExecutionLimit),
  )
  assert_eq(@resources.ledger_usage(too_small), before)
  @hubspot_catalog.retire_property_response_source(staged)
  @resources.settle_reservation(ledger, reservation).unwrap()
  @resources.settle_capacity(ledger, baseline).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
