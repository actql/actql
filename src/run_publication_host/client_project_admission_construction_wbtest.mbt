///|
test "project admission inventory includes original encoded bytes and exact entry span outputs" {
  let wire = "{\"connections\":{\"a\": { \"views\": [], \"note\": \"雪😀\" },\"b\":{\"views\":[]}}}"
  let inventory = client_project_catalog_admission_construction_inventory(wire).unwrap()
  let bytes = @scalar.admit_utf8_length(wire, 65536).unwrap()
  assert_eq(inventory.owned_wire_bytes, bytes.to_int64())
  assert_true(inventory.owned_utf16_units > wire.length().to_int64())
  let admitted = admit_client_project_catalog(wire).unwrap()
  assert_eq(admitted.count(), 2)
  assert_eq(
    admitted.at(0).unwrap().1,
    "{ \"views\": [], \"note\": \"雪😀\" }",
  )
}

///|
test "project connection and catalog admission quantities remain independent constructors" {
  let wire = "{\"version\":\"actql-connectors/0.1\",\"connections\":{\"a\":{\"connector\":\"declared_file\"}}}"
  let connections = client_project_connections_admission_construction_inventory(
    wire,
  ).unwrap()
  let catalog = client_project_catalog_admission_construction_inventory(wire).unwrap()
  assert_true(connections.reference_slots > catalog.reference_slots)
  let actual = admit_client_project_connections(wire).unwrap()
  assert_eq(actual.at(0).unwrap().1, "declared_file")
  let combined = @execution.compose_preparation_representation([
    connections, catalog,
  ]).unwrap()
  assert_eq(
    combined.owned_wire_bytes,
    connections.owned_wire_bytes + catalog.owned_wire_bytes,
  )
}

///|
test "project admission quote bounds rejected input before any native parse" {
  assert_true(
    client_project_catalog_admission_construction_inventory("{\"connections\":")
    is Some(_),
  )
  assert_true(admit_client_project_catalog("{\"connections\":") is Err(_))
  assert_true(
    client_project_connections_admission_construction_inventory(
      "x".repeat(65537),
    )
    is None,
  )
  let short = client_project_catalog_admission_construction_inventory("{}").unwrap()
  let longer = client_project_catalog_admission_construction_inventory(
    "{\"connections\":{\"a\":{}}}",
  ).unwrap()
  assert_true(longer.record_headers > short.record_headers)
  assert_true(longer.owned_wire_bytes > short.owned_wire_bytes)
}
