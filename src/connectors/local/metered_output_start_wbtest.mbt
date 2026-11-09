///|
test "metered output startup follows original default selection and preserves injected fallback" {
  let (sequence, _, _) = chain_lifetime_fixture(cross_join_lifetime_body())
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let starts = Ref(0)
  let unrelated = managed_provider(_ => false, _ => None, (_, _, _, _, _) => {
    starts.val += 1
    Err(@connector.InvalidLimits)
  })
  let original = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
    managed_providers=[unrelated],
  ).unwrap()
  let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
  let metered = local_module_metered_output_start_capacity(
    original, 0, sequence,
  ).unwrap()
  assert_true(metered.retained_bytes < full.retained_bytes)
  assert_true(metered.execution_bytes < full.execution_bytes)
  let replacement = managed_provider(_ => true, _ => Some(full), (_, _, _, _, _) => {
    starts.val += 1
    Err(@connector.InvalidLimits)
  })
  let injected = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
    managed_providers=[replacement],
  ).unwrap()
  assert_true(
    local_module_metered_output_start_capacity(injected, 0, sequence) is None,
  )
  let fallback = local_module_capacity_for_sequence(injected, 0, sequence).unwrap()
  assert_eq(
    (fallback.retained_bytes, fallback.execution_bytes),
    (full.retained_bytes, full.execution_bytes),
  )
  assert_eq(starts.val, 0)
  @connector.close_capability_registry(registry)
}

///|
test "singleton row startup uses only its original default provider proof" {
  let (chain, _, _) = chain_lifetime_fixture(cross_join_lifetime_body())
  let mut single : @execution.GeneratedSequence? = None
  for position in 0..<@execution.generated_sequence_step_count(chain) {
    if @execution.generated_sequence_step_at(chain, position)
      is Some(@lower.RowStep(_)) {
      single = @execution.select_generated_sequence_step(
        chain,
        @execution.generated_sequence_step_index_at(chain, position).unwrap(),
      )
      break
    }
  }
  let sequence = single.unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let original = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
  ).unwrap()
  let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
  let metered = local_module_metered_output_start_capacity(
    original, 0, sequence,
  ).unwrap()
  assert_true(metered.retained_bytes <= full.retained_bytes)
  assert_true(metered.execution_bytes < full.execution_bytes)
  let starts = Ref(0)
  let replacement = managed_provider(_ => true, _ => Some(full), (_, _, _, _, _) => {
    starts.val += 1
    Err(@connector.InvalidLimits)
  })
  let injected = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
    managed_providers=[replacement],
  ).unwrap()
  assert_true(
    local_module_metered_output_start_capacity(injected, 0, sequence) is None,
  )
  let preserved = local_module_capacity_for_sequence(injected, 0, sequence).unwrap()
  assert_eq(
    (preserved.retained_bytes, preserved.execution_bytes),
    (full.retained_bytes, full.execution_bytes),
  )
  assert_eq(starts.val, 0)
  @connector.close_capability_registry(registry)
}

