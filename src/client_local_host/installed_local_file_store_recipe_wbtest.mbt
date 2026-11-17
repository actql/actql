///|
fn local_file_store_recipe_fixture(
  native_bytes? : Int64 = 6000L,
  components? : Int = 128,
  window? : Int = 65536,
  body? : Int = 100000,
  request? : Int = 100000,
  control_wire? : Int? = None,
  control_response? : Int? = None,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  installed_local_file_store_recipe_capacities(
    body,
    10000,
    16,
    1000000,
    100000,
    64,
    request,
    100000,
    65536,
    1000000,
    512,
    16,
    native_bytes,
    4096,
    1024,
    components,
    130,
    window,
    control_wire_bytes=control_wire,
    control_response_bytes=control_response,
  )
}

///|
test "Local STORE quote retains actual native descriptor multiplicity and one read window" {
  let original = local_file_store_recipe_fixture().unwrap()
  assert_eq(original.length(), 8)
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
  assert_eq(@execution.execution_capacity_retained_bytes(original[6]), 0L)
  assert_true(@execution.execution_capacity_execution_bytes(original[6]) > 0L)
  assert_eq(@execution.execution_capacity_retained_bytes(original[7]), 0L)
  // The existing projected Host tree/text remains in controlsPerRow. Only
  // its one CanonicalWireBytes constructor domain (8B/byte) is selected here.
  assert_eq(@execution.execution_capacity_execution_bytes(original[7]), 524288L)
}

///|
test "Local Grant proof population is retained once while its native selector owns scratch only" {
  let grant = local_file_store_grant_capacity().unwrap()
  // Issuer proof/value/carrier, later authorization and use-id header:
  // H5/R7/W2, plus existing Map entry H4/R11/W13 and 160 UTF16 units.
  // This is independent of any remote Grant parser or signature ceiling.
  assert_eq(@execution.execution_capacity_retained_bytes(grant), 728L)
  assert_eq(@execution.execution_capacity_execution_bytes(grant), 864L)
  for control in [None, Some(1510)] {
    let recipe = local_file_store_recipe_fixture(control_wire=control).unwrap()
    assert_eq(@execution.execution_capacity_retained_bytes(recipe[6]), 0L)
    assert_eq(@execution.execution_capacity_execution_bytes(recipe[6]), 136L)
  }
}

