///|
test "initial module recipe follows this exact installed family factory" {
  let factory = installed_client_family_providers(
    @execution.execution_capacity(0L, 0L).unwrap(),
  )
  assert_eq(factory.length(), 9)
  assert_eq(installed_client_family_provider_count(), 9)
  let quote = @local.local_module_container_inventory(1, factory.length()).unwrap()
  assert_true(installed_client_module_container_units == quote)
  // Constructor DATA correspondence only; no physical backing/admission ACK.
}
