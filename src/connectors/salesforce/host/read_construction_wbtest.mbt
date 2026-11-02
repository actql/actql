///|
test "named read metadata uses bounded original copies without another declaration" {
  let limits : @catalog.DescribeLimits = {
    max_bytes: 128,
    max_nodes: 32,
    max_depth: 8,
    max_fields: 2,
    max_name_units: 64,
  }
  let inventory = sf_read_observation_construction_inventory(
    limits, 4096, 10, 4,
  ).unwrap()
  // Independent authored vector for F=2 and R=min(32,2*2)=4:
  // metadata collection 78H/271R/182W=4872B; carrier collection
  // 79H/333R/137W=5024B; String headers84H=1344B; owned text4320U=8640B.
  // Observation text ceiling:1024+6*(10+4)=1108U; original base64:172U.
  assert_eq(
    @execution.preparation_representation_cost(inventory.retained).unwrap(),
    19880L,
  )
  assert_eq(inventory.retained.owned_utf16_units, 4320L)
  assert_eq(inventory.retained.owned_wire_bytes, 0L)
  assert_eq(inventory.workspace_nodes, 0L)
  assert_eq(inventory.retained_nodes, 0L)
  let total = @execution.preparation_execution_capacity(inventory).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(total) >
    @execution.execution_capacity_retained_bytes(total),
  )
  let smaller = sf_read_observation_construction_inventory(
    { ..limits, max_fields: 1, },
    4096,
    10,
    4,
  ).unwrap()
  assert_true(
    @execution.preparation_representation_cost(smaller.retained).unwrap() <
    19880L,
  )
}

///|
test "named read metadata retains the same literal output bound through writer refusal" {
  let limits : @catalog.DescribeLimits = {
    max_bytes: 128,
    max_nodes: 32,
    max_depth: 8,
    max_fields: 2,
    max_name_units: 64,
  }
  let inventory = sf_read_observation_construction_inventory(limits, 256, 10, 4).unwrap()
  // The original writer can refuse at256B before a complete observation.
  // Its workspace and all metadata/copy/raw evidence duties still exist.
  assert_eq(inventory.retained.owned_utf16_units, 1764L)
  assert_eq(
    @execution.preparation_representation_cost(inventory.retained).unwrap(),
    14768L,
  )
  assert_true(inventory.workspace.owned_wire_bytes >= 128L + 256L)
}

///|
test "named read metadata rejects invalid constructor bounds without parsing" {
  let limits : @catalog.DescribeLimits = {
    max_bytes: 128,
    max_nodes: 32,
    max_depth: 8,
    max_fields: 2,
    max_name_units: 64,
  }
  for
    invalid in [
      { ..limits, max_bytes: 0, },
      { ..limits, max_nodes: 0, },
      { ..limits, max_depth: 0, },
      { ..limits, max_fields: 0, },
      { ..limits, max_name_units: 0, },
    ] {
    assert_true(
      sf_read_observation_construction_inventory(invalid, 4096, 10, 4) is None,
    )
  }
  assert_true(
    sf_read_observation_construction_inventory(limits, 0, 10, 4) is None,
  )
  assert_true(
    sf_read_observation_construction_inventory(limits, 4096, -1, 4) is None,
  )
  assert_true(
    sf_read_observation_construction_inventory(limits, 4096, 10, 0) is None,
  )
  // Extreme Int bounds are DATA only: quote without an allocation or parser.
  let large = sf_read_observation_construction_inventory(
    {
      max_bytes: 2147483647,
      max_nodes: 2147483647,
      max_depth: 2147483647,
      max_fields: 2147483647,
      max_name_units: 2147483647,
    },
    2147483647,
    2147483647,
    2147483647,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(
      @execution.preparation_execution_capacity(large).unwrap(),
    ) >
    2147483647L,
  )
}

///|
test "native query inventory keeps the full failed page before total-row refusal" {
  let limits : @catalog.QueryPageLimits = {
    max_bytes: 128,
    max_nodes: 32,
    max_depth: 8,
    max_rows: 2,
    max_locator_units: 64,
  }
  // Existing v0.1 endpoint, not another provider acceptance rule. The pricing
  // prototype is private DATA; real query values keep their original contracts.
  assert_true(@contract.decimal_contract(38, 0, nullable=false) is Some(_))
  assert_true(@contract.decimal_contract(39, 0, nullable=false) is None)
  assert_eq(@catalog.address_component_role_bounds(), (10, 15))
  let current = sf_read_query_construction_inventory(limits, 2, 2, 5, 64).unwrap()
  let larger = sf_read_query_construction_inventory(
    { ..limits, max_rows: 3, },
    2,
    2,
    5,
    64,
  ).unwrap()
  // Independent one-row conversion envelope:13H/67R/10W=824B for width2.
  // The Value node ceiling and returned prefix remain identical. No smaller
  // successful capture row bound enters the current-page constructor quote.
  assert_true(current.retained == larger.retained)
  assert_eq(
    @execution.preparation_representation_cost(larger.workspace).unwrap() -
    @execution.preparation_representation_cost(current.workspace).unwrap(),
    824L,
  )
  assert_true(
    sf_read_query_construction_inventory(
      { ..limits, max_rows: 2147483647, },
      2147483647,
      2,
      5,
      64,
    )
    is None,
  )
}

///|
test "native read capacity composes returned originals and serial constructor peaks" {
  let describe : @catalog.DescribeLimits = {
    max_bytes: 128,
    max_nodes: 32,
    max_depth: 8,
    max_fields: 2,
    max_name_units: 64,
  }
  let query : @catalog.QueryPageLimits = {
    max_bytes: 128,
    max_nodes: 32,
    max_depth: 8,
    max_rows: 2,
    max_locator_units: 64,
  }
  let combined = native_read_construction_capacity(
    describe, query, 4096, 10, 4, 2, 2, 5, 64,
  ).unwrap()
  let metadata = sf_read_observation_construction_inventory(
    describe, 4096, 10, 4,
  ).unwrap()
  let reading = sf_read_query_construction_inventory(query, 2, 2, 5, 64).unwrap()
  let retained = @execution.preparation_representation_cost(metadata.retained).unwrap() +
    @execution.preparation_representation_cost(reading.retained).unwrap()
  let metadata_workspace = @execution.preparation_representation_cost(
    metadata.workspace,
  ).unwrap()
  let query_workspace = @execution.preparation_representation_cost(
    reading.workspace,
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(combined), retained)
  assert_eq(
    @execution.execution_capacity_execution_bytes(combined),
    retained + Int64::max(metadata_workspace, query_workspace),
  )
  assert_true(
    native_read_construction_capacity(
      describe,
      { ..query, max_nodes: 2147483647, },
      4096,
      10,
      4,
      2,
      2,
      5,
      64,
    )
    is None,
  )
}
