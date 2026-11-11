///|
test "borrowed UNNEST chains use original child capacities and reject injected recipes" {
  for
    (expression, borrowed) in [
      ("{\"literal\":[2,null,2]}", true),
      ("{\"array\":[{\"field\":\"id\"}]}", false),
    ] {
    // Literal JSON is deliberately not used as an inferred Array schema.
    // The original Values declaration supplies the exact typed parent array;
    // this separate carried binding distinguishes borrowed and built DATA.
    let checked = @pipeline.check(
      chain_lifetime_cursor(
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":false,\"max_items\":3,\"items\":{\"type\":\"number\",\"nullable\":true}}},\"rows\":[{\"id\":1,\"items\":[2,null,2]}]},\"as\":\"parents\"}," +
        "{\"derive\":{\"extra\":" +
        expression +
        "}},{\"unnest\":{\"column\":\"items\",\"as\":\"element\",\"with_index\":\"position\"}}," +
        "{\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"element\",\"position\"]}]",
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
        debug_inspect(issue.kind, content="accepted typed parent test pipeline")
        abort("typed parent test pipeline refused")
      }
    }
    let whole = chain_lifetime_generated(owner)
    let sequence = @execution.select_generated_sequence_range(whole, 1, 4).unwrap()
    assert_eq(@execution.generated_sequence_step_count(sequence), 4)
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
    let limits = chain_lifetime_limits()
    let measurement = chain_lifetime_measurement()
    let installed = prepare_local_compute_module(
      registry,
      registration,
      [sequence],
      limits,
      measurement,
      100000,
      1,
    ).unwrap()
    let full = local_module_capacity_for_sequence(installed, 0, sequence).unwrap()
    let start = local_module_metered_output_start_capacity(
      installed, 0, sequence,
    ).unwrap()
    if borrowed {
      assert_true(start.retained_bytes < full.retained_bytes)
      assert_true(start.execution_bytes < full.execution_bytes)
    } else {
      // Constructed expression output does not get the borrowed-chain proof.
      assert_eq(start.retained_bytes, full.retained_bytes)
    }
    let unnest = @execution.select_generated_sequence_step(
      sequence,
      @execution.generated_sequence_step_index_at(sequence, 1).unwrap(),
    ).unwrap()
    let bounded = @execution.generated_bounded_sequence_capacity(
      unnest, limits, measurement,
    ).unwrap()
    let input = @execution.generated_bounded_sequence_capacity(
      unnest,
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
      measurement,
    ).unwrap()
    assert_eq(input.execution_bytes, bounded.execution_bytes)
    let output = @execution.generated_bounded_sequence_capacity(
      unnest,
      {
        ..limits,
        rows: {
          ..limits.rows,
          output_values: {
            ..limits.rows.output_values,
            max_nodes: limits.rows.output_values.max_nodes + 1,
          },
        },
      },
      measurement,
    ).unwrap()
    assert_eq(output.retained_bytes - bounded.retained_bytes, 256L)
    assert_eq(output.execution_bytes - bounded.execution_bytes, 256L)
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
    @connector.close_capability_registry(registry)
  }
}
