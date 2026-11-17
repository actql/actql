///|
test "borrowed analytic chain keeps full retention and all staged Text within the original physical recipe" {
  let (sequence, _, _) = chain_lifetime_fixture(
    (
      #|[{"from":"source","analytic":{"partition_by":[],"order_by":[{"id":"asc"}],"frame":{"start":{"preceding":1},"end":"current_row"},"functions":{"aql_order_window_0":{"fn":"string_agg","expr":{"literal":"x"},"delimiter":"|","max_bytes":65536}}}},{"sort":[{"aql_order_window_0":"desc"},{"id":"desc"}]},{"select":["id"]}]
    ),
  )
  let values : @execution.ValueLimits = {
    max_nodes: 1400,
    max_text_bytes: 20000000,
    max_depth: 100,
    max_work: 20000000,
  }
  let limits : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 100,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 20000000,
    max_frames: 100,
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 20000000,
    max_bytes: 120040633,
    max_nodes: 2800,
    max_depth: 100,
  }
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let installed = prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [sequence],
    limits,
    measurement,
    100000,
    1,
  ).unwrap()
  let full = local_module_capacity(installed, 0).unwrap()
  let startup = local_module_metered_output_start_capacity(
    installed, 0, sequence,
  ).unwrap()
  assert_eq(startup.retained_bytes, full.retained_bytes)
  assert_true(startup.execution_bytes < full.execution_bytes)
  // This is the original alongside-retained materializer convention, not an
  // E==R assumption or a completed-output retention discount.
  assert_true(
    startup.retained_bytes + startup.execution_bytes < 512L * 1024L * 1024L,
  )
  println(
    "analytic-original-policy-quote R=" +
    startup.retained_bytes.to_string() +
    " E=" +
    startup.execution_bytes.to_string() +
    " alongside=" +
    (startup.retained_bytes + startup.execution_bytes).to_string(),
  )
  @connector.close_capability_registry(registry)
}