///|
test "Local footprint targets retain CID and duplicate inventory apart from fixed hash scratch" {
  let target = local_file_store_footprint_target_capacity().unwrap()
  // One String header/word, Array growing slots3R, and the existing Set-key
  // upper (Map entry4H11R13W). The CID is71 ASCII/UTF16 units, not a new copy
  // of the request/path. This is the additional live population per row.
  let expected = @execution.preparation_representation_cost({
    record_headers: 5L,
    reference_slots: 14L,
    scalar_words: 14L,
    owned_utf16_units: 71L,
    owned_wire_bytes: 0L,
  }).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(target), expected)
  assert_eq(@execution.execution_capacity_execution_bytes(target), expected)
  let footprint = installed_effect_opaque_boundary_footprint_capacity(
    "local", "file_collection", 1024,
  ).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(footprint), 0L)
  // The fixed hash quote must also exist for an empty member's Set/Array.
  let fixed = @execution.preparation_representation_cost({
    record_headers: 10L,
    reference_slots: 31L,
    scalar_words: 23L,
    owned_utf16_units: 2L * 1024L,
    owned_wire_bytes: 0L,
  }).unwrap()
  assert_true(@execution.execution_capacity_execution_bytes(footprint) > fixed)
  let quoted = local_file_store_recipe_fixture().unwrap()
  let saved = standard_create_saved_control_capacity(1000000, 512, 16).unwrap()
  let projected = local_file_store_json_capacity(65536, 512, 16).unwrap()
  let stored = @execution.execution_capacity_inventory(
    [{ unit: QuotedBytes, count: 1000000L, copies: 3, }],
    [],
    RetainedAlongsideExecution,
  ).unwrap()
  let prior = standard_create_sum_capacities(
    [saved, stored, projected],
    sequential_workspace=true,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(quoted[4]) -
    @execution.execution_capacity_retained_bytes(prior),
    expected +
    @execution.execution_capacity_retained_bytes(
      local_file_store_grant_capacity().unwrap(),
    ),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(quoted[4]) -
    @execution.execution_capacity_execution_bytes(prior),
    expected +
    @execution.execution_capacity_retained_bytes(
      local_file_store_grant_capacity().unwrap(),
    ),
  )
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
test "Local response receiver backs native copy and rejected single batch overlap with the same closed limit" {
  let bound = 65536
  let general = local_file_store_recipe_fixture(control_wire=Some(1510)).unwrap()
  let selected = local_file_store_recipe_fixture(
    control_wire=Some(1510),
    control_response=Some(bound),
  ).unwrap()
  for index in [0, 1, 2, 3, 5] {
    assert_eq(
      @execution.execution_capacity_retained_bytes(selected[index]),
      @execution.execution_capacity_retained_bytes(general[index]),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(selected[index]),
      @execution.execution_capacity_execution_bytes(general[index]),
    )
  }
  let difference = 3L * (1000000L - bound.to_int64())
  assert_eq(
    @execution.execution_capacity_retained_bytes(general[4]) -
    @execution.execution_capacity_retained_bytes(selected[4]),
    difference,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(general[4]) -
    @execution.execution_capacity_execution_bytes(selected[4]),
    difference,
  )
  let next = local_file_store_recipe_fixture(
    control_wire=Some(1510),
    control_response=Some(bound + 1),
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(next[4]) -
    @execution.execution_capacity_retained_bytes(selected[4]),
    3L,
  )
  for invalid in [0, -1, 1000001] {
    assert_true(
      local_file_store_recipe_fixture(control_response=Some(invalid))
      is Err(Unsupported),
    )
  }
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

///|
test "warm File constructors keep real rows and references without Preview policy copies" {
  let initial = installed_local_file_store_initial_constructor_capacities()
  let actual = installed_local_file_store_observed_constructor_capacities(
    2048, 256, 16, 16384, 512, 32768,
  ).unwrap()
  assert_eq(initial.length(), 3)
  assert_eq(actual.length(), 3)
  for index in 0..<3 {
    assert_true(
      @execution.execution_capacity_retained_bytes(initial[index]) > 0L,
    )
    assert_true(
      @execution.execution_capacity_retained_bytes(actual[index]) >=
      @execution.execution_capacity_retained_bytes(initial[index]),
    )
  }
  let row = installed_standard_host_capture_row_capacity(2048, 256, 16).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(actual[1]),
    @execution.execution_capacity_retained_bytes(row),
  )
  // Distinct live member and row copies still sum. This is a selected quote
  // vector, not execution or a universal Host/default budget assertion.
  let retained = @execution.execution_capacity_retained_bytes(actual[0]) +
    @execution.execution_capacity_retained_bytes(actual[1]) +
    @execution.execution_capacity_retained_bytes(actual[2])
  assert_true(17L * retained < 536870912L)
}

///|
test "warm File wire escaping increases text but not the original node inventory" {
  let a = installed_local_file_store_observed_constructor_capacities(
    2048, 256, 16, 16384, 512, 32768,
  ).unwrap()
  let text = installed_local_file_store_observed_constructor_capacities(
    2048, 256, 16, 16385, 512, 32768,
  ).unwrap()
  let nodes = installed_local_file_store_observed_constructor_capacities(
    2048, 256, 16, 16384, 513, 32768,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(text[2]) >
    @execution.execution_capacity_retained_bytes(a[2]),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(nodes[2]) >
    @execution.execution_capacity_retained_bytes(a[2]),
  )
  for index in [0, 1] {
    assert_eq(
      @execution.execution_capacity_retained_bytes(text[index]),
      @execution.execution_capacity_retained_bytes(a[index]),
    )
  }
}

