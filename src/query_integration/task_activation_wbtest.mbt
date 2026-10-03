///|
fn activation_account_action(
  outcome : @authorization.ConfiguredOutcome,
) -> @authorization.RuntimeAction {
  let configuration = @authorization.admit_account_configuration({
    account_id: "local-account",
    entries: [
      {
        entry_id: "compute",
        outcome,
        scope: {
          principal: All,
          connection: All,
          resource: All,
          operation: AnyOf(["write"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
  @authorization.runtime_action_for(
    @authorization.evaluate_account(configuration, {
      principal: "local-user",
      connection: "site-a",
      resource: "synchronous-test",
      operation: "write",
    }),
  ).unwrap()
}

///|
fn activation_test_prepared(
  choice : @connector.FixedComputeChoice,
  candidate : @connector.PreparedCompute[Int],
  calls : Ref[Int],
) -> @connector.PreparedExecution[Int, @strategy.RunIssue] {
  @connector.bind_prepared_materializing_execution(
    choice,
    candidate,
    {
      transfer_bytes: 100L,
      retained_bytes: 100L,
      scratch_bytes: 10L,
      execution_bytes: 100L,
    },
    [],
    fn(payload) {
      calls.val += 1
      let operations : @connector.ExecutionLifecycleOperations[
        @strategy.RunIssue,
      ] = {
        cancel: fn() {  },
        dispose: fn() {  },
        settled: fn() {  },
        scratch_released: fn() { true },
        retention_released: fn() { true },
        released: fn() {  },
        ready: fn() { Ok(()) },
      }
      Ok((payload, operations))
    },
  ).unwrap()
}

///|
test "only an evaluated dispatch authorization yields an activation grant" {
  assert_true(
    @strategy.task_activation_authorized(activation_account_action(Allow))
    is Some(_),
  )
  assert_true(
    @strategy.task_activation_authorized(activation_account_action(Deny))
    is None,
  )
  assert_true(
    @strategy.task_activation_grant_basis(@strategy.task_activation_covered())
    is None,
  )
}

///|
test "synchronous start refuses a required activation without a grant" {
  let (run, _) = captured_graph_fixture()
  let (_, choice, prepared) = synchronous_test_choice(run)
  let ledger = @strategy.captured_dag_ledger(run)
  let calls = Ref(0)
  let compute = @connector.bind_synchronous_compute(
    choice,
    prepared,
    { retained_bytes: 100L, execution_bytes: 100L, },
    [],
    fn(_) {
      calls.val += 1
      Err(Compute(ComputeUnsupported))
    },
  ).unwrap()
  @strategy.require_captured_task_activation(run)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @strategy.execute_captured_synchronous_task(run, 1, compute)
    is Err(ActivationNotAuthorized),
  )
  assert_eq(calls.val, 0)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@connector.synchronous_compute_available(compute))
  let grant = @strategy.task_activation_authorized(
    activation_account_action(Allow),
  ).unwrap()
  assert_true(
    @strategy.task_activation_grant_basis(grant)
    is Some(AccountAllow("compute")),
  )
  @strategy.authorize_captured_task_activation(run, 1, grant).unwrap()
  assert_true(@strategy.captured_task_activation_granted(run, 1))
  assert_true(
    @strategy.execute_captured_synchronous_task(run, 1, compute)
    is Err(Compute(ComputeUnsupported)),
  )
  assert_eq(calls.val, 1)
  assert_false(@strategy.captured_task_activation_granted(run, 1))
}

///|
test "materializing start refuses a required activation without a grant" {
  let (run, _) = captured_graph_fixture()
  let (_, choice, candidate) = synchronous_test_choice(run)
  let ledger = @strategy.captured_dag_ledger(run)
  let calls = Ref(0)
  let prepared = activation_test_prepared(choice, candidate, calls)
  @strategy.require_captured_task_activation(run)
  assert_true(@strategy.captured_task_activation_required(run))
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @strategy.start_captured_materializing_execution(run, 1, prepared)
    is Err(ActivationNotAuthorized),
  )
  assert_eq(calls.val, 0)
  assert_eq(@resources.ledger_usage(ledger), before)
  // A grant names exactly the next ready task.
  assert_true(
    @strategy.authorize_captured_task_activation(
      run,
      2,
      @strategy.task_activation_covered(),
    )
    is Err(NotReady),
  )
  @strategy.authorize_captured_task_activation(
    run,
    1,
    @strategy.task_activation_covered(),
  ).unwrap()
  let (_, execution) = @strategy.start_captured_materializing_execution(
    run, 1, prepared,
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_false(@strategy.captured_task_activation_granted(run, 1))
  @strategy.close_task_execution(run, execution)
}

///|
test "a stopped Run neither accepts nor keeps an activation grant" {
  let (run, _) = captured_graph_fixture()
  let (_, choice, candidate) = synchronous_test_choice(run)
  let calls = Ref(0)
  let prepared = activation_test_prepared(choice, candidate, calls)
  @strategy.require_captured_task_activation(run)
  @strategy.authorize_captured_task_activation(
    run,
    1,
    @strategy.task_activation_covered(),
  ).unwrap()
  @strategy.stop_captured_dag(run)
  assert_false(@strategy.captured_task_activation_granted(run, 1))
  assert_true(
    @strategy.authorize_captured_task_activation(
      run,
      1,
      @strategy.task_activation_covered(),
    )
    is Err(Stopped),
  )
  assert_true(
    @strategy.start_captured_materializing_execution(run, 1, prepared)
    is Err(Stopped),
  )
  assert_eq(calls.val, 0)
}
