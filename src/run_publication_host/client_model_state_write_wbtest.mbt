///|
fn client_model_state_test_scope(
  planning : Int,
) -> (
  ClientCompiledRun,
  @publication.PublicationContract,
  ClientInferPlanGraph,
  @resources.Ledger,
  ClientModelReadScope,
) {
  let (compiled, definition, plan) = client_model_read_test_run(
    "state-original",
  )
  let ledger = @resources.create_ledger({
    planning_work: planning,
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
  (compiled, definition, plan, ledger, scope)
}

///|
test "checked original state Writer binds exact Run before same consumer handoff" {
  let (compiled, definition, plan, ledger, scope) = client_model_state_test_scope(
    17,
  )
  let (foreign, foreign_definition, foreign_plan) = client_model_read_test_run(
    "state-foreign",
  )
  // These small positive fixture envelopes exercise ownership only. They
  // are not an adopted physical bound for the compiler, Writer or Model.
  let writer = @encode.writer(1000, 200, 10)
  let read = prepare_client_model_read_state(scope, writer, 7L, 5L).unwrap()
  assert_eq(@resources.ledger_usage(ledger).planning_work, 17)
  assert_false(client_model_read_available(read, compiled, definition, plan))
  assert_true(
    claim_client_model_read_preparation(
      read, compiled, definition, plan, 7L, 5L,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  assert_true(
    handoff_client_model_read(read, compiled, definition, plan)
    is Err(Resource(@resources.SpentClaim)),
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    advance_client_model_read_state(read, compiled, foreign_definition, plan, 1)
    is @resources.StateWriteFailed(
      @resources.Original(@resources.ForeignOrigin),
      work=0
    ),
  )
  assert_true(
    advance_client_model_read_state(
      read, foreign, foreign_definition, foreign_plan, 1,
    )
    is @resources.StateWriteFailed(
      @resources.Original(@resources.ForeignOrigin),
      work=0
    ),
  )
  assert_eq(@encode.writer_progress(writer), (0, 0, 0))
  assert_eq(@resources.ledger_usage(ledger), before)
  let work = for work = 0 {
    match advance_client_model_read_state(read, compiled, definition, plan, 1) {
      @resources.StateWriteContinue(work=spent) => continue work + spent
      @resources.StateWriteComplete(work=spent) => break work + spent
      @resources.StateWriteFailed(_, ..) => break -1
    }
  }
  assert_eq(work, 17)
  // Independent fixed payload: checked identity stays opaque and cannot be
  // inferred from these record bytes. The original Run binding is separate.
  let expected = "[\"actql-original-ledger-state/0.1\",[\"17\",\"2\",\"3\",\"11\",\"10\",\"7\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"2\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"],[\"1\",\"0\",\"0\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
  assert_eq(@encode.finish(writer), expected)
  assert_true(client_model_read_available(read, compiled, definition, plan))
  let consumer = claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  assert_true(
    claim_client_model_read_preparation(
      read, compiled, definition, plan, 7L, 5L,
    )
    is Err(Resource(@resources.SpentClaim)),
  )
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  assert_true(
    settle_client_model_read_consumer(consumer, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  settle_client_model_read_consumer(consumer, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "checked original state Writer one short leaves original scope and encoder unissued" {
  let (compiled, definition, plan, ledger, scope) = client_model_state_test_scope(
    16,
  )
  let writer = @encode.writer(1000, 200, 10)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    prepare_client_model_read_state(scope, writer, 7L, 5L)
    is Err(@resources.Resource(@resources.PlanningLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@encode.writer_progress(writer), (0, 0, 0))
  @encode.cancel_writer(writer)
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "checked original state Writer failed cleanup keeps same claim after positive work" {
  let (compiled, definition, plan, ledger, scope) = client_model_state_test_scope(
    17,
  )
  let writer = @encode.writer(1000, 200, 10)
  let read = prepare_client_model_read_state(scope, writer, 7L, 5L).unwrap()
  assert_true(
    advance_client_model_read_state(read, compiled, definition, plan, 1)
    is @resources.StateWriteContinue(work=1),
  )
  assert_true(
    settle_client_model_read(read, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_eq(@resources.ledger_usage(ledger).planning_work, 17)
  assert_false(client_model_read_available(read, compiled, definition, plan))
  assert_true(
    advance_client_model_read_state(read, compiled, definition, plan, 1)
    is @resources.StateWriteFailed(@resources.Terminal, work=0),
  )
  assert_true(
    prepare_client_model_read_state(scope, writer, 7L, 5L)
    is Err(@resources.Original(@resources.SpentClaim)),
  )
  settle_client_model_read(read, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "checked original state Writer uses selected layout without a second descriptor" {
  let (compiled, definition, plan) = client_model_read_test_run("state-layout")
  let layout = client_node_layout_test_declaration(plan)
  let installation = client_node_layout_test_installation()
  let ledger = @resources.create_ledger({
    planning_work: 17,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 7003L,
    execution_bytes: 3002L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 1, 0, 0,
  ).unwrap()
  // The same selected installation is checked before constructing read state.
  // These declared fixture bytes do not justify a physical normal profile.
  check_client_node_model_preparation_layout(
    Some(layout),
    plan,
    installation,
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
  ).unwrap()
  let writer = @encode.writer(1000, 200, 10)
  let read = prepare_client_model_read_state(
    scope,
    writer,
    layout.retained_bytes,
    layout.execution_bytes,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  // The normal descriptor/read issuer is an ALTERNATIVE, never a second step.
  assert_true(
    prepare_client_node_model_read_layout(
      scope,
      compiled,
      definition,
      plan,
      Some(layout),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Read(Resource(@resources.SpentClaim))),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    claim_client_node_model_preparation_layout(
      read,
      compiled,
      definition,
      plan,
      Some(layout),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Read(Resource(@resources.SpentClaim))),
  )
  assert_true(
    advance_client_model_read_state(read, compiled, definition, plan, 17)
    is @resources.StateWriteComplete(work=17),
  )
  let consumer = claim_client_node_model_preparation_layout(
    read,
    compiled,
    definition,
    plan,
    Some(layout),
    installation,
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  stop_client_model_read_consumer(consumer).unwrap()
  assert_true(
    settle_client_model_read_consumer(consumer, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  settle_client_model_read_consumer(consumer, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}
