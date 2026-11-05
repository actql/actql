///|
// Existing real Common Mock, Scope, retained input identity, Account and durable
// entry/settlement fixture. Physical byte grants remain explicit test ports;
// no normal installation, Source IO, Store or physical ACK is qualified.
fn restored_host_output_fixture(
  custody : () -> Bool,
) -> (
  Execution,
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
  @publication_host.ClientInferPlanGraph,
  @resources.Ledger,
  @publication_host.ClientModelReadPreparation,
  @model.ModelMockInstallation,
  @environment.ModelMockProfile,
) raise {
  let calls = Ref(0)
  let (active, installation, profile, read, ledger, _, _) = original_mock_fixture(
    calls,
    shared_parent=Some(shared_mock_test_parent()),
    restored_input=true,
    restored_custody=custody,
  )
  let binding = active.run_binding.unwrap()
  let work = match fixture_finish(active, initial_work=active.work) {
    Settling(_, work~) => work
    _ => abort("restored Mock must retain its original settlement")
  }
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  guard fixture_finish(active, initial_work=work) is Complete(output, ..) else {
    abort("actual restored Model must complete")
  }
  assert_eq(@relation.completed_row_count(output), 1)
  assert_eq(calls.val, 1)
  (
    active,
    binding.compiled,
    binding.definition,
    active.plan.unwrap(),
    ledger,
    read,
    installation,
    profile,
  )
}

///|
fn restored_host_output_fixture_close(
  active : Execution,
  ledger : @resources.Ledger,
  read : @publication_host.ClientModelReadPreparation,
  installation : @model.ModelMockInstallation,
  profile : @environment.ModelMockProfile,
) -> Unit raise {
  assert_true(cleanup(active).unwrap())
  assert_eq(@model.retire_original_model_mock(installation), Ok(true))
  assert_true(@environment.retire_model_mock_profile(profile))
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
}

///|
test "restored Host output borrows the actual completed execution and retains cleanup" {
  let (active, compiled, definition, plan, ledger, read, installation, profile) = restored_host_output_fixture(() => {
      true
    },
  )
  active.local_component_bound = true
  let held = acquire_output(active).unwrap()
  let before = @resources.ledger_usage(ledger)
  let (output, model) = borrow_original_restored_host_output(
    held, compiled, definition, plan,
  ).unwrap()
  assert_eq(@relation.completed_row_count(output), 1)
  assert_true(@model.original_completed_model_matches_parent(model, ledger))
  let foreign_parent = @resources.create_ledger(
    @resources.ledger_limits(ledger),
  ).unwrap()
  assert_false(
    @model.original_completed_model_matches_parent(model, foreign_parent),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    borrow_original_restored_host_output(held, compiled, definition, plan)
    is Some(_),
  )
  assert_false(cleanup(active).unwrap())
  assert_true(release_output(held))
  assert_false(@relation.completed_output_available(output))
  restored_host_output_fixture_close(
    active, ledger, read, installation, profile,
  )
}

///|
test "restored Host output refuses foreign and revoked originals without spending its handoff" {
  let current = Ref(true)
  let observations = Ref(0)
  let (active, compiled, definition, plan, ledger, read, installation, profile) = restored_host_output_fixture(() => {
      observations.val += 1
      current.val
    },
  )
  let held = acquire_output(active).unwrap()
  observations.val = 0
  assert_true(
    @publication_host.client_infer_saved_call_scope_matches_originals(
      active.saved_call_scope.unwrap(),
      compiled,
      definition,
      active.occurrence,
      plan,
    ),
  )
  assert_eq(observations.val, 1)
  let foreign_prepared = fixture_prepared()
  let (foreign, foreign_definition) = original_input_capacity_run(
    foreign_prepared,
    call_identity_plan(foreign_prepared),
  )
  assert_true(
    borrow_original_restored_host_output(
      held, foreign, foreign_definition, plan,
    )
    is None,
  )
  assert_false(active.local_component_bound)
  current.val = false
  assert_true(
    borrow_original_restored_host_output(held, compiled, definition, plan)
    is None,
  )
  assert_false(active.local_component_bound)
  assert_true(release_output(held))
  restored_host_output_fixture_close(
    active, ledger, read, installation, profile,
  )
}

///|
test "restored Host output fences a saved custody callback releasing its original pin" {
  let reenter : Ref[() -> Unit] = Ref(() => ())
  let (active, compiled, definition, plan, ledger, read, installation, profile) = restored_host_output_fixture(() => {
      (reenter.val)()
      true
    },
  )
  let held = acquire_output(active).unwrap()
  reenter.val = () => release_output(held) |> ignore
  assert_true(
    borrow_original_restored_host_output(held, compiled, definition, plan)
    is None,
  )
  assert_false(active.local_component_bound)
  restored_host_output_fixture_close(
    active, ledger, read, installation, profile,
  )
}

///|
test "restored Host output does not accept a fresh Model completion as Saved" {
  let calls = Ref(0)
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let binding = original_input_capacity_run(prepared, plan)
  let active = fixture_start(prepared, () => calls.val += 1)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let held = acquire_output(active).unwrap()
  assert_true(
    borrow_original_restored_host_output(held, binding.0, binding.1, plan)
    is None,
  )
  assert_eq(calls.val, 1)
  assert_true(release_output(held))
  assert_true(cleanup(active).unwrap())
}
