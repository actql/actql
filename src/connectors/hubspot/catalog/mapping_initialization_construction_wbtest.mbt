///|
fn update_mapping_capacity_limits() -> MappingLimits {
  {
    max_properties: 100,
    max_fields: 16,
    max_name_bytes: 256,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }
}

///|
test "HubSpot update Mapping construction separates retained output from ended workspace" {
  let limits = update_mapping_capacity_limits()
  let quote = execution_mapping_construction_capacity(2, 0, 24L, limits).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quote)
  let peak = @execution.execution_capacity_execution_bytes(quote)
  assert_true(retained > 0L)
  assert_true(peak > retained)
  assert_true(peak < 536870912L)
  // The quote does not issue a Mapping or derive writable support. The
  // unchanged semantic constructor still checks the complete original types.
  let original = catalog(
    (
      #|{"results":[{"name":"amount","type":"number","fieldType":"number","calculated":false,"modificationMetadata":{"readOnlyValue":false}},{"name":"tags","type":"enumeration","fieldType":"checkbox","calculated":false,"modificationMetadata":{"readOnlyValue":false},"options":[{"value":"a"},{"value":"b"}]}]}
    ),
  )
  let mapping = prepare_execution_mapping(
    original,
    "hubspot",
    "sha256:" + "a".repeat(64),
    "companies",
    Update,
    ["amount", "tags"],
    [],
    limits,
  ).unwrap()
  let body = execution_mapping_body(mapping)
  assert_true(body.contains("\"effect_kind\":\"update\""))
  assert_true(body.contains("\"precision\":38,\"scale\":10"))
  assert_true(
    body.contains("\"items\":{\"nullable\":false,\"type\":\"string\"}"),
  )
  println("HubSpot selected Mapping retained=\{retained} peak=\{peak}")
}

///|
test "HubSpot Mapping quote ignores unused wider output maxima and keeps logical refusal" {
  let a = update_mapping_capacity_limits()
  let b = { ..a, max_bytes: 20000, max_nodes: 2000, max_depth: 40, }
  let first = execution_mapping_construction_capacity(1, 0, 15L, a).unwrap()
  let second = execution_mapping_construction_capacity(1, 0, 15L, b).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(first),
    @execution.execution_capacity_retained_bytes(second),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(first),
    @execution.execution_capacity_execution_bytes(second),
  )
  let tiny = { ..a, max_bytes: 16, max_nodes: 4, max_depth: 2, }
  assert_true(
    execution_mapping_construction_capacity(1, 0, 15L, tiny) is Some(_),
  )
  let original = catalog(
    (
      #|{"results":[{"name":"label","type":"string","fieldType":"text","calculated":false,"modificationMetadata":{"readOnlyValue":false}}]}
    ),
  )
  assert_true(
    prepare_execution_mapping(
      original,
      "hubspot",
      "sha256:" + "a".repeat(64),
      "companies",
      Update,
      ["label"],
      [],
      tiny,
    )
    is Err(_),
  )
}

///|
test "HubSpot Mapping construction refuses invalid counts limits and nonfinite arithmetic demand" {
  let limits = update_mapping_capacity_limits()
  for
    (fields, sources, units) in [
      (-1, 0, 1L),
      (0, -1, 1L),
      (0, 0, -1L),
      (16, 0, 1L),
      (1, 17, 1L),
      (1, 0, 2305843009213693952L),
    ] {
    assert_true(
      execution_mapping_construction_capacity(fields, sources, units, limits)
      is None,
    )
  }
  assert_true(
    execution_mapping_construction_capacity(1, 0, 1L, {
      ..limits,
      max_bytes: 0,
    })
    is None,
  )
}
