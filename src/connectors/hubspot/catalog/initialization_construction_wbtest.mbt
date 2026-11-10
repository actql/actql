///|
test "HubSpot native initialization quote precedes actual account and property originals" {
  let account = b"{\"portalId\":12345}"
  let account_capacity = account_initialization_construction_capacity(
    account.length(),
    28,
    5,
    8192,
    2000,
    16,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(account_capacity) > 0L,
  )
  assert_eq(
    project_account_identity(account, {
      max_input_bytes: 8192,
      max_nodes: 2000,
      max_depth: 16,
    }).unwrap().portal_id,
    12345,
  )
  let body = b"{\"results\":[{\"name\":\"tags\",\"type\":\"enumeration\",\"fieldType\":\"checkbox\",\"options\":[{\"value\":\"red\"},{\"value\":\"blue\"}]}]}"
  let quote = object_initialization_construction_capacity(
    body.length(),
    4 * ((body.length() + 2) / 3),
    9,
    limits(),
    16,
    1000,
    200000,
    20000,
    20,
  ).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(quote)
  println(
    "HubSpot property constructor body_bytes=\{body.length()} peak_bytes=\{peak}",
  )
  assert_true(peak < 536870912L)
  assert_true(@execution.execution_capacity_retained_bytes(quote) < peak)
  let original = project_properties(body, "companies", limits()).unwrap()
  let wire = object_schema_wire(
    original,
    property_names(original),
    16,
    1000,
    200000,
    20000,
    20,
  ).unwrap()
  assert_true(wire.contains("\"items\""))
}

///|
test "HubSpot quotes preserve input bounds and malformed prefix capacity" {
  assert_true(
    account_initialization_construction_capacity(-1, 0, 5, 8192, 100, 8) is None,
  )
  assert_true(
    object_initialization_construction_capacity(
      20001,
      0,
      9,
      limits(),
      16,
      1000,
      200000,
      20000,
      20,
    )
    is None,
  )
  let body = b"{\"results\":[{\"name\":\"tags\",\"type\":\"enumeration\",\"fieldType\":\"checkbox\",\"options\":[{\"value\":\"red\"},{\"value\":\"red\"}]}]}"
  assert_true(
    object_initialization_construction_capacity(
      body.length(),
      body.length() * 2,
      9,
      limits(),
      16,
      1000,
      200000,
      20000,
      20,
    )
    is Some(_),
  )
  assert_true(project_properties(body, "companies", limits()) is Err(_))
}

///|
test "HubSpot unchanged tiny input does not charge unused output maximum" {
  let a = object_initialization_construction_capacity(
    200,
    268,
    9,
    limits(),
    16,
    1000,
    200000,
    20000,
    20,
  ).unwrap()
  let b = object_initialization_construction_capacity(
    200,
    268,
    9,
    limits(),
    16,
    1000,
    200001,
    20001,
    20,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(a),
    @execution.execution_capacity_execution_bytes(b),
  )
}

///|
test "Source property projection retains returned originals without completed constructor forests" {
  let original = object_initialization_construction_capacity(
    361489,
    481988,
    9,
    {
      max_bytes: 524288,
      max_nodes: 65536,
      max_depth: 32,
      max_properties: 256,
      max_name_units: 6003,
    },
    256,
    6003,
    65536,
    8000,
    32,
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(original)
  let peak = @execution.execution_capacity_execution_bytes(original)
  println(
    "HubSpot Source property output retained=\{retained} execution=\{peak}",
  )
  assert_true(retained > 361489L + 2L * 65536L)
  assert_true(retained < peak)
  assert_true(
    peak >= 319422677L,
    msg="the original complete bounded constructor peak is not weakened",
  )
}

///|
test "Source property projection borrows original encoded text without duplicating retained storage" {
  let first = object_initialization_construction_capacity(
    200,
    268,
    9,
    limits(),
    16,
    1000,
    200000,
    20000,
    20,
  ).unwrap()
  let wider = object_initialization_construction_capacity(
    200,
    26800,
    9,
    limits(),
    16,
    1000,
    200000,
    20000,
    20,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(first),
    @execution.execution_capacity_retained_bytes(wider),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(wider) >
    @execution.execution_capacity_execution_bytes(first),
  )
}