///|
test "singleton Append startup uses its bounded constructor and preserves injected fallback" {
  let (chain, _, _) = chain_lifetime_fixture(chain_lifetime_append_body())
  let mut single : @execution.GeneratedSequence? = None
  for position in 0..<@execution.generated_sequence_step_count(chain) {
    if @execution.generated_sequence_step_at(chain, position)
      is Some(@lower.AppendStep(_)) {
      single = @execution.select_generated_sequence_step(
        chain,
        @execution.generated_sequence_step_index_at(chain, position).unwrap(),
      )
      break
    }
  }
  let sequence = single.unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let original = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
  ).unwrap()
  let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
  let metered = local_module_metered_output_start_capacity(
    original, 0, sequence,
  ).unwrap()
  assert_true(metered.retained_bytes <= full.retained_bytes)
  assert_true(metered.execution_bytes < full.execution_bytes)
  let limits = chain_lifetime_limits()
  let measure = chain_lifetime_measurement()
  let bounded = @execution.generated_bounded_sequence_capacity(
    sequence, limits, measure,
  ).unwrap()
  let more_input = {
    ..limits,
    rows: {
      ..limits.rows,
      input_values: {
        ..limits.rows.input_values,
        max_nodes: limits.rows.input_values.max_nodes + 1,
        max_text_bytes: limits.rows.input_values.max_text_bytes + 1,
      },
    },
  }
  let same = @execution.generated_bounded_sequence_capacity(
    sequence, more_input, measure,
  ).unwrap()
  assert_eq(
    (bounded.retained_bytes, bounded.execution_bytes),
    (same.retained_bytes, same.execution_bytes),
  )
  let generic = @execution.generated_sequence_capacity(
    sequence, limits, measure,
  ).unwrap()
  let generic_more = @execution.generated_sequence_capacity(
    sequence, more_input, measure,
  ).unwrap()
  assert_eq(generic_more.execution_bytes - generic.execution_bytes, 264L)
  let starts = Ref(0)
  let replacement = managed_provider(_ => true, _ => Some(full), (_, _, _, _, _) => {
    starts.val += 1
    Err(@connector.InvalidLimits)
  })
  let injected = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    chain_lifetime_limits(),
    chain_lifetime_measurement(),
    100000,
    1,
    managed_providers=[replacement],
  ).unwrap()
  assert_true(
    local_module_metered_output_start_capacity(injected, 0, sequence) is None,
  )
  let preserved = local_module_capacity_for_sequence(injected, 0, sequence).unwrap()
  assert_eq(
    (preserved.retained_bytes, preserved.execution_bytes),
    (full.retained_bytes, full.execution_bytes),
  )
  assert_eq(starts.val, 0)
  @connector.close_capability_registry(registry)
}

///|
test "singleton Set startup keeps recursive and injected providers fully prepaid" {
  for
    (contract, literal, primitive) in [
      ("{\"type\":\"number\",\"nullable\":false}", "1", true),
      ("{\"type\":\"boolean\",\"nullable\":false}", "true", true),
      ("{\"type\":\"string\",\"nullable\":false}", "\"text\"", false),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "[1,2]", false,
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"number\",\"nullable\":false}}}",
        "{\"x\":1}", false,
      ),
    ] {
    let (chain, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"id\":" +
      contract +
      "},\"rows\":[{\"id\":" +
      literal +
      "}]},\"as\":\"value\"},{\"from\":\"value\",\"intersect\":{\"with\":\"value\",\"duplicates\":\"distinct\"}}]",
    )
    let selected = @execution.select_generated_sequence_step(
      chain,
      @execution.generated_sequence_step_index_at(chain, 1).unwrap(),
    ).unwrap()
    let registry = @connector.prepare_capability_registry(
      [
        {
          name: "local",
          acquisition: false,
          fixed_compute: true,
          effect: false,
        },
      ],
      1,
      100,
    ).unwrap()
    let registration = @connector.capability_registration_at(registry, 0).unwrap()
    let original = prepare_local_compute_module(
      registry,
      registration,
      [selected],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(original, 0, selected).unwrap()
    let generic = @execution.generated_sequence_capacity(
      selected,
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
    ).unwrap()
    let metered = local_module_metered_output_start_capacity(
      original, 0, selected,
    )
    if primitive {
      assert_true(full.execution_bytes < generic.execution_bytes)
      assert_true(
        metered is Some(value) && value.execution_bytes < full.execution_bytes,
      )
    } else {
      assert_true(metered is None)
      assert_eq(
        (full.retained_bytes, full.execution_bytes),
        (generic.retained_bytes, generic.execution_bytes),
      )
    }
    let starts = Ref(0)
    let replacement = managed_provider(_ => true, _ => Some(generic), (
      _,
      _,
      _,
      _,
      _,
    ) => {
      starts.val += 1
      Err(@connector.InvalidLimits)
    })
    let injected = prepare_local_compute_module(
      registry,
      registration,
      [selected],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
      managed_providers=[replacement],
    ).unwrap()
    assert_true(
      local_module_metered_output_start_capacity(injected, 0, selected) is None,
    )
    let fallback = local_module_capacity_for_sequence(injected, 0, selected).unwrap()
    assert_eq(
      (fallback.retained_bytes, fallback.execution_bytes),
      (generic.retained_bytes, generic.execution_bytes),
    )
    assert_eq(starts.val, 0)
    @connector.close_capability_registry(registry)
  }
}

