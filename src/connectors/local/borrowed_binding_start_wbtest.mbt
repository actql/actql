///|
test "singleton borrowed binding leaves meter output DATA without admitting constructors or injected providers" {
  for
    (expression, borrowed) in [
      ("{\"literal\":\"ÿ\"}", true),
      ("{\"field\":\"payload\"}", true),
      ("{\"literal\":[1,2]}", true),
      ("{\"literal\":{\"x\":1}}", true),
      ("{\"object\":{\"x\":{\"field\":\"payload\"}}}", false),
      ("{\"array\":[{\"field\":\"payload\"}]}", false),
    ] {
    let (chain, _, _) = chain_lifetime_fixture(
      "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"payload\":\"é\"}]},\"as\":\"value\"},{\"from\":\"value\",\"derive\":{\"result\":" +
      expression +
      "}}]",
    )
    let selected = @execution.select_generated_sequence_step(
      chain,
      @execution.generated_sequence_step_index_at(chain, 1).unwrap(),
    ).unwrap()
    guard @execution.generated_sequence_step_at(selected, 0)
      is Some(@lower.RowStep(kernel)) else {
      fail("original binding kernel")
    }
    assert_eq(selected_binding_outputs_borrowed(kernel), borrowed)
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
    let metered = local_module_metered_output_start_capacity(
      original, 0, selected,
    ).unwrap()
    if borrowed {
      assert_true(metered.retained_bytes < full.retained_bytes)
    } else {
      assert_eq(metered.retained_bytes, full.retained_bytes)
    }
    // The logical constructor and traversal recipe itself stays unchanged;
    // this selection defers only persistent output to the existing growth link.
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
    assert_eq(more_output.retained_bytes - full.retained_bytes, 256L)
    assert_eq(more_output.execution_bytes - full.execution_bytes, 256L)
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
    assert_eq(
      local_module_capacity_for_sequence(injected, 0, selected).map(value => {
        (value.retained_bytes, value.execution_bytes)
      }),
      Some((full.retained_bytes, full.execution_bytes)),
    )
    @connector.close_capability_registry(registry)
  }
}

///|
test "ordered borrowed bindings retain repeated original prior-slot occurrences" {
  let owner = chain_lifetime_bind(
    @pipeline.check(
      chain_lifetime_cursor(
        "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"payload\":\"é\"}]},\"as\":\"value\"},{\"derive\":[{\"first\":\"payload\"},{\"second\":\"first\"},{\"again\":\"first\"}]}]",
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
    ).unwrap(),
  )
  let kernel = @lower.prepare_kernel(
    owner,
    1,
    max_bindings=100,
    max_name_bytes=10000,
    {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  ).unwrap()
  guard @lower.kernel_bindings(kernel) is Some(bindings) else {
    fail("original ordered binding kernel")
  }
  assert_true(@lower.bindings_ordered(bindings))
  assert_eq(@lower.bindings_count(bindings), 3)
  for index in 1..<3 {
    guard @lower.binding_at(bindings, index) is Some((_, expression)) else {
      fail("original prior-slot binding")
    }
    assert_true(
      @lower.expression_body(expression)
      is @lower.Field(_, @relation.PriorSlot(0)),
    )
  }
  assert_true(selected_binding_outputs_borrowed(kernel))
}
