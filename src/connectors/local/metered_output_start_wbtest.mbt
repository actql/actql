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
  assert_eq(metered.retained_bytes, full.retained_bytes)
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
