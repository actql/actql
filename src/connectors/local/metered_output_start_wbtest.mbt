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
  let same = local_module_metered_output_start_capacity(original, 0, sequence).unwrap()
  assert_true(
    physical_equal(metered, same),
    msg="reuse SAME prepared startup capacity, do not reconstruct its recipe",
  )
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
test "singleton Set borrows scalar Text without metering and preserves recursive and injected fallbacks" {
  for
    (contract, literal, metered_scalar, borrowed_scalar) in [
      ("{\"type\":\"number\",\"nullable\":false}", "1", true, true),
      ("{\"type\":\"boolean\",\"nullable\":false}", "true", true, true),
      ("{\"type\":\"string\",\"nullable\":false}", "\"text\"", false, true),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "[1,2]", false, false,
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"number\",\"nullable\":false}}}",
        "{\"x\":1}", false, false,
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
    if metered_scalar {
      assert_true(full.execution_bytes < generic.execution_bytes)
      assert_true(
        metered is Some(value) && value.execution_bytes < full.execution_bytes,
      )
    } else {
      assert_true(metered is None)
      if borrowed_scalar {
        // The fixed Set constructor borrows original flat Text inputs, but
        // keeps its complete output DATA prepaid. It does not opt Text into
        // the Number/Boolean output-growth protocol or copy input forests.
        let output = chain_lifetime_limits().rows.output_values
        let retained_output = @execution.execution_capacity_inventory_bytes([
          { unit: @execution.CursorRootSlots, count: 3L, copies: 1, },
          {
            unit: @execution.ValueNodeSlots,
            count: output.max_nodes.to_int64(),
            copies: 1,
          },
          {
            unit: @execution.DecodedTextBytes,
            count: output.max_text_bytes.to_int64(),
            copies: 1,
          },
        ]).unwrap()
        assert_eq(full.retained_bytes, retained_output)
        assert_true(full.execution_bytes < generic.execution_bytes)
      } else {
        assert_eq(
          (full.retained_bytes, full.execution_bytes),
          (generic.retained_bytes, generic.execution_bytes),
        )
      }
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
test "singleton Join borrows carried values with immediate keys and preserves injected fallback" {
  for
    (kind, contract, literal) in [
      ("inner", "{\"type\":\"number\",\"nullable\":false}", "1"),
      ("inner", "{\"type\":\"boolean\",\"nullable\":false}", "true"),
      ("inner", "{\"type\":\"string\",\"nullable\":false}", "\"text\""),
      (
        "inner", "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "[1,2]",
      ),
      (
        "inner", "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"number\",\"nullable\":false}}}",
        "{\"x\":1}",
      ),
      ("left", "{\"type\":\"string\",\"nullable\":false}", "\"text\""),
    ] {
    let (chain, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":" +
      contract +
      "},\"rows\":[{\"id\":1,\"payload\":" +
      literal +
      "}]},\"as\":\"value\"},{\"from\":\"value\",\"join\":{\"with\":\"value\",\"kind\":\"" +
      kind +
      "\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\",\"payload\":\"right.payload\"}}}]",
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
    // The comparison key is still original numeric id. Text/recursive
    // payload is carried unchanged and independently funded before commit.
    assert_true(full.execution_bytes < generic.execution_bytes)
    assert_true(
      metered is Some(value) && value.execution_bytes < full.execution_bytes,
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
test "scalar grouped count meters original output without replacing its bounded or injected capacity" {
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
  // The same bounded COUNT now funds complete persistent rows before commit.
  // Its full provider envelope above remains unchanged, while only default
  // startup can defer this DATA to the original task's growth attachment.
  let startup = local_module_metered_output_start_capacity(
    original, 0, sequence,
  ).unwrap()
  assert_true(startup.retained_bytes < capacity.retained_bytes)
  assert_true(startup.execution_bytes < capacity.execution_bytes)
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
  // The same bounded COUNT now funds complete persistent rows before commit.
  // Its full provider envelope above remains unchanged, while only default
  // startup can defer this DATA to the original task's growth attachment.
  let startup = local_module_metered_output_start_capacity(
    original, 0, sequence,
  ).unwrap()
  assert_true(startup.retained_bytes < capacity.retained_bytes)
  assert_true(startup.execution_bytes < capacity.execution_bytes)
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

///|
test "recursive carried Join funding borrows bounded text keys and preserves nullable and outer fallback" {
  for
    (kind, contract, literal, borrowed) in [
      ("inner", "{\"type\":\"number\",\"nullable\":false}", "1", true),
      ("inner", "{\"type\":\"boolean\",\"nullable\":false}", "true", true),
      ("inner", "{\"type\":\"string\",\"nullable\":false}", "\"key\"", true),
      ("inner", "{\"type\":\"string\",\"nullable\":true}", "\"key\"", false),
      ("left", "{\"type\":\"string\",\"nullable\":false}", "\"key\"", false),
      ("left", "{\"type\":\"number\",\"nullable\":false}", "1", false),
    ] {
    let (chain, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"id\":" +
      contract +
      ",\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}},\"rows\":[{\"id\":" +
      literal +
      ",\"payload\":[1,2]}]},\"as\":\"value\"},{\"from\":\"value\",\"join\":{\"with\":\"value\",\"kind\":\"" +
      kind +
      "\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\",\"payload\":\"right.payload\"}}}]",
    )
    let sequence = @execution.select_generated_sequence_step(
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
      [sequence],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
    let generic = @execution.generated_sequence_capacity(
      sequence,
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
    ).unwrap()
    let start = local_module_metered_output_start_capacity(
      original, 0, sequence,
    )
    if borrowed {
      assert_true(full.execution_bytes < generic.execution_bytes)
      assert_true(
        start is Some(value) && value.execution_bytes < full.execution_bytes,
      )
    } else {
      assert_eq(
        (full.retained_bytes, full.execution_bytes),
        (generic.retained_bytes, generic.execution_bytes),
      )
      assert_true(start is None)
    }
    @connector.close_capability_registry(registry)
  }
}

///|
test "chained Join output funding retains recursive and injected provider fallbacks" {
  for
    (contract, literal, immediate) in [
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
    let (whole, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":" +
      contract +
      "},\"rows\":[{\"id\":1,\"payload\":" +
      literal +
      "}]},\"as\":\"value\"},{\"from\":\"value\",\"join\":{\"with\":\"value\",\"kind\":\"right\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"right.id\",\"payload\":\"left.payload\"}},\"as\":\"joined\"},{\"from\":\"joined\",\"select\":[\"id\",\"payload\"]}]",
    )
    let sequence = @execution.select_generated_sequence_range(whole, 1, 2).unwrap()
    assert_eq(@execution.generated_sequence_step_count(sequence), 2)
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
      [sequence],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
    let start = local_module_metered_output_start_capacity(
      original, 0, sequence,
    )
    if immediate {
      assert_true(
        start is Some(value) &&
        value.retained_bytes < full.retained_bytes &&
        value.execution_bytes < full.execution_bytes,
      )
    } else {
      assert_true(start is None)
    }
    let starts = Ref(0)
    let replacement = managed_provider(_ => true, _ => Some(full), (
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
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
      managed_providers=[replacement],
    ).unwrap()
    assert_true(
      local_module_metered_output_start_capacity(injected, 0, sequence) is None,
    )
    let kept = local_module_capacity_for_sequence(injected, 0, sequence).unwrap()
    assert_eq(
      (kept.retained_bytes, kept.execution_bytes),
      (full.retained_bytes, full.execution_bytes),
    )
    assert_eq(starts.val, 0)
    @connector.close_capability_registry(registry)
  }
}

///|
test "Count chains borrow Text but retain recursive and injected provider funding" {
  for
    (contract, literal, immediate) in [
      ("{\"type\":\"number\",\"nullable\":false}", "1", true),
      ("{\"type\":\"boolean\",\"nullable\":false}", "true", true),
      ("{\"type\":\"string\",\"nullable\":false}", "\"text\"", true),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "[1,2]", false,
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"number\",\"nullable\":false}}}",
        "{\"x\":1}", false,
      ),
    ] {
    let (whole, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":" +
      contract +
      "},\"rows\":[{\"id\":1,\"payload\":" +
      literal +
      "}]},\"as\":\"value\"},{\"from\":\"value\",\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}},\"as\":\"counted\"},{\"from\":\"counted\",\"select\":[\"n\"]}]",
    )
    let sequence = @execution.select_generated_sequence_range(whole, 1, 2).unwrap()
    assert_eq(@execution.generated_sequence_step_count(sequence), 2)
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
      [sequence],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
    let start = local_module_metered_output_start_capacity(
      original, 0, sequence,
    )
    if immediate {
      assert_true(
        start is Some(value) &&
        value.retained_bytes < full.retained_bytes &&
        value.execution_bytes < full.execution_bytes,
      )
    } else {
      assert_true(start is None)
    }
    let starts = Ref(0)
    let replacement = managed_provider(_ => true, _ => Some(full), (
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
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
      managed_providers=[replacement],
    ).unwrap()
    assert_true(
      local_module_metered_output_start_capacity(injected, 0, sequence) is None,
    )
    let kept = local_module_capacity_for_sequence(injected, 0, sequence).unwrap()
    assert_eq(
      (kept.retained_bytes, kept.execution_bytes),
      (full.retained_bytes, full.execution_bytes),
    )
    assert_eq(starts.val, 0)
    @connector.close_capability_registry(registry)
  }
}

///|
test "window chain startup uses original row funding and preserves injected full capacity" {
  let (sequence, _, _) = chain_lifetime_fixture(
    "[{\"from\":\"source\",\"row_window\":{\"kind\":\"fixed\",\"time\":\"id\",\"size\":10},\"as\":\"windowed\"},{\"from\":\"windowed\",\"select\":[\"id\",\"window_start\",\"window_end\"]}]",
  )
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
  let startup = local_module_metered_output_start_capacity(
    original, 0, sequence,
  ).unwrap()
  assert_true(startup.retained_bytes < full.retained_bytes)
  assert_true(startup.execution_bytes < full.execution_bytes)
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
  let fallback = local_module_capacity_for_sequence(injected, 0, sequence).unwrap()
  assert_eq(
    (fallback.retained_bytes, fallback.execution_bytes),
    (full.retained_bytes, full.execution_bytes),
  )
  assert_eq(starts.val, 0)
  @connector.close_capability_registry(registry)
}

///|
test "window reductions retain constructing aggregate backing before row funding" {
  for
    (aggregate, borrowed) in [
      ("{\"fn\":\"count\"}", true),
      (
        "{\"fn\":\"sum\",\"expr\":{\"add\":[{\"field\":\"id\"},{\"literal\":1}]},\"filter\":{\"gt\":[{\"field\":\"id\"},{\"literal\":0}]},\"distinct\":true}",
        true,
      ),
      ("{\"fn\":\"count\",\"expr\":{\"literal\":\"text\"}}", false),
      (
        "{\"fn\":\"array_agg\",\"field\":\"id\",\"max_items\":100,\"order_by\":[{\"id\":\"asc\"}]}",
        false,
      ),
    ] {
    let checked = @pipeline.check(
      chain_lifetime_cursor(
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"id\",\"size\":10}},{\"window_group\":{\"by\":[],\"aggregates\":{\"n\":" +
        aggregate +
        "}}}]",
      ),
      [],
      None,
      None,
      {
        max_steps: 100,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    )
    let owner = match checked {
      Ok(value) => chain_lifetime_bind(value)
      Err(issue) => {
        debug_inspect(issue.kind, content="checked window aggregate fixture")
        abort("checked window aggregate fixture refused")
      }
    }
    let whole = chain_lifetime_generated(owner)
    let sequence = @execution.select_generated_sequence_range(whole, 1, 2).unwrap()
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
    let original = prepare_local_compute_module(
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      [sequence],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
    let startup = local_module_metered_output_start_capacity(
      original, 0, sequence,
    ).unwrap()
    if borrowed {
      assert_true(startup.retained_bytes < full.retained_bytes)
    } else {
      // This aggregate constructs its own array before the managed row is
      // committed. Its complete original output backing remains prepaid.
      assert_eq(startup.retained_bytes, full.retained_bytes)
    }
    @connector.close_capability_registry(registry)
  }
}

///|
test "ROW_NUMBER startup keeps nonprimitive other-function and injected providers fully prepaid" {
  for
    (contract, literal, function_name) in [
      ("{\"type\":\"string\",\"nullable\":false}", "\"text\"", "row_number"),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "[1,2]", "row_number",
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"number\",\"nullable\":false}}}",
        "{\"x\":1}", "row_number",
      ),
      ("{\"type\":\"number\",\"nullable\":false}", "1", "rank"),
    ] {
    let (whole, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":" +
      contract +
      "},\"rows\":[{\"id\":1,\"payload\":" +
      literal +
      "}]},\"as\":\"value\"},{\"from\":\"value\",\"analytic\":{\"partition_by\":[],\"order_by\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"functions\":{\"n\":{\"fn\":\"" +
      function_name +
      "\"}}}}]",
    )
    let sequence = @execution.select_generated_sequence_step(
      whole,
      @execution.generated_sequence_step_index_at(whole, 1).unwrap(),
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
      [sequence],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
    let generic = @execution.generated_sequence_capacity(
      sequence,
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
    ).unwrap()
    let borrowed = @execution.generated_sequence_step_at(sequence, 0)
      .map(operation => {
        match operation {
          @lower.RowStep(kernel) =>
            @execution.bounded_analytic_borrows_input(kernel)
          _ => false
        }
      })
      .unwrap_or(false)
    assert_eq(full.retained_bytes, generic.retained_bytes)
    let startup = local_module_metered_output_start_capacity(
      original, 0, sequence,
    )
    if borrowed {
      assert_true(full.execution_bytes <= generic.execution_bytes)
      if startup is Some(value) {
        assert_eq(value.retained_bytes, full.retained_bytes)
        assert_true(value.execution_bytes <= full.execution_bytes)
      }
    } else {
      assert_eq(full.execution_bytes, generic.execution_bytes)
      assert_true(startup is None)
    }
    let starts = Ref(0)
    let replacement = managed_provider(_ => true, _ => Some(full), (
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
}

///|
test "unpivot borrowed cells use original row funding and preserve injected provider capacities" {
  for
    (contract, literal) in [
      ("{\"type\":\"string\",\"nullable\":false}", "\"text\""),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "[1,2]",
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"number\",\"nullable\":false}}}",
        "{\"x\":1}",
      ),
    ] {
    let (whole, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":" +
      contract +
      "},\"rows\":[{\"id\":1,\"payload\":" +
      literal +
      "}]},\"as\":\"value\"},{\"from\":\"value\",\"unpivot\":{\"columns\":[\"id\"],\"keep\":[\"payload\"],\"name_column\":\"label\",\"value_column\":\"number\"}}]",
    )
    let sequence = @execution.select_generated_sequence_step(
      whole,
      @execution.generated_sequence_step_index_at(whole, 1).unwrap(),
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
      [sequence],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
    let generic = @execution.generated_sequence_capacity(
      sequence,
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
    ).unwrap()
    let bounded = @execution.generated_bounded_sequence_capacity(
      sequence,
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
    ).unwrap()
    assert_eq(
      (full.retained_bytes, full.execution_bytes),
      (bounded.retained_bytes, bounded.execution_bytes),
    )
    assert_true(full.retained_bytes <= generic.retained_bytes)
    assert_true(full.execution_bytes < generic.execution_bytes)
    let startup = local_module_metered_output_start_capacity(
      original, 0, sequence,
    ).unwrap()
    assert_true(startup.retained_bytes < full.retained_bytes)
    assert_true(startup.execution_bytes < full.execution_bytes)
    let starts = Ref(0)
    let replacement = managed_provider(_ => true, _ => Some(full), (
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
}

///|
test "numeric pivot borrows Text index keys and preserves recursive aggregate or injected fallback" {
  // resource-case-id: numeric_pivot_start_capacity
  for
    (extra, key, value, aggregate, borrowed) in [
      ("", "id", "amount", "count", true),
      (
        ",\"extra\":{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "id", "amount", "count", false,
      ),
      ("", "status", "amount", "count", true),
      ("", "id", "status", "max", false),
    ] {
    let (whole, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"status\":{\"type\":\"string\",\"nullable\":false},\"amount\":{\"type\":\"number\",\"nullable\":true}" +
      extra +
      "},\"rows\":[]},\"as\":\"value\"},{\"from\":\"value\",\"pivot\":{\"index\":[\"" +
      key +
      "\"],\"column\":\"status\",\"values\":[\"open\"],\"value\":\"" +
      value +
      "\",\"aggregate\":\"" +
      aggregate +
      "\"}}]",
    )
    let sequence = @execution.select_generated_sequence_step(
      whole,
      @execution.generated_sequence_step_index_at(whole, 1).unwrap(),
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
      [sequence],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
    let generic = @execution.generated_sequence_capacity(
      sequence,
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
    ).unwrap()
    let bounded = @execution.generated_bounded_sequence_capacity(
      sequence,
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
    ).unwrap()
    assert_eq(
      (full.retained_bytes, full.execution_bytes),
      (bounded.retained_bytes, bounded.execution_bytes),
    )
    let start = local_module_metered_output_start_capacity(
      original, 0, sequence,
    )
    if borrowed {
      let start = start.unwrap()
      assert_true(full.retained_bytes <= generic.retained_bytes)
      assert_true(full.execution_bytes < generic.execution_bytes)
      assert_true(start.retained_bytes < full.retained_bytes)
      assert_true(start.execution_bytes < full.execution_bytes)
    } else {
      assert_eq(
        (full.retained_bytes, full.execution_bytes),
        (generic.retained_bytes, generic.execution_bytes),
      )
      assert_true(start is None)
    }
    let starts = Ref(0)
    let replacement = managed_provider(_ => true, _ => Some(full), (
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
}

///|
test "joined branch Append keeps recursive outer and injected provider fallbacks" {
  for
    (contract, literal, kind, immediate) in [
      ("{\"type\":\"number\",\"nullable\":false}", "1", "inner", true),
      ("{\"type\":\"string\",\"nullable\":false}", "\"text\"", "inner", false),
      (
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "[1,2]", "inner", false,
      ),
      (
        "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"number\",\"nullable\":false}}}",
        "{\"x\":1}", "inner", false,
      ),
      ("{\"type\":\"number\",\"nullable\":false}", "1", "right", false),
    ] {
    let joined = "\"join\":{\"with\":\"value\",\"kind\":\"" +
      kind +
      "\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"right.id\",\"payload\":\"left.payload\"}}"
    let (whole, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"payload\":" +
      contract +
      "},\"rows\":[{\"id\":1,\"payload\":" +
      literal +
      "}]},\"as\":\"value\"},{\"from\":\"value\"," +
      joined +
      ",\"as\":\"left\"},{\"from\":\"value\"," +
      joined +
      ",\"as\":\"right\"},{\"from\":\"left\",\"append\":{\"with\":\"right\"}}]",
    )
    let sequence = @execution.select_generated_sequence_range(whole, 1, 3).unwrap()
    assert_eq(@execution.generated_sequence_step_count(sequence), 3)
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
      [sequence],
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(original, 0, sequence).unwrap()
    let startup = local_module_metered_output_start_capacity(
      original, 0, sequence,
    )
    if immediate {
      let startup = startup.unwrap()
      assert_true(startup.retained_bytes < full.retained_bytes)
      assert_true(startup.execution_bytes < full.execution_bytes)
    } else {
      assert_true(startup is None)
    }
    let starts = Ref(0)
    let replacement = managed_provider(_ => true, _ => Some(full), (
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
      chain_lifetime_limits(),
      chain_lifetime_measurement(),
      100000,
      1,
      managed_providers=[replacement],
    ).unwrap()
    assert_true(
      local_module_metered_output_start_capacity(injected, 0, sequence) is None,
    )
    let retained = local_module_capacity_for_sequence(injected, 0, sequence).unwrap()
    assert_eq(
      (retained.retained_bytes, retained.execution_bytes),
      (full.retained_bytes, full.execution_bytes),
    )
    assert_eq(starts.val, 0)
    @connector.close_capability_registry(registry)
  }
}

///|
test "nullable Text DISTINCT defers only actual same-task output and keeps recursive or injected retention" {
  for recursive in [false, true] {
    let (chain, _, _) = chain_lifetime_fixture(
      "[{\"from\":\"source\",\"derive\":{\"tag\":" +
      (if recursive {
        "{\"array\":[{\"field\":\"id\"}]}"
      } else {
        "{\"case\":{\"when\":[{\"when\":{\"eq\":[{\"field\":\"id\"},{\"literal\":1}]},\"then\":{\"literal\":\"x\"}}],\"else\":{\"literal\":null}}}"
      }) +
      "}},{\"distinct\":[\"id\"" +
      (if recursive { "" } else { ",\"tag\"" }) +
      "]}]",
    )
    let sequence = @execution.select_generated_sequence_step(
      chain,
      @execution.generated_sequence_step_index_at(chain, 1).unwrap(),
    ).unwrap()
    let values = {
      ..chain_lifetime_limits().rows.output_values,
      max_nodes: 590000,
      max_text_bytes: 20000000,
    }
    let limits = {
      ..chain_lifetime_limits(),
      rows: {
        ..chain_lifetime_limits().rows,
        input_values: values,
        output_values: values,
      },
    }
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
      [sequence],
      limits,
      chain_lifetime_measurement(),
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity(original, 0).unwrap()
    let startup = local_module_metered_output_start_capacity(
      original, 0, sequence,
    ).unwrap()
    if recursive {
      assert_eq(startup.retained_bytes, full.retained_bytes)
    } else {
      assert_true(startup.retained_bytes < full.retained_bytes)
      assert_true(startup.execution_bytes < full.execution_bytes)
      assert_true(startup.retained_bytes + startup.execution_bytes < 536870912L)
    }
    let unchanged = local_module_capacity(original, 0).unwrap()
    assert_eq(unchanged.retained_bytes, full.retained_bytes)
    assert_eq(unchanged.execution_bytes, full.execution_bytes)
    let replacement = managed_provider(_ => true, _ => Some(full), (
      _,
      _,
      _,
      _,
      _,
    ) => Err(@connector.InvalidLimits))
    let injected = prepare_local_compute_module(
      registry,
      registration,
      [sequence],
      limits,
      chain_lifetime_measurement(),
      100000,
      1,
      managed_providers=[replacement],
    ).unwrap()
    assert_true(
      local_module_metered_output_start_capacity(injected, 0, sequence) is None,
    )
    let fallback = local_module_capacity(injected, 0).unwrap()
    assert_eq(fallback.retained_bytes, full.retained_bytes)
    assert_eq(fallback.execution_bytes, full.execution_bytes)
    @connector.close_capability_registry(registry)
  }
}