///|
test "singleton Join startup keeps recursive and injected providers fully prepaid" {
  for
    (contract, literal, primitive) in [
      ("{\"type\":\"number\",\"nullable\":false}", "1", true),
      ("{\"type\":\"boolean\",\"nullable\":false}", "true", true),
      ("{\"type\":\"string\",\"nullable\":false}", "\"text\"", false),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "[1,2]", false,
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"number\",\"nullable\":false}}}",
        "{\"x\":1}", false,
      ),
    ] {
    let (chain, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":" +
      contract +
      "},\"rows\":[{\"id\":1,\"payload\":" +
      literal +
      "}]},\"as\":\"value\"},{\"from\":\"value\",\"join\":{\"with\":\"value\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\",\"payload\":\"right.payload\"}}}]",
    )
    let selected = @execution.select_generated_sequence_step(
      chain,
      @execution.generated_sequence_step_index_at(chain, 1).unwrap(),
    ).unwrap()
    let registry = @connector.prepare_capability_registry(
      [
        {
          name: "local",
          acquisition: false,
          fixed_compute: true,
          effect: false,
        },
      ],
      1,
      100,
    ).unwrap()
    let registration = @connector.capability_registration_at(registry, 0).unwrap()
    let original = prepare_local_compute_module(
      registry,
      registration,
      [selected],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(original, 0, selected).unwrap()
    let generic = @execution.generated_sequence_capacity(
      selected,
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
    ).unwrap()
    let metered = local_module_metered_output_start_capacity(
      original, 0, selected,
    )
    if primitive {
      assert_true(full.execution_bytes < generic.execution_bytes)
      assert_true(
        metered is Some(value) && value.execution_bytes < full.execution_bytes,
      )
    } else {
      assert_true(metered is None)
      assert_eq(
        (full.retained_bytes, full.execution_bytes),
        (generic.retained_bytes, generic.execution_bytes),
      )
    }
    let starts = Ref(0)
    let replacement = managed_provider(_ => true, _ => Some(generic), (
      _,
      _,
      _,
      _,
      _,
    ) => {
      starts.val += 1
      Err(@connector.InvalidLimits)
    })
    let injected = prepare_local_compute_module(
      registry,
      registration,
      [selected],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
      managed_providers=[replacement],
    ).unwrap()
    assert_true(
      local_module_metered_output_start_capacity(injected, 0, selected) is None,
    )
    let fallback = local_module_capacity_for_sequence(injected, 0, selected).unwrap()
    assert_eq(
      (fallback.retained_bytes, fallback.execution_bytes),
      (generic.retained_bytes, generic.execution_bytes),
    )
    assert_eq(starts.val, 0)
    @connector.close_capability_registry(registry)
  }
}

