///|
// Explicit constructor DATA only. These tests issue no Request, grant or Run.
fn confirmation_recipe_profile(
  count : Int,
) -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
] {
  Array::make(
    count,
    (
      @execution.execution_capacity(16L, 32L).unwrap(),
      None,
      Some({ max_input_bytes: 128, max_nodes: 8, max_depth: 4, }),
    ),
  )
}

///|
fn confirmation_recipe_capacities(
  count : Int,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  installed_standard_create_request_recipe_capacities(
    Some(confirmation_recipe_profile(count)),
    4096,
    128,
    16,
    1024,
    32,
    8,
    2048,
    4096,
    2048,
    4096,
    false,
    64,
    7,
    256,
    4096,
    128,
    16,
    0L,
  )
}

///|
test "confirmed CREATE recipe forwards all seven native roles and keeps distinct physical and finalization quantities" {
  let old = confirmation_recipe_capacities(4).unwrap()
  let confirmed = confirmation_recipe_capacities(7).unwrap()
  assert_eq(old.length(), 6)
  assert_eq(confirmed.length(), 8)
  for index in [0, 1, 2, 3, 5] {
    assert_eq(
      @execution.execution_capacity_retained_bytes(confirmed[index]),
      @execution.execution_capacity_retained_bytes(old[index]),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(confirmed[index]),
      @execution.execution_capacity_execution_bytes(old[index]),
    )
  }
  assert_true(
    @execution.execution_capacity_retained_bytes(confirmed[4]) >
    @execution.execution_capacity_retained_bytes(old[4]),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(confirmed[6]) >
    @execution.execution_capacity_retained_bytes(confirmed[2]),
  )
  assert_eq(
    @execution.execution_capacity_retained_bytes(confirmed[7]),
    @execution.execution_capacity_retained_bytes(confirmed[5]),
  )
}

///|
test "confirmed CREATE recipe keeps absent and incomplete native inventories refused" {
  assert_true(
    installed_standard_create_constructor_capacities(None) is Err(Unsupported),
  )
  for count in [0, 1, 3, 5, 6, 8] {
    assert_true(confirmation_recipe_capacities(count) is Err(Unsupported))
  }
}

///|
test "standard read request scratch belongs to the shared control while each physical child keeps its retained output" {
  for count in [4, 7] {
    let profile = confirmation_recipe_profile(count)
    let quote = (
      original : Array[
        (
          @execution.ExecutionCapacity,
          @source.ParseLimits?,
          @source.ParseLimits?,
        ),
      ],
    ) => {
      installed_standard_create_request_recipe_capacities(
        Some(original),
        4096,
        128,
        16,
        1024,
        32,
        8,
        2048,
        4096,
        2048,
        4096,
        false,
        64,
        7,
        256,
        4096,
        128,
        16,
        0L,
      ).unwrap()
    }
    let baseline = quote(profile)
    let baseline_workspace = @execution.execution_capacity_execution_bytes(
        baseline[4],
      ) -
      @execution.execution_capacity_retained_bytes(baseline[4])
    let request_workspace = baseline_workspace + 100L
    profile[1] = (
      @execution.execution_capacity(16L, 16L + request_workspace).unwrap(),
      None,
      profile[1].2,
    )
    if count == 7 {
      profile[4] = (
        @execution.execution_capacity(16L, 26L + request_workspace).unwrap(),
        None,
        profile[4].2,
      )
    }
    let selected = quote(profile)
    let constructors = installed_standard_create_constructor_capacities(
      Some(profile),
    ).unwrap()
    let mut expected_workspace = Int64::max(
      baseline_workspace,
      @execution.execution_capacity_execution_bytes(constructors[1]) -
      @execution.execution_capacity_retained_bytes(constructors[1]),
    )
    if count == 7 {
      expected_workspace = Int64::max(
        expected_workspace,
        @execution.execution_capacity_execution_bytes(constructors[4]) -
        @execution.execution_capacity_retained_bytes(constructors[4]),
      )
    }
    assert_eq(
      @execution.execution_capacity_retained_bytes(selected[4]),
      @execution.execution_capacity_retained_bytes(baseline[4]),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(selected[4]),
      @execution.execution_capacity_retained_bytes(selected[4]) +
      expected_workspace,
    )
    let physical_slots = if count == 7 { [5, 7] } else { [5] }
    for slot in physical_slots {
      assert_eq(
        @execution.execution_capacity_retained_bytes(selected[slot]),
        @execution.execution_capacity_retained_bytes(baseline[slot]),
      )
      assert_eq(
        @execution.execution_capacity_execution_bytes(selected[slot]),
        @execution.execution_capacity_execution_bytes(baseline[slot]),
      )
    }
  }
}

///|
test "standard CREATE initially retains codec limits and text without a future Host Preview forest" {
  let initial = confirmation_recipe_capacities(7).unwrap()
  let full = installed_standard_recipe_capacities(
    Some(confirmation_recipe_profile(7)),
    None,
    4096,
    128,
    16,
    1024,
    32,
    8,
    2048,
    4096,
    2048,
    4096,
    false,
    64,
    7,
    256,
    4096,
    128,
    16,
    0L,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(initial[0]) <
    @execution.execution_capacity_retained_bytes(full[0]),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(initial[0]) <
    @execution.execution_capacity_execution_bytes(full[0]),
  )
  for slot in 1..<8 {
    assert_eq(
      @execution.execution_capacity_retained_bytes(initial[slot]),
      @execution.execution_capacity_retained_bytes(full[slot]),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(initial[slot]),
      @execution.execution_capacity_execution_bytes(full[slot]),
    )
  }
  let extent = prepare_installed_effect_host_input_capture_recipe_extent(
    "create",
    [initial[0], initial[1]],
    4096,
    128,
    16,
  ).unwrap()
  assert_true(extent.checked_effect_id_capacity is None)
  let bounds = extent.host_input_limits.unwrap()
  assert_eq(bounds.max_input_bytes, 4096)
  assert_eq(bounds.max_nodes, 128)
  assert_eq(bounds.max_depth, 16)
  assert_true(physical_equal(extent.capacity, initial[0]))
  assert_true(physical_equal(extent.checked_row_capacity.unwrap(), initial[1]))
  for count in [0, 1, 3, 4, 5, 7, 8] {
    assert_true(
      prepare_installed_effect_host_input_capture_recipe_extent(
        "create",
        Array::make(count, initial[0]),
        4096,
        128,
        16,
      )
      is Err(Unsupported),
    )
  }
}
