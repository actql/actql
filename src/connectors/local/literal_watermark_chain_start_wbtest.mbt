///|
fn literal_watermark_start_sequence() -> @execution.GeneratedSequence raise {
  let owner = chain_lifetime_bind(
    @pipeline.check(
      chain_lifetime_cursor(
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"at\":10},{\"id\":2,\"at\":3},{\"id\":3,\"at\":9}]},\"as\":\"rows\"},{\"from\":\"rows\",\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}],\"as\":\"ordered\"},{\"from\":\"ordered\",\"watermark_rows\":{\"time\":\"at\",\"late_policy\":\"mark\",\"watermark_ms\":3},\"as\":\"marked\"},{\"from\":\"marked\",\"sort\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"}]},{\"select\":[\"id\",\"at\",\"watermark_ms\",\"watermark_late\",\"watermark_decision\"]}]",
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
  chain_lifetime_generated(owner, fragment_work=20000000L)
}

///|
test "literal watermark keeps full output DATA without reserving a legacy sequence table" {
  let sequence = literal_watermark_start_sequence()
  assert_true(selected_literal_binding_chain(sequence))
  let values : @execution.ValueLimits = {
    max_nodes: 20000,
    max_text_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  let limits = {
    ..chain_lifetime_limits(),
    rows: {
      ..chain_lifetime_limits().rows,
      input_values: values,
      output_values: values,
    },
    max_work: 20000000,
  }
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  // Match the public case's large finite measurement ceiling. Its bounded
  // cursor measures original cells without allocating a maximum-size wire.
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 20000000,
    max_bytes: 120069633,
    max_nodes: 20000,
    max_depth: 100,
  }
  let installed = prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [sequence],
    limits,
    measurement,
    100000,
    1,
  ).unwrap()
  let full = local_module_capacity_for_sequence(installed, 0, sequence).unwrap()
  let startup = local_module_metered_output_start_capacity(
    installed, 0, sequence,
  ).unwrap()
  assert_eq(startup.retained_bytes, full.retained_bytes)
  assert_true(startup.execution_bytes < full.execution_bytes)
  assert_true(startup.retained_bytes + startup.execution_bytes < 536870912L)
}
