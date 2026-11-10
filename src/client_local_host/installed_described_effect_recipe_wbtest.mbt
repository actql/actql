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
fn described_multiread_fixture(
  metadata_occurrences : Int,
  target_occurrences : Int,
  target_on_child : Bool,
  target : @execution.ExecutionCapacity,
  target_reads? : Bool = true,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  installed_described_effect_recipe_capacities(
    Some([
      (zero, None, None),
      (target, None, None),
      (zero, None, None),
      (zero, None, None),
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
    metadata_occurrences~,
    target_occurrences~,
    target_on_child~,
  )
}

///|
test "described multi-read defaults retain every original three-phase quantity" {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  for target_reads in [false, true] {
    let old = described_recipe_fixture(zero, target_reads)
    let explicit = described_multiread_fixture(3, 3, false, zero, target_reads~).unwrap()
    assert_eq(old.length(), explicit.length())
    for index in 0..<old.length() {
      assert_eq(
        @execution.execution_capacity_retained_bytes(old[index]),
        @execution.execution_capacity_retained_bytes(explicit[index]),
      )
      assert_eq(
        @execution.execution_capacity_execution_bytes(old[index]),
        @execution.execution_capacity_execution_bytes(explicit[index]),
      )
    }
  }
}

///|
test "described multi-read Grant retention follows actual added occurrences with one synchronous workspace" {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  let baseline = described_multiread_fixture(3, 3, false, zero).unwrap()
  let grant = standard_create_grant_capacity().unwrap()
  for pair in [(6, 3, 3), (3, 12, 9), (6, 12, 12)] {
    let (metadata, target, additional) = pair
    let selected = described_multiread_fixture(metadata, target, false, zero).unwrap()
    assert_eq(
      @execution.execution_capacity_retained_bytes(selected[4]) -
      @execution.execution_capacity_retained_bytes(baseline[4]),
      additional.to_int64() *
      @execution.execution_capacity_retained_bytes(grant),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(selected[4]) -
      @execution.execution_capacity_retained_bytes(selected[4]),
      @execution.execution_capacity_execution_bytes(baseline[4]) -
      @execution.execution_capacity_retained_bytes(baseline[4]),
    )
    for index in [0, 1, 2, 3, 5, 6, 7] {
      assert_eq(
        @execution.execution_capacity_retained_bytes(selected[index]),
        @execution.execution_capacity_retained_bytes(baseline[index]),
      )
      assert_eq(
        @execution.execution_capacity_execution_bytes(selected[index]),
        @execution.execution_capacity_execution_bytes(baseline[index]),
      )
    }
  }
}

///|
test "described multi-read target decoder keeps its private workspace on original physical child" {
  let target = @execution.execution_capacity(17L, 1000L).unwrap()
  let before = described_multiread_fixture(6, 12, false, target).unwrap()
  let inside = described_multiread_fixture(6, 12, true, target).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(inside[6]),
    @execution.execution_capacity_retained_bytes(before[6]),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(inside[6]) -
    @execution.execution_capacity_execution_bytes(before[6]),
    983L,
  )
  for index in [0, 1, 2, 3, 4, 5, 7] {
    assert_eq(
      @execution.execution_capacity_retained_bytes(inside[index]),
      @execution.execution_capacity_retained_bytes(before[index]),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(inside[index]),
      @execution.execution_capacity_execution_bytes(before[index]),
    )
  }
}

///|
test "described multi-read cannot lower original occurrences or invent a missing target child" {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  for counts in [(2, 3), (3, 2), (-1, 3), (3, -1)] {
    let (metadata, target) = counts
    assert_true(
      described_multiread_fixture(metadata, target, false, zero)
      is Err(Unsupported),
    )
  }
  assert_true(
    described_multiread_fixture(6, 12, false, zero, target_reads=false)
    is Err(Unsupported),
  )
  assert_true(
    described_multiread_fixture(3, 3, true, zero, target_reads=false)
    is Err(Unsupported),
  )
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

///|
// The production described-record composer supplies the COMPLETE child:
// received HTTP backing + the original Core-selected secret bound + metadata.
// Other recipe inputs below cannot grant this child any surrounding allowance.
fn hubspot_full_metadata_response_quote(
  metadata : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  installed_described_effect_recipe_capacities(
    Some([
      (zero, None, None),
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
    true,
    16,
    32,
    16,
    524288,
    installed_source_reader_policy()[0],
    7,
    16384,
    256,
    64,
    4,
    0L,
    response_read_quantum=16384,
    metadata_on_child=true,
    metadata_occurrences=6,
    target_occurrences=12,
    target_on_child=true,
    host_input_bytes=Some(0),
  ).unwrap()[7]
}

///|
test "portable HubSpot Catalog quantities preserve the Core staged extent bound" {
  // Producer -> full receive/secret/metadata composer -> existing Common
  // staged-extent contract. No JS Resource admission, IO or cleanup ACK.
  let limits : @hubspot_catalog.PropertyLimits = {
    max_bytes: 8192,
    max_nodes: 4096,
    max_depth: 32,
    max_properties: 64,
    max_name_units: 4096,
  }
  let initial = hubspot_full_metadata_response_quote(
    @hubspot_catalog.effect_metadata_construction_capacity(0, 9, limits).unwrap(),
  )
  let full = hubspot_full_metadata_response_quote(
    @hubspot_catalog.effect_metadata_construction_capacity(8192, 9, limits).unwrap(),
  )
  let extent = (capacity : @execution.ExecutionCapacity) => {
    prepare_installed_effect_operation_extent("properties", capacity, 17L, true).unwrap()
  }
  let initial_extent = extent(initial)
  let full_extent = extent(full)
  let staged = prepare_installed_effect_staged_extent(
    initial_extent, full_extent,
  ).unwrap()
  assert_eq(staged.operation, "properties")
  assert_eq(staged.transfer_bytes, 17L)
  assert_true(staged.physical_attempt)
  assert_true(staged.maximum is Some(_))
  assert_eq(
    @execution.execution_capacity_retained_bytes(staged.capacity),
    @execution.execution_capacity_retained_bytes(initial),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(staged.capacity),
    @execution.execution_capacity_execution_bytes(initial),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(full) >
    @execution.execution_capacity_execution_bytes(initial),
  )
  assert_true(
    prepare_installed_effect_staged_extent(full_extent, initial_extent)
    is Err(Unsupported),
  )
  // Each dimension remains mandatory, independently of the other full bound.
  let short_r = @execution.execution_capacity(
    @execution.execution_capacity_retained_bytes(initial) - 1L,
    @execution.execution_capacity_execution_bytes(full),
  ).unwrap()
  let short_e = @execution.execution_capacity(
    @execution.execution_capacity_retained_bytes(initial),
    @execution.execution_capacity_execution_bytes(initial) - 1L,
  ).unwrap()
  for short in [short_r, short_e] {
    assert_true(
      prepare_installed_effect_staged_extent(initial_extent, extent(short))
      is Err(Unsupported),
    )
  }
}
