///|
test "HubSpot original physical metadata grow keeps old token and coheld captured quantities" {
  // Independent authored same-scale response, never retained provider state.
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
  let limits : @hubspot_catalog.PropertyLimits = {
    max_bytes: 524288,
    max_nodes: 65536,
    max_depth: 32,
    max_properties: 256,
    max_name_units: 6003,
  }
  let prepared = @hubspot_catalog.prepare_property_response_source(
    body, "/properties", "companies", limits,
  )
  let data = @hubspot_catalog.property_response_source_geometry_data(prepared)
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  // The actual Effect openRowSite selects this existing Core policy, rather
  // than the separate Source profile's lower maxSecretBytes setting.
  let secret_bytes = client_program_installed_source_reader_policy()[0]
  let physical = (bytes, geometry) => {
    let metadata = client_program_hubspot_effect_constructor_capacity(
      4,
      [bytes, 9, 524288, 65536, 32, 256, 6003],
      [],
      geometry,
    ).unwrap()
    // Only metadata physical position7 is selected. Other constructor terms
    // do not contribute here; the same composer adds receive + original secret.
    client_program_hubspot_effect_recipe_capacities(
      [
        (zero, None, None),
        (zero, None, None),
        (zero, None, None),
        (metadata, None, None),
      ],
      Some(zero),
      [
        256, 16, 4, 128, 8, 2, 64, 32, 16384, 524288, 16384, 524288, secret_bytes,
        7, 16384, 256, 64, 4,
      ],
      0L,
      16384,
      0,
      0,
    ).unwrap()[7]
  }
  let initial = physical(0, [])
  let selected = physical(body.length(), data)
  let old_r = @execution.execution_capacity_retained_bytes(initial)
  let old_e = @execution.execution_capacity_execution_bytes(initial)
  println(
    "Physical metadata oldR=\{old_r} oldE=\{old_e} newR=\{@execution.execution_capacity_retained_bytes(selected)} newE=\{@execution.execution_capacity_execution_bytes(selected)}",
  )
  assert_eq(old_r, 10692246L)
  assert_eq(old_e, 12333318L)
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 10000000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
  let held_token = @resources.reserve_attempt(ledger, 0L, 27452533L, 0L).unwrap()
  let held = @resources.retain_allocation(ledger, held_token, 27452533L).unwrap()
  let token = @resources.reserve_attempt(ledger, 0L, old_r, old_e).unwrap()
  let other = @resources.reserve_capacity(
    ledger,
    441336923L - old_r,
    499513054L - old_e,
  ).unwrap()
  @resources.consume_reserved_attempt(ledger, token).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_eq(before.held_bytes, 27452533L)
  assert_eq(before.reserved_retention_bytes, 441336923L)
  assert_eq(before.reserved_execution_bytes, 499513054L)
  // Exact actual old refusal vector: grow, not a new zero-start reservation.
  assert_true(
    @resources.grow_execution_reservation_capacity(
      ledger, token, 13553144L, 70087086L,
    )
    is Err(ExecutionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let requested_r = @execution.execution_capacity_retained_bytes(selected)
  let requested_e = @execution.execution_capacity_execution_bytes(selected)
  assert_true(
    requested_e - old_e <= 536870912L - before.reserved_execution_bytes,
  )
  @resources.grow_execution_reservation_capacity(
    ledger, token, requested_r, requested_e,
  ).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    before.reserved_execution_bytes + requested_e - old_e,
  )
  let result = @hubspot_catalog.consume_property_response_source(
    prepared, "/properties", body,
  ).unwrap()
  assert_eq(@hubspot_catalog.property_names(result).length(), 245)
  @hubspot_catalog.retire_property_response_source(prepared)
  @resources.settle_execution_reservation(ledger, token).unwrap()
  @resources.settle_capacity(ledger, other).unwrap()
  @resources.release_allocation(ledger, held).unwrap()
  @resources.settle_execution_reservation(ledger, held_token).unwrap()
}
