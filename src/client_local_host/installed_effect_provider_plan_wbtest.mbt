///|
test "provider Source Plan retains original reader and simultaneous completed tail envelopes" {
  for provider_execution in [2222L, 536874245L] {
    let provider = @execution.execution_capacity(1111L, provider_execution).unwrap()
    let plan = effect_operation_source_plan_fixture(provider=Some(provider))
    let (_, requirement, acquisition, capacity) = prepared_installed_effect_managed_source(
      plan, 0,
    ).unwrap()
    assert_true(physical_equal(requirement, capacity.requirement))
    assert_true(
      installed_provider_row_capture_capacity_matches(
        capacity, acquisition, provider,
      ),
    )
    let ordinary = installed_row_capture_capacity(acquisition).unwrap()
    assert_eq(capacity.retained_bytes, ordinary.retained_bytes + 1111L)
    assert_eq(
      capacity.execution_bytes,
      ordinary.execution_bytes + provider_execution,
    )
    let plain = effect_operation_source_plan_fixture()
    let retained_controls = @execution.preparation_representation_cost({
      record_headers: 3L,
      reference_slots: 7L,
      scalar_words: 1L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap()
    let scratch_controls = @execution.preparation_representation_cost({
      record_headers: 3L,
      reference_slots: 2L,
      scalar_words: 4L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap()
    assert_eq(
      plan._observed_compute_limits.retained_bytes,
      plain._observed_compute_limits.retained_bytes + 1111L,
    )
    assert_eq(
      plan._observed_compute_limits.execution_bytes,
      Int64::max(
        plain._observed_compute_limits.execution_bytes,
        capacity.execution_bytes + plan.transport_execution_bytes[0],
      ),
    )
    assert_eq(
      plan.limits.retained_bytes,
      plain.limits.retained_bytes + 1111L + retained_controls,
    )
    // Read the SAME retained dispatch envelopes as the eventual execution
    // consumer. This does not invoke the Plan's phase-fold helper or prepare
    // another graph/configuration; independently compose the actual lifetime.
    let mut tail_execution = 0L
    for
      task in plan.capacity_plan.graph_offset..<@strategy.graph_task_count(
        plan.configuration.graph,
      ) {
      tail_execution += @local_driver.local_dispatch_preparation_task_capacity(
          plan.configuration.dispatch,
          task,
        ).unwrap().execution_bytes
    }
    let tail_retained = plan._observed_compute_limits.retained_bytes -
      capacity.retained_bytes
    let reading = capacity.execution_bytes +
      plan.transport_execution_bytes[0] +
      tail_retained
    let completed = ordinary.execution_bytes +
      1111L +
      plan.transport_execution_bytes[0] +
      tail_execution
    assert_eq(
      plan.limits.execution_bytes,
      plain.limits.execution_bytes -
      plain._observed_compute_limits.execution_bytes +
      Int64::max(reading, completed) +
      retained_controls +
      scratch_controls,
    )
  }
}