///|
test "singleton SnapshotMap meters recursive output only with prepaid construction and immediate input" {
  for
    (contract, literal, primitive) in [
      ("{\"type\":\"number\",\"nullable\":false}", "1", true),
      ("{\"type\":\"boolean\",\"nullable\":false}", "true", true),
      ("{\"type\":\"string\",\"nullable\":false}", "\"text\"", false),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "[1,2]", false,
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"number\",\"nullable\":false}}}",
        "{\"x\":1}", false,
      ),
    ] {
    let (chain, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"payload\":" +
      contract +
      "},\"rows\":[{\"payload\":" +
      literal +
      "}]},\"as\":\"value\"},{\"from\":\"value\",\"derive\":{\"wrapped\":{\"object\":{\"item\":{\"field\":\"payload\"}}}}}]",
    )
    let selected = @execution.select_generated_sequence_step(
      chain,
      @execution.generated_sequence_step_index_at(chain, 1).unwrap(),
    ).unwrap()
    let registry = @connector.prepare_capability_registry(
      [
        {
          name: "local",
          acquisition: false,
          fixed_compute: true,
          effect: false,
        },
      ],
      1,
      100,
    ).unwrap()
    let registration = @connector.capability_registration_at(registry, 0).unwrap()
    let original = prepare_local_compute_module(
      registry,
      registration,
      [selected],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(original, 0, selected).unwrap()
    let generic = @execution.generated_sequence_capacity(
      selected,
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
    ).unwrap()
    let metered = local_module_metered_output_start_capacity(
      original, 0, selected,
    )
    if primitive {
      assert_true(full.execution_bytes < generic.execution_bytes)
      assert_true(
        metered is Some(value) && value.execution_bytes < full.execution_bytes,
      )
    } else {
      assert_true(
        metered is None ||
        metered.map(value => value.retained_bytes) == Some(full.retained_bytes),
      )
    }
    let more_output = @execution.generated_bounded_sequence_capacity(
      selected,
      {
        ..chain_lifetime_limits(),
        rows: {
          ..chain_lifetime_limits().rows,
          output_values: {
            ..chain_lifetime_limits().rows.output_values,
            max_nodes: chain_lifetime_limits().rows.output_values.max_nodes + 1,
          },
        },
      },
      chain_lifetime_measurement(),
    ).unwrap()
    // Recursive output construction is not removed from the scratch recipe.
    assert_eq(more_output.retained_bytes - full.retained_bytes, 256L)
    assert_eq(more_output.execution_bytes - full.execution_bytes, 256L)
    let starts = Ref(0)
    let replacement = managed_provider(_ => true, _ => Some(generic), (
      _,
      _,
      _,
      _,
      _,
    ) => {
      starts.val += 1
      Err(@connector.InvalidLimits)
    })
    let injected = prepare_local_compute_module(
      registry,
      registration,
      [selected],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
      managed_providers=[replacement],
    ).unwrap()
    assert_true(
      local_module_metered_output_start_capacity(injected, 0, selected) is None,
    )
    let fallback = local_module_capacity_for_sequence(injected, 0, selected).unwrap()
    assert_eq(
      (fallback.retained_bytes, fallback.execution_bytes),
      (generic.retained_bytes, generic.execution_bytes),
    )
    assert_eq(starts.val, 0)
    @connector.close_capability_registry(registry)
  }
}

