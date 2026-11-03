///|
fn local_file_store_recipe_fixture(
  native_bytes? : Int64 = 6000L,
  components? : Int = 128,
  window? : Int = 65536,
  body? : Int = 100000,
  request? : Int = 100000,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  installed_local_file_store_recipe_capacities(
    body, 10000, 16, 1000000, 100000, 64, request, 100000, 65536, 1000000, 512, 16,
    native_bytes, 4096, 1024, components, 130, window,
  )
}

///|
test "Local STORE quote retains actual native descriptor multiplicity and one read window" {
  let original = local_file_store_recipe_fixture().unwrap()
  assert_eq(original.length(), 6)
  for index in 0..<5 {
    assert_true(
      @execution.execution_capacity_retained_bytes(original[index]) > 0L,
    )
    assert_true(
      @execution.execution_capacity_execution_bytes(original[index]) >=
      @execution.execution_capacity_retained_bytes(original[index]),
    )
  }
  let larger = local_file_store_recipe_fixture(native_bytes=6001L).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(larger[3]) -
    @execution.execution_capacity_retained_bytes(original[3]),
    129L,
  )
  let window = local_file_store_recipe_fixture(window=65537).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(window[3]),
    @execution.execution_capacity_retained_bytes(original[3]),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(window[3]) -
    @execution.execution_capacity_execution_bytes(original[3]),
    1L,
  )
  assert_eq(@execution.execution_capacity_execution_bytes(original[5]), 0L)
}

///|
test "Local STORE quote preserves failed input envelope despite smaller accepted request" {
  let smaller = local_file_store_recipe_fixture(request=1000).unwrap()
  let bigger_input = local_file_store_recipe_fixture(request=1000, body=100001).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(bigger_input[2]) >
    @execution.execution_capacity_execution_bytes(smaller[2]),
  )
  assert_true(
    local_file_store_recipe_fixture(native_bytes=0L) is Err(Unsupported),
  )
  assert_true(
    local_file_store_recipe_fixture(components=131) is Err(Unsupported),
  )
  assert_true(local_file_store_recipe_fixture(window=0) is Err(Unsupported))
  assert_true(
    local_file_store_recipe_fixture(native_bytes=9223372036854775807L)
    is Err(Unsupported),
  )
}

///|
test "Local closed saved codec keeps original response buffers and generic fallback" {
  let bytes = installed_local_file_store_control_wire_bound()
  assert_eq(bytes, 1510)
  let original = local_file_store_recipe_fixture().unwrap()
  let narrow = installed_local_file_store_recipe_capacities(
    100000,
    10000,
    16,
    1000000,
    100000,
    64,
    100000,
    100000,
    65536,
    1000000,
    512,
    16,
    6000L,
    4096,
    1024,
    128,
    130,
    65536,
    control_wire_bytes=Some(bytes),
  ).unwrap()
  for index in [0, 1, 2, 3, 5] {
    assert_eq(
      @execution.execution_capacity_retained_bytes(narrow[index]),
      @execution.execution_capacity_retained_bytes(original[index]),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(narrow[index]),
      @execution.execution_capacity_execution_bytes(original[index]),
    )
  }
  assert_true(
    @execution.execution_capacity_retained_bytes(narrow[4]) >= 2000000L,
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(original[4]) -
    @execution.execution_capacity_execution_bytes(narrow[4]) >
    200000000L,
  )
}

///|
test "Local JS clones retain complete DATA without a nonexistent Source parser" {
  let bytes = 100000
  let nodes = 10000
  let returned = @source.json_tree_retained_construction_extent(
    nodes,
    nodes - 1,
    nodes,
    0,
    bytes.to_int64(),
    keep_spans=false,
  ).unwrap()
  let tree = @execution.preparation_representation_cost({
    record_headers: returned.record_headers,
    reference_slots: returned.reference_slots,
    scalar_words: returned.scalar_words,
    owned_utf16_units: returned.owned_utf16_units,
    owned_wire_bytes: 0L,
  }).unwrap()
  let capacity = local_file_store_json_capacity(bytes, nodes, 16).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(capacity),
    tree + 8L * bytes.to_int64(),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(capacity),
    tree + 16L * bytes.to_int64(),
  )
  // The real Source proposal parser is still a distinct, fully quoted owner.
  let native = installed_standard_host_capture_row_capacity(bytes, nodes, 16).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(native) >
    @execution.execution_capacity_execution_bytes(capacity),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(
      local_file_store_json_capacity(bytes + 1, nodes, 16).unwrap(),
    ) >
    @execution.execution_capacity_execution_bytes(capacity),
  )
  assert_true(local_file_store_json_capacity(0, nodes, 16) is None)
}
