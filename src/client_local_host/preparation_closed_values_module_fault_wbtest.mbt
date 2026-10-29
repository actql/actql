///|
extern "js" fn closed_module_test_throw() -> Array[@local.ManagedProvider] =
  #|() => { throw new Error('closed-module-original-callback'); }

///|
extern "js" fn closed_module_test_catch(body : () -> Unit) -> Bool =
  #|(body) => { try { body(); return false; } catch(error) { if(error.message!=='closed-module-original-callback')throw error; return true; } }

///|
test "original callback exception unwinds constructor occupancy before existing cleanup" {
  let (owner, ledger, environment, public_environment, contracts, manifests) = closed_module_fixture()
  let caught = closed_module_test_catch(() => {
    ignore(
      prepare_closed_values_module_body(
        owner,
        environment,
        public_environment,
        contracts,
        manifests,
        retained_output=true,
        family_retained=closed_module_no_family,
        family_array=closed_module_empty_factory_array,
        family_temporary=closed_module_no_family,
        provider_factory=_ => closed_module_test_throw(),
      ),
    )
  })
  assert_true(caught)
  assert_false(owner.module_constructing)
  // The failed constructor did not release funding in its exception handler.
  assert_true(@resources.ledger_usage(ledger).reserved_retention_bytes > 0L)
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  abort_closed_values_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
}
