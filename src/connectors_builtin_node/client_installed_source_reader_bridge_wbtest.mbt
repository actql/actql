///|
test "Salesforce native quote keeps original two metadata occurrences and same opaque composition" {
  let limits = [128, 512, 32, 8, 2, 3, 4, 2, 64, 32, 256, 32, 128, 128, 32, 8]
  let describe = [128, 32, 8, 2, 64]
  let actual = client_program_installed_salesforce_source_reader_capacity(
    limits, 2, 64, describe, 4096, 10, 4, 2, 5, 64,
  ).unwrap()
  let native = @salesforce_catalog.native_read_construction_capacity(
    {
      max_bytes: 128,
      max_nodes: 32,
      max_depth: 8,
      max_fields: 2,
      max_name_units: 64,
    },
    {
      max_bytes: 128,
      max_nodes: 32,
      max_depth: 8,
      max_rows: 2,
      max_locator_units: 64,
    },
    4096,
    10,
    4,
    2,
    2,
    5,
    64,
  )
  let expected = @client_local_host.installed_native_source_reader_capacity(
    limits, 2, 64, native,
  ).unwrap()
  assert_eq(
    (
      @execution.execution_capacity_retained_bytes(actual),
      @execution.execution_capacity_execution_bytes(actual),
    ),
    (
      @execution.execution_capacity_retained_bytes(expected),
      @execution.execution_capacity_execution_bytes(expected),
    ),
  )
  assert_true(
    client_program_installed_salesforce_source_reader_capacity(
      [],
      2,
      64,
      describe,
      4096,
      10,
      4,
      2,
      5,
      64,
    )
    is None,
  )
  assert_true(
    client_program_installed_salesforce_source_reader_capacity(
      limits,
      2,
      64,
      [],
      4096,
      10,
      4,
      2,
      5,
      64,
    )
    is None,
  )
  assert_true(
    client_program_installed_salesforce_source_reader_capacity(
      limits, 2, 64, describe, 4096, 10, 4, 3, 5, 64,
    )
    is None,
  )
}

///|
test "original Salesforce Describe query page bounds yield an explicit native quote" {
  // Original read profile:4MB/400000nodes/2000page rows/10query pages/100total
  // rows. Two independent metadata reads use the same original4MB describe
  // bounds. These are constructor DATA, no actual RowRun/Resource admission.
  let limits = [
    4000000, 48000000, 400000, 32, 2000, 100, 12, 2000, 2048, 255, 16384, 400000,
    4000000, 4000000, 400000, 32,
  ]
  let quote = client_program_installed_salesforce_source_reader_capacity(
    limits,
    2,
    65536,
    [4000000, 400000, 32, 1000, 200000],
    8000000,
    1024,
    17,
    10,
    5,
    4096,
  ).unwrap()
  let r = @execution.execution_capacity_retained_bytes(quote)
  let e = @execution.execution_capacity_execution_bytes(quote)
  assert_true(r > 0L && e >= r)
  println("SF_NATIVE_CONSTRUCTION_DATA R=\{r} E=\{e}; no physical admission")
}
