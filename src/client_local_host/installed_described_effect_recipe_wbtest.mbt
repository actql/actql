///|
fn described_recipe_fixture(
  metadata : @execution.ExecutionCapacity,
  target_reads : Bool,
  request_original? : @execution.ExecutionCapacity? = None,
  request_output? : @source.ParseLimits? = None,
  host_input_bytes? : Int? = None,
) -> Array[@execution.ExecutionCapacity] {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  installed_described_effect_recipe_capacities(
    Some([
      (request_original.unwrap_or(zero), None, request_output),
      (zero, None, None),
      (zero, None, None),
      (metadata, None, None),
    ]),
    Some([zero, zero, zero]),
    256,
    16,
    4,
    128,
    8,
    2,
    64,
    32,
    target_reads,
    16,
    32,
    16,
    64,
    16,
    7,
    32,
    256,
    64,
    4,
    0L,
    host_input_bytes~,
  ).unwrap()
}

///|
test "described cold capture includes the same complete request and Host output constructor" {
  let baseline = described_recipe_fixture(
    @execution.execution_capacity(0L, 0L).unwrap(),
    true,
  )
  let request = @execution.execution_capacity(17L, 23L).unwrap()
  let output : @source.ParseLimits = {
    max_input_bytes: 128,
    max_nodes: 8,
    max_depth: 2,
  }
  let selected = described_recipe_fixture(
    @execution.execution_capacity(0L, 0L).unwrap(),
    true,
    request_original=Some(request),
    request_output=Some(output),
  )
  let complete = installed_standard_create_constructor_capacity(
    request,
    None,
    Some(output),
  ).unwrap()
  // This is the checked-row capture slot used BEFORE recoverRequests, not
  // a promise that the warm request child will also execute on cold restore.
  assert_eq(
    @execution.execution_capacity_retained_bytes(selected[1]) -
    @execution.execution_capacity_retained_bytes(baseline[1]),
    @execution.execution_capacity_retained_bytes(complete),
  )
  // The existing adapter reconstructs rows synchronously. Returned request
  // material remains per row; its private workspace lives once on the same
  // fixed member beside completed Catalog/Preview decoding scratch.
  assert_eq(
    @execution.execution_capacity_execution_bytes(selected[1]) -
    @execution.execution_capacity_retained_bytes(selected[1]),
    @execution.execution_capacity_execution_bytes(baseline[1]) -
    @execution.execution_capacity_retained_bytes(baseline[1]),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(selected[0]) -
    @execution.execution_capacity_retained_bytes(selected[0]) >=
    @execution.execution_capacity_execution_bytes(complete) -
    @execution.execution_capacity_retained_bytes(complete),
  )
}

///|
test "described recipe retains original metadata once on member before callbacks" {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  let baseline = described_recipe_fixture(zero, true)
  let selected = described_recipe_fixture(
    @execution.execution_capacity(17L, 23L).unwrap(),
    true,
  )
  assert_eq(selected.length(), 8)
  assert_eq(
    @execution.execution_capacity_retained_bytes(selected[0]) -
    @execution.execution_capacity_retained_bytes(baseline[0]),
    17L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(selected[0]) -
    @execution.execution_capacity_execution_bytes(baseline[0]),
    17L,
  )
  // The returned metadata is not duplicated on every row/control/physical
  // slot. Existing controls carry its private scratch, not another R copy.
  for index in 1..<8 {
    assert_eq(
      @execution.execution_capacity_retained_bytes(selected[index]),
      @execution.execution_capacity_retained_bytes(baseline[index]),
    )
  }
}

///|
test "described recipe metadata scratch never expands target or HTTP reservations" {
  let baseline = described_recipe_fixture(
    @execution.execution_capacity(17L, 23L).unwrap(),
    true,
  )
  let large = described_recipe_fixture(
    @execution.execution_capacity(17L, 1000000000L).unwrap(),
    true,
  )
  for index in [0, 1, 2, 3, 5, 6, 7] {
    assert_eq(
      @execution.execution_capacity_execution_bytes(baseline[index]),
      @execution.execution_capacity_execution_bytes(large[index]),
    )
  }
  assert_true(
    @execution.execution_capacity_execution_bytes(large[4]) >
    @execution.execution_capacity_execution_bytes(baseline[4]),
  )
}

///|
test "described recipe create retains Describe but selects no target read capacity" {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  let create = described_recipe_fixture(zero, false)
  let update = described_recipe_fixture(zero, true)
  assert_eq(@execution.execution_capacity_retained_bytes(create[6]), 0L)
  assert_eq(@execution.execution_capacity_execution_bytes(create[6]), 0L)
  assert_true(@execution.execution_capacity_execution_bytes(update[6]) > 0L)
  // Metadata HTTP is the SAME member physical occurrence in both shapes.
  assert_eq(
    @execution.execution_capacity_execution_bytes(create[7]),
    @execution.execution_capacity_execution_bytes(update[7]),
  )
}

///|
test "described recipe keeps post-return request export on original control workspace" {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  let baseline = described_recipe_fixture(zero, true)
  let selected = described_recipe_fixture(
    zero,
    true,
    request_original=Some(
      @execution.execution_capacity(17L, 1000000000L).unwrap(),
    ),
  )
  // requestFacts reads/parses the SAME exported request after the request
  // child's Native constructor returned. Its scratch therefore belongs on
  // this original control frame too, rather than assuming completed child W.
  assert_true(
    @execution.execution_capacity_execution_bytes(selected[4]) >
    @execution.execution_capacity_execution_bytes(baseline[4]),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(selected[0]) -
    @execution.execution_capacity_retained_bytes(selected[0]) >=
    1000000000L - 17L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(selected[1]) -
    @execution.execution_capacity_retained_bytes(selected[1]),
    @execution.execution_capacity_execution_bytes(baseline[1]) -
    @execution.execution_capacity_retained_bytes(baseline[1]),
  )
  for index in [3, 5, 6, 7] {
    assert_eq(
      @execution.execution_capacity_execution_bytes(selected[index]),
      @execution.execution_capacity_execution_bytes(baseline[index]),
    )
  }
}
