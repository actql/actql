///|
fn original_serialization_test_run(
  run_id? : String = "original-prefix",
) -> (
  PreparedClientProgram,
  ClientCompiledRun,
  @publication.PublicationContract,
  ClientInferPlanGraph,
) raise {
  let document =
    #|{"version":"actql/0.1","id":"original-content-prefix","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2},{"id":1}]},"as":"seed"},{"serialize":{"format":"jsonl","fields":["id"],"name":"out.jsonl","preserve_order":true,"bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"},{"assert_rows":{"unique_by":["name"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"text":{"field":"name"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["name","outcome","value"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let owner = client_composed_infer_test_program(authored=Some(document))
  let content = issue_prepared_client_serialization_plan_component(
    owner,
    0,
    1,
    serialization_plan_test_policy(),
    2,
    128,
    10000,
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  let occurrence = prepared_client_composed_infer_occurrence(owner).unwrap()
  let plan = issue_prepared_client_serialized_infer_plan_graph(
    occurrence,
    content,
    client_infer_graph_test_execution(owner, occurrence=Some(occurrence)),
    run_materials_limits().sequence,
    1000000,
    100000,
    100,
  ).unwrap()
  let compilation = issue_prepared_client_infer_compilation(
    owner,
    plan,
    run_materials_manifests(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let compiled = issue_client_task_compiled_run(
    owner,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    compiled, "content-scope", run_id, "2026-10-13T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  (owner, compiled, definition, plan)
}

///|
fn original_serialization_test_scope(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> (ClientModelReadScope, @resources.Ledger) {
  // Independent small lifetime fixture, not an adopted physical profile.
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 20L,
    execution_bytes: 12L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 3, 1, 0,
  ).unwrap()
  (scope, ledger)
}

///|
test "original Content prefix borrow binds nominal Program Run Model and compiler coordinates" {
  let (owner, compiled, definition, plan) = original_serialization_test_run()
  let (foreign_owner, foreign, foreign_definition, foreign_plan) = original_serialization_test_run(
    run_id="foreign-prefix",
  )
  let (scope, ledger) = original_serialization_test_scope(
    compiled, definition, plan,
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    physical_equal(
      borrow_client_original_serialization_ledger(
        scope, compiled, definition, plan, owner, 0, 1,
      ).unwrap(),
      ledger,
    ),
  )
  for (task, step) in [(1, 1), (0, 0), (0, 2), (-1, 1), (0, -1)] {
    assert_true(
      borrow_client_original_serialization_ledger(
        scope, compiled, definition, plan, owner, task, step,
      )
      is Err(ForeignRun),
    )
  }
  assert_true(
    borrow_client_original_serialization_ledger(
      scope, compiled, definition, plan, foreign_owner, 0, 1,
    )
    is Err(ForeignRun),
  )
  assert_true(
    borrow_client_original_serialization_ledger(
      scope, foreign, foreign_definition, foreign_plan, foreign_owner, 0, 1,
    )
    is Err(ForeignRun),
  )
  assert_true(
    borrow_client_original_serialization_ledger(
      scope, compiled, foreign_definition, plan, owner, 0, 1,
    )
    is Err(ForeignRun),
  )
  assert_true(
    borrow_client_original_serialization_ledger(
      scope, compiled, definition, foreign_plan, owner, 0, 1,
    )
    is Err(ForeignRun),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "original Content prefix refuses descriptor issuance and closed scope before construction" {
  let (owner, compiled, definition, plan) = original_serialization_test_run()
  let (scope, ledger) = original_serialization_test_scope(
    compiled, definition, plan,
  )
  let read = prepare_client_model_read(scope, 7L, 5L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    borrow_client_original_serialization_ledger(
      scope, compiled, definition, plan, owner, 0, 1,
    )
    is Err(Resource(@resources.ChangedOriginalState)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  settle_client_model_read(read, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_true(
    borrow_client_original_serialization_ledger(
      scope, compiled, definition, plan, owner, 0, 1,
    )
    is Err(Resource(@resources.ChangedOriginalState)),
  )
}

///|
test "original Content prefix reentry cannot bypass failed pending child cleanup or issued identity" {
  let (owner, compiled, definition, plan) = original_serialization_test_run()
  let (scope, ledger) = original_serialization_test_scope(
    compiled, definition, plan,
  )
  let same = borrow_client_original_serialization_ledger(
    scope, compiled, definition, plan, owner, 0, 1,
  ).unwrap()
  let child = @resources.reserve_attempt(same, 0L, 7L, 5L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    borrow_client_original_serialization_ledger(
      scope, compiled, definition, plan, owner, 0, 1,
    )
    is Err(Resource(@resources.ChangedOriginalState)),
  )
  assert_false(
    finish_client_model_read_scope(scope, compiled, definition, plan, false).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@resources.reservation_open(child))
  @resources.settle_reservation(same, child).unwrap()
  // No physical attempt was started. Returning the reserved attempt slot does
  // not rewind its issued identity or make the original census pristine.
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 0)
  assert_true(
    borrow_client_original_serialization_ledger(
      scope, compiled, definition, plan, owner, 0, 1,
    )
    is Err(Resource(@resources.ChangedOriginalState)),
  )
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "original Content prefix reserve failure leaves the same pristine scope retryable" {
  let (owner, compiled, definition, plan) = original_serialization_test_run()
  let (scope, ledger) = original_serialization_test_scope(
    compiled, definition, plan,
  )
  let same = borrow_client_original_serialization_ledger(
    scope, compiled, definition, plan, owner, 0, 1,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @resources.reserve_attempt(same, 0L, 18L, 5L)
    is Err(@resources.RetentionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    physical_equal(
      borrow_client_original_serialization_ledger(
        scope, compiled, definition, plan, owner, 0, 1,
      ).unwrap(),
      ledger,
    ),
  )
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}
