///|
test "retained inventory admits exact capacity and rejects one short" {
  // Three outputs: 3 * (10 provider + 7 export), three input ports: 3 * 5.
  assert_eq(
    client_local_store_inventory([0, 1, 2], 10L, 5L, 7L, 66L),
    Some((66L, 3L)),
  )
  assert_true(client_local_store_inventory([0, 1, 2], 10L, 5L, 7L, 65L) is None)
  assert_eq(
    client_local_store_inventory([0], 10L, 5L, 7L, 17L),
    Some((17L, 0L)),
  )
  assert_true(client_local_store_inventory([0], 10L, 5L, 7L, 16L) is None)
}

///|
test "retained inventory counts repeated producer ports without sharing" {
  assert_eq(
    client_local_store_inventory([0, 2, 1, 1], 10L, 5L, 7L, 88L),
    Some((88L, 4L)),
  )
  assert_true(
    client_local_store_inventory([0, 2, 1, 1], 10L, 5L, 7L, 87L) is None,
  )
}

///|
test "installed Store limits cover the eight task Set publication inventory" {
  let (values, _, _) = client_local_execution_limits()
  let imports = client_local_import_limits(
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    },
    values,
  )
  assert_eq(@local.local_import_retention_capacity(imports), Some(21905664L))
  assert_eq(
    @local.local_export_retention_capacity(
      client_local_export_limits(100, values),
    ),
    Some(1541184L),
  )
  // Eight outputs and eight ports (including both Set inputs), not six
  // authored producer operations alone. The 512 MiB ceiling is unchanged.
  assert_eq(
    client_local_store_inventory(
      [0, 1, 2, 1, 1, 1, 1, 1],
      14240000L,
      21905664L,
      1541184L,
      536870912L,
    ),
    Some((301494784L, 8L)),
  )
  assert_true(
    client_local_store_inventory(
      [0, 1, 2, 1, 1, 1, 1, 1],
      14240000L,
      21905664L,
      1541184L,
      301494783L,
    )
    is None,
  )
  // A larger inventory still fails before opening a Run; no limit increase.
  assert_true(
    client_local_store_inventory(
      Array::make(32, 1),
      14240000L,
      21905664L,
      1541184L,
      536870912L,
    )
    is None,
  )
}

///|
test "retained inventory rejects invalid and overflowing capacities" {
  for inputs in [[-1], [1, -1]] {
    assert_true(client_local_store_inventory(inputs, 0L, 0L, 0L, 10L) is None)
  }
  assert_true(client_local_store_inventory([1], -1L, 0L, 0L, 10L) is None)
  assert_true(client_local_store_inventory([1], 0L, -1L, 0L, 10L) is None)
  assert_true(client_local_store_inventory([1], 0L, 0L, -1L, 10L) is None)
  assert_true(client_local_store_inventory([1], 0L, 0L, 0L, -1L) is None)
  assert_true(
    client_local_store_inventory(
      [1],
      9223372036854775807L,
      0L,
      1L,
      9223372036854775807L,
    )
    is None,
  )
  assert_true(
    client_local_store_inventory(
      [2147483647],
      0L,
      9223372036854775807L,
      0L,
      9223372036854775807L,
    )
    is None,
  )
}
