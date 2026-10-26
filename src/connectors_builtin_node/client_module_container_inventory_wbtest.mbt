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

///|
test "fixed family constructor recipe follows actual enum composition without activation" {
  assert_eq(installed_client_family_provider_count(), 9)
  assert_eq(
    @execution.preparation_representation_cost(
      installed_client_family_construction_retained,
    ),
    Some(2024L),
  )
  assert_eq(
    @execution.preparation_representation_cost(
      installed_client_family_construction_array,
    ),
    Some(128L),
  )
  assert_eq(
    @execution.preparation_representation_cost(
      installed_client_family_construction_temporary,
    ),
    Some(336L),
  )
}
