///|
test "HubSpot SAME property preflight grows real Ledger before complete projection" {
  let protocol = [
    524288, 65536, 32, 256, 6003, 2, 4, 6, 2, 256, 128, 16384, 65536, 262144, 16384,
    32,
  ]
  let reader = [
    524288, 3145728, 65536, 32, 2, 4, 6, 2, 128, 524288, 37264, 16384, 65536, 262144,
    16384, 32,
  ]
  let initial = client_program_hubspot_source_reader_observed_capacity(
    reader,
    256,
    65536,
    protocol,
    37264,
    [],
    [],
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 1000000L,
    retained_bytes: 16777216L,
    execution_bytes: 16777216L,
  }).unwrap()
  let reservation = @resources.reserve_attempt(
    ledger,
    524288L,
    @execution.execution_capacity_retained_bytes(initial),
    @execution.execution_capacity_execution_bytes(initial),
  ).unwrap()
  @resources.consume_reserved_attempt(ledger, reservation).unwrap()
  let body = @utf8.encode(
    "{\"results\":[{\"name\":\"name\",\"type\":\"string\",\"fieldType\":\"text\"}],\"unknown\":\"" +
    String::make(15000, '日') +
    "\"}",
  )
  let path = "/crm/v3/properties/companies"
  let prepared = @hubspot_catalog.prepare_property_response_source(
    body,
    path,
    "companies",
    {
      max_bytes: protocol[0],
      max_nodes: protocol[1],
      max_depth: protocol[2],
      max_properties: protocol[3],
      max_name_units: protocol[4],
    },
  )
  let data = @hubspot_catalog.property_response_source_geometry_data(prepared)
  let received = [15, body.length()]
  @resources.charge_transfer(
    ledger,
    reservation,
    15L + body.length().to_int64(),
  ).unwrap()
  let quote = client_program_hubspot_source_reader_observed_capacity(
    reader, 256, 65536, protocol, 37264, received, data,
  ).unwrap()
  let old = client_program_hubspot_source_reader_observed_capacity(
    reader,
    256,
    65536,
    protocol,
    37264,
    received,
    [],
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quote)
  let execution = @execution.execution_capacity_execution_bytes(quote)
  println(
    "HubSpot staged source bytes=\{body.length()} observed=\{retained} full=\{@execution.execution_capacity_retained_bytes(old)}",
  )
  assert_true(retained < 16777216L)
  assert_true(@execution.execution_capacity_retained_bytes(old) > 16777216L)
  @resources.grow_execution_reservation_capacity(
    ledger, reservation, retained, execution,
  ).unwrap()
  let catalog = @hubspot_catalog.consume_property_response_source(
    prepared, path, body,
  ).unwrap()
  assert_eq(@hubspot_catalog.property_names(catalog), ["name"])
  @hubspot_catalog.retire_property_response_source(prepared)
  @resources.settle_reservation(ledger, reservation).unwrap()
  let short = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 1000000L,
    retained_bytes: retained - 1L,
    execution_bytes: execution,
  }).unwrap()
  assert_true(@resources.reserve_capacity(short, retained, execution) is Err(_))
  let pending = @hubspot_catalog.prepare_property_response_source(
    body,
    path,
    "companies",
    {
      max_bytes: protocol[0],
      max_nodes: protocol[1],
      max_depth: protocol[2],
      max_properties: protocol[3],
      max_name_units: protocol[4],
    },
  )
  let original = @resources.reserve_attempt(
    short,
    524288L,
    @execution.execution_capacity_retained_bytes(initial),
    @execution.execution_capacity_execution_bytes(initial),
  ).unwrap()
  @resources.consume_reserved_attempt(short, original).unwrap()
  let before = @resources.ledger_usage(short)
  assert_true(
    @resources.grow_execution_reservation_capacity(
      short, original, retained, execution,
    )
    is Err(RetentionLimit),
  )
  assert_eq(@resources.ledger_usage(short), before)
  assert_eq(
    @hubspot_catalog.property_response_source_geometry_data(pending).length(),
    12,
  )
  @hubspot_catalog.retire_property_response_source(pending)
  assert_eq(@hubspot_catalog.property_response_source_geometry_data(pending), [])
  @resources.settle_reservation(short, original).unwrap()
  let foreign = data.copy()
  foreign[0] += 1
  assert_true(
    client_program_hubspot_source_reader_observed_capacity(
      reader, 256, 65536, protocol, 37264, received, foreign,
    )
    is None,
  )
}
