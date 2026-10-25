///|
fn compute_host(plan : LocalRunPlan) -> LocalComputeHost raise {
  configure_source_free_local_compute(
    plan,
    registered_installed_contracts(),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    Some(@identity.stringify_value(registered_fragment(), 100000, 10000, 100)),
    Some(@identity.stringify_value(registered_ordered(), 100000, 10000, 100)),
  ).unwrap()
}

///|
fn compute_start(host : LocalComputeHost) -> LocalComputeStart {
  let current = account(Allow)
  confirm_local_compute_start(
    host,
    host.plan.request,
    @publication.publication_contract_identity(host.plan.definition),
    true,
    true,
    false,
    false,
    permit(host.plan.input, current),
    current,
    tuple(),
    context_cid(),
  ).unwrap()
}

///|
let compute_program : String =
  #|{"version":"actql/0.1","id":"python.local.shared-seed","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"seed"},{"from":"seed","join":{"kind":"inner","with":"seed","on":[{"left":"n","right":"n"}],"select":{"left_n":"left.n","right_n":"right.n"},"max_output_rows":1},"as":"joined"},{"from":"joined","derive":{"value":"left_n + right_n"},"as":"derived"},{"from":"derived","select":["value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}

///|
test "the existing managed task Owners execute multiple tasks from Program and AQL" {
  for
    (original, restore) in [
      (@input.Program(compute_program), false),
      (@input.Program(compute_program), true),
      (
        @input.Aql(
          "WITH seed AS (SELECT 1 AS n) FROM seed AS l |> JOIN seed AS r ON l.n = r.n MAX_OUTPUT_ROWS 1 |> SELECT l.n + r.n AS value |> RESULT answer",
        ),
        false,
      ),
      (
        @input.Aql(
          "WITH seed AS (SELECT 1 AS n) FROM seed AS l |> JOIN seed AS r ON l.n = r.n MAX_OUTPUT_ROWS 1 |> SELECT l.n + r.n AS value |> RESULT answer",
        ),
        true,
      ),
    ] {
    let input = prepared(original)
    let original_plan = plan(input, "original-run")
    let plan = if restore {
      restore_fixture(prepared(original), original_plan).unwrap()
    } else {
      original_plan
    }
    let host = compute_host(plan)
    let run = local_compute_run(host)
    assert_true(@strategy.captured_task_activation_required(run))
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
      0,
    )
    let current = account(Allow)
    let allowed = permit(input, current)
    // These are independently fixed Owner facts, not a durable Host receipt.
    let start = compute_start(host)
    let outputs : Map[Int, @execution.ManagedCompletedOutput[Int]] = Map([])
    let retained : Map[Int, @managed.LocalManagedDispatchOperations[Int]] = Map([],
    )
    let available = Ref(true)
    let mut rounds = 0
    let tasks : Array[Int] = []
    while @strategy.next_captured_task(run) is Some(task) {
      rounds += 1
      assert_true(rounds <= 10)
      let producer_indexes = local_compute_producers(host)
      let inputs = producer_indexes.map(index => outputs.get(index).unwrap())
      let operations = start_local_compute_task(
          host,
          start,
          inputs,
          allowed,
          current,
          tuple(),
          context_cid(),
        )
        .unwrap()
        .unwrap()
      assert_false(@strategy.captured_task_activation_granted(run, task))
      assert_eq(operations.inputs.length(), producer_indexes.length())
      for index, transfer in operations.inputs {
        let source = retained.get(producer_indexes[index]).unwrap()
        for row in 0..<(source.output_rows)() {
          (transfer.append)((source.output_row)(row).unwrap()).unwrap()
        }
        (transfer.finish)().unwrap()
      }
      let mut executed = false
      for _ in 0..<1000 {
        let progress = (operations.advance)(1).unwrap()
        assert_true(progress.work >= 0L && progress.work <= 1L)
        if progress.complete {
          executed = true
          break
        }
      }
      assert_true(executed)
      (operations.prepare_finalization)(task, operations.storage_bytes, () => {
        available.val
      }).unwrap()
      let mut finalized = false
      for _ in 0..<1000 {
        let progress = (operations.advance_finalization)(1).unwrap()
        if progress.complete {
          finalized = true
          break
        }
      }
      assert_true(finalized)
      (operations.settle)().unwrap()
      let output = (operations.complete)(task, operations.storage_bytes, () => {
        available.val
      }).unwrap()
      assert_true(@strategy.captured_task_completed(run, task))
      outputs[task] = output
      retained[task] = operations
      tasks.push(task)
    }
    assert_true(rounds >= 2)
    let last = retained.get(tasks[rounds - 1]).unwrap()
    assert_eq((last.output_rows)(), 1)
    assert_eq((last.output_row)(0).unwrap(), "{\"value\":2}")
    assert_true(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes >
      0L,
    )
    // Only kernel completion is established here. Named Result publication,
    // physical persistence and process recovery remain separate boundaries.
    assert_eq(@host.client_task_compilation_result_names(plan.compilation), [
      "answer",
    ])
    available.val = false
    for offset in 0..<rounds {
      let task = tasks[rounds - offset - 1]
      let operations = retained.get(task).unwrap()
      (operations.close)()
      @strategy.close_captured_task_output(run, task)
      assert_true((operations.cleanup_refresh)())
    }
    @strategy.stop_captured_dag(run)
    @strategy.refresh_captured_retention(run)
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(usage.held_bytes, 0L)
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.reserved_transfer_bytes, 0L)
  }
}