///|
test "metered primitive DISTINCT borrows input cells and preserves injected fallback" {
  let (chain, _, _) = chain_lifetime_fixture(
    "[{\"from\":\"source\",\"distinct\":[\"id\"]}]",
  )
  let sequence = @execution.select_generated_sequence_step(
    chain,
    @execution.generated_sequence_step_index_at(chain, 0).unwrap(),
  ).unwrap()
  let limits = chain_lifetime_limits()
  let measurement = chain_lifetime_measurement()
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let original = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    limits,
    measurement,
    100000,
    1,
  ).unwrap()
  let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
  let start = local_module_metered_output_start_capacity(original, 0, sequence).unwrap()
  assert_true(start.retained_bytes < full.retained_bytes)
  assert_true(start.execution_bytes < full.execution_bytes)
  let more = {
    ..limits,
    rows: {
      ..limits.rows,
      input_values: {
        ..limits.rows.input_values,
        max_nodes: limits.rows.input_values.max_nodes + 1,
      },
    },
  }
  let borrowed = @execution.generated_bounded_sequence_capacity(
    sequence, limits, measurement,
  ).unwrap()
  let borrowed_more = @execution.generated_bounded_sequence_capacity(
    sequence, more, measurement,
  ).unwrap()
  assert_eq(borrowed_more.execution_bytes, borrowed.execution_bytes)
  let generic = @execution.generated_sequence_capacity(
    sequence, limits, measurement,
  ).unwrap()
  let generic_more = @execution.generated_sequence_capacity(
    sequence, more, measurement,
  ).unwrap()
  assert_eq(generic_more.execution_bytes - generic.execution_bytes, 256L)
  let starts = Ref(0)
  let replacement = managed_provider(_ => true, _ => Some(full), (_, _, _, _, _) => {
    starts.val += 1
    Err(@connector.InvalidLimits)
  })
  let injected = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    limits,
    measurement,
    100000,
    1,
    managed_providers=[replacement],
  ).unwrap()
  assert_true(
    local_module_metered_output_start_capacity(injected, 0, sequence) is None,
  )
  let fallback = local_module_capacity_for_sequence(injected, 0, sequence).unwrap()
  assert_eq(
    (fallback.retained_bytes, fallback.execution_bytes),
    (full.retained_bytes, full.execution_bytes),
  )
  assert_eq(starts.val, 0)
  @connector.close_capability_registry(registry)
}

///|
test "scalar grouped count selects its bounded provider without metering output or injected capacity" {
  let (chain, _, _) = chain_lifetime_fixture(
    "[{\"from\":\"source\",\"group\":{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
  )
  let sequence = @execution.select_generated_sequence_step(
    chain,
    @execution.generated_sequence_step_index_at(chain, 0).unwrap(),
  ).unwrap()
  let limits = chain_lifetime_limits()
  let measurement = chain_lifetime_measurement()
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let original = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    limits,
    measurement,
    100000,
    1,
  ).unwrap()
  let capacity = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
  let bounded = @execution.generated_bounded_sequence_capacity(
    sequence, limits, measurement,
  ).unwrap()
  let generic = @execution.generated_sequence_capacity(
    sequence, limits, measurement,
  ).unwrap()
  assert_eq(
    (capacity.retained_bytes, capacity.execution_bytes),
    (bounded.retained_bytes, bounded.execution_bytes),
  )
  assert_true(capacity.execution_bytes < generic.execution_bytes)
  // GROUP keeps all persistent output prepaid, not the row commit-growth path.
  assert_true(
    local_module_metered_output_start_capacity(original, 0, sequence) is None,
  )
  let starts = Ref(0)
  let replacement = managed_provider(_ => true, _ => Some(generic), (
    _,
    _,
    _,
    _,
    _,
  ) => {
    starts.val += 1
    Err(@connector.InvalidLimits)
  })
  let injected = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    limits,
    measurement,
    100000,
    1,
    managed_providers=[replacement],
  ).unwrap()
  let fallback = local_module_capacity_for_sequence(injected, 0, sequence).unwrap()
  assert_eq(
    (fallback.retained_bytes, fallback.execution_bytes),
    (generic.retained_bytes, generic.execution_bytes),
  )
  assert_true(
    local_module_metered_output_start_capacity(injected, 0, sequence) is None,
  )
  assert_eq(starts.val, 0)
  @connector.close_capability_registry(registry)
}

