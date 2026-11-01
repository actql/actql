///|
test "preserving Source reader keeps the generic recipe and same retained response and request" {
  let limits = [4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]
  let request = @execution.execution_capacity(17L, 23L).unwrap()
  let normalized = installed_json_source_reader_capacity_with_request(
    limits,
    2,
    3,
    Some(request),
  ).unwrap()
  let preserving = installed_preserving_json_source_reader_capacity_with_request(
    limits,
    2,
    3,
    Some(request),
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(preserving), 3433L)
  assert_eq(@execution.execution_capacity_retained_bytes(normalized), 3433L)
  assert_eq(@execution.execution_capacity_execution_bytes(normalized), 30823L)
  assert_true(
    @execution.execution_capacity_execution_bytes(preserving) <
    @execution.execution_capacity_execution_bytes(normalized),
  )
  assert_true(
    installed_preserving_json_source_reader_capacity_with_request(
      limits,
      2,
      3,
      None,
    )
    is None,
  )
  assert_true(
    installed_preserving_json_source_reader_capacity_with_request(
      [],
      2,
      3,
      Some(request),
    )
    is None,
  )
}

///|
test "Sheets existing response bounds use sequential active key maps without NFC or policy increase" {
  // Existing Sheets implementation bounds: no production limit is reduced.
  // The authored 1024-byte physical target bounds this fixture's fixed view;
  // it is DATA, not a Ledger, grant, admitted resource or ordinary proof.
  let limits = [
    2000000, 2000000, 200000, 32, 100, 100, 1, 100, 1, 1, 1024, 1, 2000000, 12009902,
    401, 4,
  ]
  let request = @execution.execution_capacity(17L, 23L).unwrap()
  let normal = installed_json_source_reader_capacity_with_request(
    limits,
    3,
    65536,
    Some(request),
  ).unwrap()
  let preserving = installed_preserving_json_source_reader_capacity_with_request(
    limits,
    3,
    65536,
    Some(request),
  ).unwrap()
  let policy = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  let source = installed_source_response_preserving_workspace(
    limits[0],
    limits[2],
    limits[3],
  ).unwrap()
  println(
    "SHEETS_CONSTRUCTOR normalized=\{@execution.execution_capacity_execution_bytes(normal)} preserving=\{@execution.execution_capacity_execution_bytes(preserving)} source=\{@execution.preparation_representation_cost(source).unwrap()} policy=\{policy.execution_bytes}",
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(normal) >
    policy.execution_bytes,
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(preserving) <=
    policy.execution_bytes,
  )
  assert_eq(
    @execution.execution_capacity_retained_bytes(preserving),
    @execution.execution_capacity_retained_bytes(normal),
  )
}