///|
test "current denial cannot reserve or activate a configured task" {
  let input = prepared(@input.Program(program))
  let original = plan(input, "original-run")
  let host = compute_host(original)
  let run = local_compute_run(host)
  assert_true(
    start_local_compute_task(
      host,
      compute_start(host),
      [],
      permit(input, account(Allow)),
      account(Deny),
      tuple(),
      context_cid(),
    )
    is Err(AuthorizationMismatch),
  )
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.attempts, 0)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_false(@strategy.captured_task_completed(run, 0))
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
}

///|
test "foreign task subject and context cannot consume the original activation" {
  let input = prepared(@input.Program(compute_program))
  let host = compute_host(plan(input, "original-run"))
  let run = local_compute_run(host)
  let current = account(Allow)
  let foreign = @authorization.bind_dispatch_authorization(
    current,
    tuple(),
    Activation,
    "sha256:" + "f".repeat(64),
    context_cid(),
  ).unwrap()
  for
    (allowed, context) in [
      (foreign, context_cid()),
      (permit(input, current), "sha256:" + "e".repeat(64)),
    ] {
    let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_true(
      start_local_compute_task(
        host,
        compute_start(host),
        [],
        allowed,
        current,
        tuple(),
        context,
      )
      is Err(AuthorizationMismatch),
    )
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
      before,
    )
    assert_false(@strategy.captured_task_activation_granted(run, 0))
    assert_false(@strategy.captured_task_completed(run, 0))
  }
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
}

///|
test "each missing physical-start fact blocks task activation without reservation" {
  let input = prepared(@input.Program(compute_program))
  let original = plan(input, "original-run")
  let host = compute_host(original)
  let run = local_compute_run(host)
  let current = account(Allow)
  let allowed = permit(input, current)
  for
    (reserved, unstarted, cancelled, failed) in [
      (false, true, false, false),
      (true, false, false, false),
      (true, true, true, false),
      (true, true, false, true),
    ] {
    let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_true(
      confirm_local_compute_start(
        host,
        original.request,
        @publication.publication_contract_identity(original.definition),
        reserved,
        unstarted,
        cancelled,
        failed,
        allowed,
        current,
        tuple(),
        context_cid(),
      )
      is Err(_),
    )
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
      before,
    )
    assert_false(@strategy.captured_task_completed(run, 0))
    assert_false(@strategy.captured_task_activation_granted(run, 0))
  }
  let other = compute_host(original)
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_true(
    start_local_compute_task(
      host,
      compute_start(other),
      [],
      allowed,
      current,
      tuple(),
      context_cid(),
    )
    is Err(AuthorizationMismatch),
  )
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), before)
  for configured in [host, other] {
    @strategy.stop_captured_dag(local_compute_run(configured))
    @strategy.refresh_captured_retention(local_compute_run(configured))
  }
}
