///|
fn alias_metadata_limits() -> PropertyLimits {
  {
    max_bytes: 524288,
    max_nodes: 65536,
    max_depth: 32,
    max_properties: 256,
    max_name_units: 6003,
  }
}

///|
fn alias_metadata_body() -> Bytes {
  let properties = Array::makei(245, index => {
    "{\"name\":\"field_" +
    index.to_string() +
    "\",\"type\":\"string\",\"fieldType\":\"text\",\"description\":\"" +
    String::make(1050, 'x') +
    "\",\"shape\":[" +
    Array::make(11, "{\"a\":0,\"b\":0,\"c\":0,\"d\":0,\"e\":0}").join(",") +
    "]}"
  })
  @utf8.encode("{\"results\":[" + properties.join(",") + "]}")
}

///|
test "Effect shared Catalog text retains full output and real same-token one-short execution refusal" {
  let limits = alias_metadata_limits()
  let body = alias_metadata_body()
  assert_true(body.length() > 300000 && body.length() < limits.max_bytes)
  let path = "/crm/v3/properties/companies"
  let initial = effect_metadata_construction_capacity(0, 9, limits).unwrap()
  let initial_r = @execution.execution_capacity_retained_bytes(initial)
  let initial_e = @execution.execution_capacity_execution_bytes(initial)
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 10000000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  let token = @resources.reserve_attempt(ledger, 0L, initial_r, initial_e).unwrap()
  @resources.consume_reserved_attempt(ledger, token).unwrap()
  let staged = prepare_property_response_source(body, path, "companies", limits)
  let geometry = property_response_source_geometry(staged).unwrap()
  let quote = effect_metadata_observed_construction_capacity(
    body.length(),
    9,
    limits,
    property_response_source_geometry_data(staged),
  ).unwrap()
  let full_output = @execution.preparation_representation_cost(
    property_catalog_retained_units(
      body.length(),
      9,
      limits,
      object_bound=geometry.objects,
    ),
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quote)
  let execution = @execution.execution_capacity_execution_bytes(quote)
  assert_true(retained >= full_output)
  assert_true(execution > retained)
  let pressure = @resources.reserve_capacity(ledger, 0L, 536870912L - execution).unwrap()
  let one = @resources.reserve_capacity(ledger, 0L, 1L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @resources.grow_execution_reservation_capacity(
      ledger, token, retained, execution,
    )
    is Err(ExecutionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  // Refusal does not consume the provider's original parser transfer.
  assert_true(!staged.unwrap().taken)
  @resources.settle_capacity(ledger, one).unwrap()
  @resources.grow_execution_reservation_capacity(
    ledger, token, retained, execution,
  ).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    536870912L,
  )
  let catalog = consume_property_response_source(staged, path, body).unwrap()
  recheck_property_catalog(catalog, catalog, limits.max_properties).unwrap()
  assert_eq(catalog.properties.length(), 245)
  assert_eq(catalog.response_sha256, @sha.hex(body))
  retire_property_response_source(staged)
  // The returned Catalog and all its text dependencies outlive cursor disposal.
  assert_eq(property_names(catalog)[244], "field_244")
  assert_true(
    @resources.ledger_usage(ledger).reserved_retention_bytes >= full_output,
  )
  @resources.settle_reservation(ledger, token).unwrap()
  @resources.settle_capacity(ledger, pressure).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "Effect shared Catalog text keeps independent retention refusal and complete malformed-prefix validation" {
  let limits = alias_metadata_limits()
  let body = b"{\"results\":[{\"name\":\"status\",\"type\":\"enumeration\",\"fieldType\":\"select\",\"options\":[{\"value\":\"caf\\u00e9\"},{\"value\":\"e\\u0301\"}]}],\"unknown\":01}"
  let path = "/properties"
  let initial = effect_metadata_construction_capacity(0, 9, limits).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 10000000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  let token = @resources.reserve_attempt(
    ledger,
    0L,
    @execution.execution_capacity_retained_bytes(initial),
    @execution.execution_capacity_execution_bytes(initial),
  ).unwrap()
  @resources.consume_reserved_attempt(ledger, token).unwrap()
  let staged = prepare_property_response_source(body, path, "companies", limits)
  let quote = effect_metadata_observed_construction_capacity(
    body.length(),
    9,
    limits,
    property_response_source_geometry_data(staged),
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quote)
  let execution = @execution.execution_capacity_execution_bytes(quote)
  let pressure = @resources.reserve_capacity(ledger, 536870912L - retained, 0L).unwrap()
  let one = @resources.reserve_capacity(ledger, 1L, 0L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @resources.grow_execution_reservation_capacity(
      ledger, token, retained, execution,
    )
    is Err(RetentionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(!staged.unwrap().taken)
  @resources.settle_capacity(ledger, one).unwrap()
  @resources.grow_execution_reservation_capacity(
    ledger, token, retained, execution,
  ).unwrap()
  assert_true(
    consume_property_response_source(staged, path, body) is Err(InvalidResponse),
  )
  // A failed grammar has not retired its failed token or weakened validation.
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    536870912L,
  )
  retire_property_response_source(staged)
  retire_property_response_source(staged)
  @resources.settle_reservation(ledger, token).unwrap()
  @resources.settle_capacity(ledger, pressure).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
