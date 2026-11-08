///|
fn response_metadata_profile() -> Array[Int] {
  [
    524288, 65536, 32, 256, 6003, 2, 4, 6, 2, 256, 128, 16384, 65536, 262144, 16384,
    32,
  ]
}

///|
fn response_metadata_ledger() -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 1000000L,
    retained_bytes: 536870912L,
    execution_bytes: 536870912L,
  }).unwrap()
}

///|
test "HubSpot response metadata prefixes fund only their actual constructors" {
  let profile = response_metadata_profile()
  // The received body is authored independently; no real account/state is read.
  let account = b"{\"portalId\":41}"
  let initial = source_read_construction_capacity(profile, 37264, []).unwrap()
  let first = source_read_construction_capacity(profile, 37264, [
    account.length(),
  ]).unwrap()
  let delta = @execution.execution_capacity_retained_bytes(first) -
    @execution.execution_capacity_retained_bytes(initial)
  println("HubSpot account-prefix retained delta=\{delta}")
  let ledger = response_metadata_ledger()
  let baseline = @resources.reserve_capacity(ledger, 472539124L, 472539124L).unwrap()
  let account_capacity = match
    @resources.reserve_capacity(ledger, delta, delta) {
    Ok(value) => value
    Err(_) => fail("Metadata constructor exceeded unchanged residual")
  }
  assert_eq(
    project_account_identity(account, {
      max_input_bytes: profile[0],
      max_nodes: profile[1],
      max_depth: profile[2],
    }).unwrap().portal_id,
    41,
  )
  @resources.settle_capacity(ledger, account_capacity).unwrap()
  @resources.settle_capacity(ledger, baseline).unwrap()
  let properties = Array::makei(245, index => {
    "{\"name\":\"field_" +
    index.to_string() +
    "\",\"type\":\"string\",\"fieldType\":\"text\",\"description\":\"" +
    String::make(1300, 'x') +
    "\"}"
  })
  let body = @utf8.encode("{\"results\":[" + properties.join(",") + "]}")
  assert_true(body.length() > 300000 && body.length() < profile[0])
  let prefix = [account.length(), body.length()]
  let metadata = source_read_construction_capacity(profile, 37264, prefix).unwrap()
  let metadata_bytes = @execution.execution_capacity_execution_bytes(metadata)
  println(
    "HubSpot245-property metadata bytes=\{body.length()} quote=\{metadata_bytes}",
  )
  let metadata_ledger = response_metadata_ledger()
  let metadata_capacity = @resources.reserve_capacity(
    metadata_ledger,
    @execution.execution_capacity_retained_bytes(metadata),
    metadata_bytes,
  ).unwrap()
  let original = project_properties(body, "companies", {
    max_bytes: profile[0],
    max_nodes: profile[1],
    max_depth: profile[2],
    max_properties: profile[3],
    max_name_units: profile[4],
  }).unwrap()
  recheck_property_catalog(original, original, profile[3]).unwrap()
  assert_eq(property_names(original).length(), 245)
  @resources.settle_capacity(metadata_ledger, metadata_capacity).unwrap()
  let wider_rows = profile.copy()
  wider_rows[11] = 32768
  wider_rows[12] = 131072
  wider_rows[13] = 524288
  wider_rows[14] = 32768
  wider_rows[15] = 64
  let unchanged = source_read_construction_capacity(wider_rows, 37264, prefix).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(unchanged),
    @execution.execution_capacity_retained_bytes(metadata),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(unchanged),
    metadata_bytes,
  )
  let one_short = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 16,
    holdings: 16,
    transfer_bytes: 1000000L,
    retained_bytes: @execution.execution_capacity_retained_bytes(metadata) - 1L,
    execution_bytes: metadata_bytes,
  }).unwrap()
  assert_true(
    @resources.reserve_capacity(
      one_short,
      @execution.execution_capacity_retained_bytes(metadata),
      metadata_bytes,
    )
    is Err(@resources.RetentionLimit),
  )
  let rows = source_read_construction_capacity(profile, 37264, [
    account.length(),
    body.length(),
    64,
  ]).unwrap()
  let wider = source_read_construction_capacity(wider_rows, 37264, [
    account.length(),
    body.length(),
    64,
  ]).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(wider) >
    @execution.execution_capacity_retained_bytes(rows),
  )
  assert_true(source_read_construction_capacity(profile, 37264, [-1]) is None)
  assert_true(
    source_read_construction_capacity(profile, 37264, [profile[0] + 1]) is None,
  )
}
