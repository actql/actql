///|
// This exercises the Model half of the supplier-entry fence. It does not
// manufacture an imported physical frame or establish Native funding.
fn model_read_frame_scope_fixture() -> (
  ClientModelReadScope,
  ClientCompiledRun,
  @publication.PublicationContract,
  ClientInferPlanGraph,
) {
  let (compiled, definition, plan) = client_model_read_test_run("frame-model")
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 10L,
    execution_bytes: 7L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 1, 0, 0,
  ).unwrap()
  (scope, compiled, definition, plan)
}

///|
test "Model frame scope fence keeps the checked Run and Plan without spending capacity" {
  let (scope, compiled, definition, plan) = model_read_frame_scope_fixture()
  let (other, other_definition, other_plan) = client_model_read_test_run(
    "other-frame",
  )
  let before = @resources.ledger_usage(scope.ledger)
  assert_true(
    client_model_read_frame_scope_current(scope, compiled, definition, plan),
  )
  assert_false(
    client_model_read_frame_scope_current(scope, other, definition, plan),
  )
  assert_false(
    client_model_read_frame_scope_current(
      scope, compiled, other_definition, plan,
    ),
  )
  assert_false(
    client_model_read_frame_scope_current(
      scope, compiled, definition, other_plan,
    ),
  )
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_false(
    client_model_read_frame_scope_current(scope, compiled, definition, plan),
  )
}

///|
test "Model frame final fence refuses copied grouped scope and real closing before census retirement" {
  let (compiled, definition, plans, ledger, identity) = client_model_read_group_fixture()
  let scopes = bind_client_model_read_scopes(
    compiled,
    definition,
    plans,
    ledger,
    identity,
    [7L, 9L],
    [5L, 6L],
  ).unwrap()
  assert_true(
    client_model_read_frame_scope_current(
      scopes[0],
      compiled,
      definition,
      plans[0],
    ),
  )
  assert_false(
    client_model_read_frame_scope_current(
      { ..scopes[0], },
      compiled,
      definition,
      plans[0],
    ),
  )
  assert_false(
    finish_client_model_read_scope(
      scopes[0],
      compiled,
      definition,
      plans[0],
      true,
    ).unwrap(),
  )
  // The real first-member close leaves the shared census alive for its sibling.
  // That retained census cannot reopen either member after closing began.
  assert_true(
    client_model_read_scope_live(scopes[0], compiled, definition, plans[0]),
  )
  let before = @resources.ledger_usage(ledger)
  assert_false(
    client_model_read_frame_scope_current(
      scopes[0],
      compiled,
      definition,
      plans[0],
    ),
  )
  assert_false(
    client_model_read_frame_scope_current(
      scopes[1],
      compiled,
      definition,
      plans[1],
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    finish_client_model_read_scope(
      scopes[1],
      compiled,
      definition,
      plans[1],
      true,
    ).unwrap(),
  )
}
