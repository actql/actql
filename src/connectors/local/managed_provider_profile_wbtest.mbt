///|
test "bounded family recipe borrows actual module profile and preserves legacy holding" {
  let (sequence, _, _) = chain_lifetime_fixture(chain_lifetime_select_body())
  let (foreign, _, _) = chain_lifetime_fixture(chain_lifetime_select_body())
  let execution = chain_lifetime_limits()
  let measurement = chain_lifetime_measurement()
  let calls = Ref(0)
  let same_profile = Ref(false)
  let provider = managed_provider_with_inputs(
    selected => physical_equal(selected, sequence),
    selected => {
      if physical_equal(selected, sequence) {
        @execution.execution_capacity(1000L, 2000L)
      } else {
        None
      }
    },
    (_, _, _, _, _) => Err(@connector.InvalidLimits),
    bounded_relation_capacity=Some((
      selected,
      actual_execution,
      actual_measurement,
    ) => {
      same_profile.val = physical_equal(selected, sequence) &&
        physical_equal(actual_execution, execution) &&
        physical_equal(actual_measurement, measurement)
      calls.val += 1
      @execution.execution_capacity(10L, 100L)
    }),
  )
  assert_eq(
    managed_provider_capacity(provider, sequence).unwrap().retained_bytes,
    1000L,
  )
  assert_eq(calls.val, 0)
  let selected = managed_provider_capacity_for_execution(
    provider, sequence, execution, measurement,
  ).unwrap()
  assert_eq(selected.retained_bytes, 1000L)
  assert_eq(selected.execution_bytes, 1090L)
  assert_eq(calls.val, 1)
  assert_true(same_profile.val)
  assert_true(
    managed_provider_bounded_relation_capacity(
      provider, foreign, execution, measurement,
    )
    is None,
  )
  assert_eq(calls.val, 1)
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let installed = prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [sequence],
    execution,
    measurement,
    100,
    1,
    managed_providers=[provider],
  ).unwrap()
  assert_eq(calls.val, 2)
  assert_true(
    physical_equal(
      local_module_managed_provider(installed, 0, sequence).unwrap(),
      provider,
    ),
  )
  let cached = local_module_capacity_for_sequence(installed, 0, sequence).unwrap()
  assert_eq(cached.retained_bytes, selected.retained_bytes)
  assert_eq(cached.execution_bytes, selected.execution_bytes)
  assert_eq(calls.val, 2)
  // The generic Local importer/exporter owns its own growth independently
  // of this injected compute provider. Preserve the complete selected family
  // quote and expose NO permission to meter the provider's constructor.
  let (transport, provider_growth) = local_module_materializing_start_capacity(
    installed, 0,
  ).unwrap()
  assert_eq(provider_growth, None)
  assert_eq(transport.retained_bytes, cached.retained_bytes + 1752L)
  assert_eq(transport.execution_bytes, cached.execution_bytes + 1752L)
  assert_eq(calls.val, 2)
  assert_true(
    local_module_metered_output_start_capacity(installed, 0, sequence) is None,
  )
  assert_true(local_module_materializing_start_capacity(installed, 1) is None)
  assert_true(local_module_capacity_for_sequence(installed, 0, foreign) is None)
  assert_eq(calls.val, 2)
  let legacy = managed_provider_with_inputs(
    _ => true,
    _ => @execution.execution_capacity(1000L, 2000L),
    (_, _, _, _, _) => Err(@connector.InvalidLimits),
  )
  assert_true(
    managed_provider_bounded_relation_capacity(
      legacy, sequence, execution, measurement,
    )
    is None,
  )
  assert_eq(
    managed_provider_capacity_for_execution(
      legacy, sequence, execution, measurement,
    ).unwrap().execution_bytes,
    2000L,
  )
}

///|
test "bounded family unsupported and oversized recipe keeps full conservative capacity" {
  let (sequence, _, _) = chain_lifetime_fixture(chain_lifetime_select_body())
  let execution = chain_lifetime_limits()
  let measurement = chain_lifetime_measurement()
  for
    quoted in [
      None,
      @execution.execution_capacity(1001L, 1500L),
      @execution.execution_capacity(100L, 2001L),
      // Fits each callback dimension, but its scratch plus legacy R does not.
      @execution.execution_capacity(10L, 1500L),
    ] {
    let provider = managed_provider_with_inputs(
      _ => true,
      _ => @execution.execution_capacity(1000L, 2000L),
      (_, _, _, _, _) => Err(@connector.InvalidLimits),
      bounded_relation_capacity=Some((_, _, _) => quoted),
    )
    assert_true(
      managed_provider_bounded_relation_capacity(
        provider, sequence, execution, measurement,
      )
      is None,
    )
    let fallback = managed_provider_capacity_for_execution(
      provider, sequence, execution, measurement,
    ).unwrap()
    assert_eq(fallback.retained_bytes, 1000L)
    assert_eq(fallback.execution_bytes, 2000L)
  }
}

///|
test "provider reference inventory follows actual task population and separates transient selection" {
  assert_true(local_module_provider_field_inventory(-1) is None)
  let empty = local_module_provider_field_inventory(0).unwrap()
  assert_eq(empty.retained_bytes, 0L)
  assert_eq(empty.execution_bytes, 0L)
  let first = local_module_provider_field_inventory(1).unwrap()
  let next = local_module_provider_field_inventory(2).unwrap()
  let reference = @execution.preparation_representation_cost({
    record_headers: 0L,
    reference_slots: 1L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  assert_eq(next.retained_bytes - first.retained_bytes, reference)
  assert_eq(next.execution_bytes - first.execution_bytes, reference)
  assert_eq(
    first.execution_bytes - first.retained_bytes,
    @execution.preparation_representation_cost({
      record_headers: 4L,
      reference_slots: 13L,
      scalar_words: 4L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap(),
  )
}
