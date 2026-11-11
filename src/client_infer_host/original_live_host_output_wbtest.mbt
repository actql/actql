///|
// Actual portable original Mock/Read/entry/settlement, with the existing test
// Account and byte-grant ports. No ordinary Native/Source/Store is claimed.
test "live original Host output retains its same physical Model and never issues Saved custody" {
  let calls = Ref(0)
  let (active, installation, profile, read, ledger, _, _) = original_mock_fixture(
    calls,
    shared_parent=Some(shared_mock_test_parent()),
  )
  let binding = active.run_binding.unwrap()
  let plan = active.plan.unwrap()
  let work = match fixture_finish(active, initial_work=active.work) {
    Settling(_, work~) => work
    _ => abort("physical Mock must retain its original settlement")
  }
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
  assert_eq(calls.val, 1)
  assert_true(active.saved_call_scope is None)
  let held = acquire_output(active).unwrap()
  let before = @resources.ledger_usage(ledger)
  let foreign = call_identity_plan(fixture_prepared())
  assert_true(
    borrow_original_live_host_output(
      held,
      binding.compiled,
      binding.definition,
      foreign,
    )
    is None,
  )
  let (output, model) = borrow_original_live_host_output(
    held,
    binding.compiled,
    binding.definition,
    plan,
  ).unwrap()
  assert_eq(@relation.completed_row_count(output), 1)
  assert_true(@model.original_completed_model_matches_parent(model, ledger))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    borrow_original_restored_host_output(
      held,
      binding.compiled,
      binding.definition,
      plan,
    )
    is None,
  )
  assert_false(cleanup(active).unwrap())
  assert_true(release_output(held))
  assert_false(@relation.completed_output_available(output))
  assert_true(
    borrow_original_live_host_output(
      held,
      binding.compiled,
      binding.definition,
      plan,
    )
    is None,
  )
  restored_host_output_fixture_close(
    active, ledger, read, installation, profile,
  )
}
