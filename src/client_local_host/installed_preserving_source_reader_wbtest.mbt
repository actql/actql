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
  // Keep the normalizing recipe's original complete execution envelope. Its
  // Unicode construction is owned by the pinned canonical Owner, not another
  // numeric NFC expansion expectation in this request-composition test.
  let generic = installed_json_source_reader_capacity(limits, 2, 3).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(normalized),
    @execution.execution_capacity_execution_bytes(generic) + 23L,
  )
  let reader = installed_json_source_reader_capacity_with_decoder(
    limits,
    2,
    3,
    installed_source_response_preserving_workspace,
    sequential_preserving=true,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(preserving),
    Int64::max(
      @execution.execution_capacity_execution_bytes(reader) + 17L,
      @execution.execution_capacity_retained_bytes(reader) + 23L,
    ),
  )
  let large_request = @execution.execution_capacity(
    17L,
    2L * @execution.execution_capacity_execution_bytes(reader),
  ).unwrap()
  let request_first = installed_preserving_json_source_reader_capacity_with_request(
    limits,
    2,
    3,
    Some(large_request),
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(request_first),
    @execution.execution_capacity_execution_bytes(large_request) +
    @execution.execution_capacity_retained_bytes(reader),
  )
  assert_eq(@execution.execution_capacity_retained_bytes(request_first), 3433L)
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

///|
test "mutually exclusive container populations leave the actual captured task its unchanged execution allowance" {
  let before = 450421431L
  let before_reserved = 495727552L
  let actual_task = 46987648L
  let unchanged_policy = 536870912L
  // Original7132 normal failure observed these values at the SAME failed
  // reserve comparison. They are a regression fixture, not a new allowance,
  // measured current heap, generalized task bound or ordinary success proof.
  let limits = [
    2000000, 2000000, 200000, 32, 100, 100, 1, 100, 1, 1, 1024, 1, 2000000, 12009902,
    401, 4,
  ]
  let request = @execution.execution_capacity(17L, 23L).unwrap()
  let after = installed_preserving_json_source_reader_capacity_with_request(
      limits,
      3,
      65536,
      Some(request),
    ).unwrap()
    |> @execution.execution_capacity_execution_bytes
  assert_true(before_reserved + actual_task > unchanged_policy)
  assert_true(
    before_reserved - (before - after) + actual_task <= unchanged_policy,
  )
}
