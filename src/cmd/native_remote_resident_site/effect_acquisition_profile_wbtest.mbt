///|
test "Effect acquisition capture fits the unchanged resident byte allowances" {
  let limits = resident_effect_acquisition_limits()
  let capacity = @acquisition_host.prepared_native_capacity(limits).unwrap()
  // The profile must charge the complete receiver, not its streaming variant.
  // Leave capacity for the Site-controlled engine inside the existing budget.
  assert_true(capacity.retained_bytes < 16777216L)
  assert_true(capacity.execution_bytes + 67108864L < 134217728L)
  assert_eq(limits.completion.records.max_bytes, 65536)
  assert_eq(limits.completion.capture.max_bytes, 65536)
}
