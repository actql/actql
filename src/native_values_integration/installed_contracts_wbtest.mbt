///|
// Admit the same generated contract DATA once per installation. This is not a
// Run or resource grant; selected optional bodies remain checked by consumers.
fn native_values_installed_contracts() -> @client_local_host.ClientInstalledSequenceContracts raise {
  @client_local_host.prepare_installed_sequence_contracts(
    @identity.stringify_value(registered_body(), 100000, 10000, 100),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    Some(@identity.stringify_value(registered_fragment(), 100000, 10000, 100)),
    None,
  ).unwrap()
}

///|
test "native Values installation admits distinct originals and rejects malformed DATA" {
  let first = native_values_installed_contracts()
  let second = native_values_installed_contracts()
  assert_false(physical_equal(first, second))
  assert_true(
    @client_local_host.prepare_installed_sequence_contracts(
      "{}",
      @identity.stringify_value(registered_values(), 100000, 10000, 100),
      None,
      None,
    )
    is Err(@client_local_host.Unsupported),
  )
}
