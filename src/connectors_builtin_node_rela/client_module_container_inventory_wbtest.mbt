///|
test "provider-free RelA factory supplies empty installed snapshot dimension" {
  let factory = installed_client_family_providers(
    @execution.execution_capacity(0L, 0L).unwrap(),
  )
  assert_eq(factory.length(), 0)
  let quote = @local.local_module_container_inventory(1, factory.length()).unwrap()
  assert_eq(
    (quote.record_headers, quote.reference_slots, quote.scalar_words),
    (10L, 13L, 9L),
  )
  // DATA correspondence only. This package has no Node initial Root bridge.
}
