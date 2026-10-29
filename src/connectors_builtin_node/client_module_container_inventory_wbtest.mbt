///|
test "actual installed family factory retains its selected provider inventory" {
  let factory = installed_client_family_providers(
    @execution.execution_capacity(0L, 0L).unwrap(),
  )
  assert_eq(factory.length(), 9)
  // Constructor DATA correspondence only; no physical backing/admission ACK.
}