///|
test "direct field count preserves original provider selection and injected capacity" {
  let (chain, _, _) = chain_lifetime_fixture(
    "[{\"from\":\"source\",\"group\":{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\",\"field\":\"id\"}}}}]",
  )
  let sequence = @execution.select_generated_sequence_step(
    chain,
    @execution.generated_sequence_step_index_at(chain, 0).unwrap(),
  ).unwrap()
  let limits = chain_lifetime_limits()
  let measurement = chain_lifetime_measurement()
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let original = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    limits,
    measurement,
    100000,
    1,
  ).unwrap()
  let capacity = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
  let bounded = @execution.generated_bounded_sequence_capacity(
    sequence, limits, measurement,
  ).unwrap()
  let generic = @execution.generated_sequence_capacity(
    sequence, limits, measurement,
  ).unwrap()
  assert_eq(
    (capacity.retained_bytes, capacity.execution_bytes),
    (bounded.retained_bytes, bounded.execution_bytes),
  )
  assert_true(capacity.execution_bytes < generic.execution_bytes)
  // GROUP keeps all persistent output prepaid, not the row commit-growth path.
  assert_true(
    local_module_metered_output_start_capacity(original, 0, sequence) is None,
  )
  let starts = Ref(0)
  let replacement = managed_provider(_ => true, _ => Some(generic), (
    _,
    _,
    _,
    _,
    _,
  ) => {
    starts.val += 1
    Err(@connector.InvalidLimits)
  })
  let injected = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    limits,
    measurement,
    100000,
    1,
    managed_providers=[replacement],
  ).unwrap()
  let fallback = local_module_capacity_for_sequence(injected, 0, sequence).unwrap()
  assert_eq(
    (fallback.retained_bytes, fallback.execution_bytes),
    (generic.retained_bytes, generic.execution_bytes),
  )
  assert_true(
    local_module_metered_output_start_capacity(injected, 0, sequence) is None,
  )
  assert_eq(starts.val, 0)
  @connector.close_capability_registry(registry)
}

///|
test "singleton CROSS JOIN borrows original inputs and refuses injected constructor credit" {
  let (chain, _, _) = chain_lifetime_fixture(cross_join_lifetime_body())
  let mut single : @execution.GeneratedSequence? = None
  for index in 0..<@execution.generated_sequence_step_count(chain) {
    if @execution.generated_sequence_step_at(chain, index)
      is Some(@lower.CrossJoinStep(_)) {
      single = @execution.select_generated_sequence_step(
        chain,
        @execution.generated_sequence_step_index_at(chain, index).unwrap(),
      )
      break
    }
  }
  let sequence = single.unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let limits = chain_lifetime_limits()
  let measure = chain_lifetime_measurement()
  let original = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    limits,
    measure,
    100000,
    1,
  ).unwrap()
  let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
  let start = local_module_metered_output_start_capacity(original, 0, sequence).unwrap()
  assert_true(start.retained_bytes < full.retained_bytes)
  assert_true(start.execution_bytes < full.execution_bytes)
  let more = @execution.generated_bounded_sequence_capacity(
    sequence,
    {
      ..limits,
      rows: {
        ..limits.rows,
        input_values: {
          ..limits.rows.input_values,
          max_nodes: limits.rows.input_values.max_nodes + 1,
          max_text_bytes: limits.rows.input_values.max_text_bytes + 1,
        },
      },
    },
    { ..measure, max_nodes: 2830000, max_bytes: 10000000, },
  ).unwrap()
  assert_eq(more.retained_bytes, full.retained_bytes)
  assert_eq(more.execution_bytes, full.execution_bytes)
  let generic = @execution.generated_sequence_capacity(
    sequence, limits, measure,
  ).unwrap()
  assert_true(generic.execution_bytes > full.execution_bytes)
  let injected = prepare_local_compute_module(
    registry,
    registration,
    [sequence],
    limits,
    measure,
    100000,
    1,
    managed_providers=[
      managed_provider(_ => true, _ => Some(generic), (_, _, _, _, _) => {
        Err(@connector.InvalidLimits)
      }),
    ],
  ).unwrap()
  assert_true(
    local_module_metered_output_start_capacity(injected, 0, sequence) is None,
  )
  let kept = local_module_capacity_for_sequence(injected, 0, sequence).unwrap()
  assert_eq(kept.retained_bytes, generic.retained_bytes)
  assert_eq(kept.execution_bytes, generic.execution_bytes)
  @connector.close_capability_registry(registry)
}