///|
test "warm File constructor refuses missing geometry before a capacity is selected" {
  assert_true(
    installed_local_file_store_observed_constructor_capacities(
      0, 256, 16, 16384, 512, 32768,
    )
    is Err(Unsupported),
  )
  assert_true(
    installed_local_file_store_observed_constructor_capacities(
      2048, 256, 16, 16384, 0, 32768,
    )
    is Err(Unsupported),
  )
  assert_true(
    installed_local_file_store_observed_constructor_capacities(
      2048, 256, 16, 16384, 512, 0,
    )
    is Err(Unsupported),
  )
}

///|
test "empty warm File capture retains its real recovery envelope without row construction" {
  let initial = installed_local_file_store_initial_constructor_capacities()
  let empty = installed_local_file_store_observed_constructor_capacities(
    0, 0, 16, 0, 0, 525,
  ).unwrap()
  for index in [1, 2] {
    assert_eq(
      @execution.execution_capacity_retained_bytes(empty[index]),
      @execution.execution_capacity_retained_bytes(initial[index]),
    )
  }
  let larger = installed_local_file_store_observed_constructor_capacities(
    0, 0, 16, 0, 0, 526,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(larger[0]) >
    @execution.execution_capacity_retained_bytes(empty[0]),
  )
  assert_true(
    installed_local_file_store_observed_constructor_capacities(
      0, 1, 16, 0, 0, 525,
    )
    is Err(Unsupported),
  )
}

///|
test "cold File capacities retain saved tree beside every immutable request clone" {
  let actual = installed_local_file_store_observed_recovery_capacities(
    4096, 1365, 16,
  ).unwrap()
  let tree = local_file_store_json_capacity(4096, 1365, 16).unwrap()
  assert_eq(actual.length(), 2)
  assert_eq(
    @execution.execution_capacity_retained_bytes(actual[0]),
    2L * @execution.execution_capacity_retained_bytes(tree) +
    @execution.execution_capacity_retained_bytes(
      installed_local_file_store_initial_constructor_capacities()[0],
    ),
  )
  let handles = @execution.preparation_representation_cost({
    record_headers: 4L,
    reference_slots: 16L,
    scalar_words: 1L,
    owned_utf16_units: 71L,
    owned_wire_bytes: 0L,
  }).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(actual[1]), handles)
  // Seventeen distinct member envelopes keep seventeen complete saved and
  // cloned forests. A101-row member keeps ONE saved/clone forest plus101
  // original handle records; it does not hold101 complete envelopes.
  let retained = @execution.execution_capacity_retained_bytes(actual[0]) +
    @execution.execution_capacity_retained_bytes(actual[1])
  assert_true(17L * retained < 536870912L)
  let extent = prepare_installed_effect_capture_extent(
    "files.write.capture",
    actual[0],
    actual[1],
  ).unwrap()
  let resolved = resolve_installed_effect_capture_extent(extent, 101).unwrap()
  let r = @execution.execution_capacity_retained_bytes(resolved.capacity)
  let e = @execution.execution_capacity_execution_bytes(resolved.capacity)
  assert_eq(
    r,
    @execution.execution_capacity_retained_bytes(actual[0]) + 101L * handles,
  )
  let ledger = @resources.create_ledger({
    planning_work: 1,
    attempts: 0,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: r,
    execution_bytes: e,
  }).unwrap()
  let pressure = @resources.reserve_capacity(ledger, 1L, 1L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(@resources.reserve_capacity(ledger, r, e) is Err(RetentionLimit))
  assert_eq(@resources.ledger_usage(ledger), before)
  @resources.settle_capacity(ledger, pressure).unwrap()
  let owned = @resources.reserve_capacity(ledger, r, e).unwrap()
  @resources.settle_capacity(ledger, owned).unwrap()
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "cold File geometry refuses missing original wire or tree bounds" {
  for fields in [(0, 1, 16), (1, 0, 16), (1, 1, 0)] {
    assert_true(
      installed_local_file_store_observed_recovery_capacities(
        fields.0,
        fields.1,
        fields.2,
      )
      is Err(Unsupported),
    )
  }
}
