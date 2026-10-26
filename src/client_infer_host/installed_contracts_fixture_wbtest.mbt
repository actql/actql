///|
// One original immutable installed DATA closure, never a Run or provider grant.
// Existing foreign/reentry tests still pass their original distinct run owners.
let infer_fixture_installed_contracts_result : Result[
  @input.ClientInstalledSequenceContracts,
  @input.ClientInstalledManagedRunIssue,
] = @input.prepare_installed_sequence_contracts(
  infer_fixture_registry,
  infer_fixture_values,
  None,
  None,
)

///|
fn infer_fixture_installed_contracts() -> @input.ClientInstalledSequenceContracts {
  infer_fixture_installed_contracts_result.unwrap()
}

///|
test "Infer installed fixture admits exact originals and rejects malformed contracts" {
  let another = @input.prepare_installed_sequence_contracts(
    infer_fixture_registry,
    infer_fixture_values,
    None,
    None,
  ).unwrap()
  assert_false(physical_equal(infer_fixture_installed_contracts(), another))
  assert_true(
    @input.prepare_installed_sequence_contracts(
      "{}",
      infer_fixture_values,
      None,
      None,
    )
    is Err(@input.Unsupported),
  )
}
