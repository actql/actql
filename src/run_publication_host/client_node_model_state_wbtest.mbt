///|
fn client_node_state_test_scope(
  planning : Int,
) -> (
  ClientCompiledRun,
  @publication.PublicationContract,
  ClientInferPlanGraph,
  @resources.Ledger,
  ClientModelReadScope,
  ClientNodeModelPreparationLayout,
) {
  let (compiled, definition, plan) = client_model_read_test_run("node-state")
  let layout = client_node_layout_test_declaration(plan)
  // These independent fixture envelopes test ownership, not physical capacity.
  let ledger = @resources.create_ledger({
    planning_work: planning,
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
  (compiled, definition, plan, ledger, scope, layout)
}

///|
fn client_node_state_test_prepare(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  layout : ClientNodeModelPreparationLayout,
  max_bytes? : Int = 1000,
) -> Result[ClientNodeModelStateWriter, ClientNodeModelStateIssue] {
  prepare_client_node_model_read_state(
    scope,
    compiled,
    definition,
    plan,
    Some(layout),
    client_node_layout_test_installation(),
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
    max_bytes,
    200,
    10,
  )
}

///|
test "Node original state Writer uses one descriptor and exact bounded work" {
  let expected = "[\"actql-original-ledger-state/0.1\",[\"17\",\"2\",\"3\",\"11\",\"7003\",\"3002\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"7003\",\"3002\",\"7003\",\"0\",\"2\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"],[\"1\",\"0\",\"0\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7000\",\"3000\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
  for quantum in [1, 17] {
    let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
      17,
    )
    let value = client_node_state_test_prepare(
      scope, compiled, definition, plan, layout,
    ).unwrap()
    let read = client_node_model_state_read(value).unwrap()
    assert_true(physical_equal(read, value.read.unwrap()))
    assert_true(
      finish_client_node_model_read_state(value, compiled, definition, plan)
      is Err(State(@resources.Terminal)),
    )
    assert_true(
      prepare_client_node_model_read_layout(
        scope,
        compiled,
        definition,
        plan,
        Some(layout),
        client_node_layout_test_installation(),
        layout.runtime_artifact_cid,
        layout.layout_artifact_cid,
        None,
      )
      is Err(Read(Resource(@resources.SpentClaim))),
    )
    assert_true(
      claim_client_model_read_preparation(
        read, compiled, definition, plan, 7000L, 3000L,
      )
      is Err(Resource(@resources.SpentClaim)),
    )
    let work = for work = 0 {
      if work >= 17 {
        break -2
      }
      match
        advance_client_node_model_read_state(
          value, compiled, definition, plan, quantum,
        ) {
        @resources.StateWriteContinue(work=spent) => continue work + spent
        @resources.StateWriteComplete(work=spent) => break work + spent
        @resources.StateWriteFailed(_, ..) => break -1
      }
    }
    assert_eq(work, 17)
    assert_eq(@resources.ledger_usage(ledger).planning_work, 17)
    let wire = finish_client_node_model_read_state(
      value, compiled, definition, plan,
    ).unwrap()
    assert_eq(wire, expected)
    assert_true(value.writer is None)
    assert_true(
      finish_client_node_model_read_state(value, compiled, definition, plan)
      is Err(State(@resources.Terminal)),
    )
    stop_client_node_model_read_state(value, scope, compiled, definition, plan).unwrap()
    settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
    assert_true(value.read is None)
    assert_true(
      client_node_model_state_read(value) is Err(State(@resources.Terminal)),
    )
    assert_true(
      finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
    )
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(wire, expected)
  }
}

///|
test "Node original state Writer rejects foreign and invalid inputs before issuance" {
  let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
    17,
  )
  let (foreign, foreign_definition, foreign_plan) = client_model_read_test_run(
    "node-state-foreign",
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    client_node_state_test_prepare(
      scope, compiled, foreign_definition, plan, layout,
    )
    is Err(Layout(Read(ForeignRun))),
  )
  assert_true(
    client_node_state_test_prepare(
      scope, foreign, foreign_definition, foreign_plan, layout,
    )
    is Err(Layout(Read(ForeignRun))),
  )
  assert_true(
    client_node_state_test_prepare(
      scope,
      compiled,
      definition,
      plan,
      layout,
      max_bytes=-1,
    )
    is Err(State(@resources.Encoding)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let value = client_node_state_test_prepare(
    scope, compiled, definition, plan, layout,
  ).unwrap()
  let current = @resources.ledger_usage(ledger)
  assert_true(
    advance_client_node_model_read_state(
      value, compiled, foreign_definition, plan, 1,
    )
    is @resources.StateWriteFailed(
      @resources.Original(@resources.ForeignOrigin),
      work=0
    ),
  )
  assert_true(
    finish_client_node_model_read_state(
      value, compiled, foreign_definition, plan,
    )
    is Err(State(@resources.Original(@resources.ForeignOrigin))),
  )
  assert_true(
    stop_client_node_model_read_state(
      value, scope, compiled, foreign_definition, plan,
    )
    is Err(ForeignRun),
  )
  assert_true(
    settle_client_node_model_read_state(
      value, compiled, foreign_definition, plan, true,
    )
    is Err(ForeignRun),
  )
  assert_eq(@resources.ledger_usage(ledger), current)
  assert_eq(@encode.writer_progress(value.writer.unwrap()), (0, 0, 0))
  stop_client_node_model_read_state(value, scope, compiled, definition, plan).unwrap()
  settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "Node original state Writer one short preserves scope without hidden read" {
  let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
    16,
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    client_node_state_test_prepare(scope, compiled, definition, plan, layout)
    is Err(State(@resources.Resource(@resources.PlanningLimit))),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_true(
    client_node_state_test_prepare(scope, compiled, definition, plan, layout)
    is Err(State(@resources.Original(@resources.ForeignOrigin))),
  )
}

///|
test "Node original state Writer encoding failure retains original cleanup responsibility" {
  let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
    17,
  )
  let value = client_node_state_test_prepare(
    scope,
    compiled,
    definition,
    plan,
    layout,
    max_bytes=1,
  ).unwrap()
  assert_true(
    advance_client_node_model_read_state(value, compiled, definition, plan, 1)
    is @resources.StateWriteFailed(@resources.Encoding, work=1),
  )
  assert_true(
    finish_client_node_model_read_state(value, compiled, definition, plan)
    is Err(State(@resources.Terminal)),
  )
  assert_true(
    settle_client_node_model_read_state(
      value, compiled, definition, plan, false,
    )
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_true(value.read is Some(_))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 7003L)
  stop_client_node_model_read_state(value, scope, compiled, definition, plan).unwrap()
  settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
  assert_true(value.read is None && value.writer is None)
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "Node original state Writer stop and retry do not recharge or retain retired graph" {
  let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
    17,
  )
  let value = client_node_state_test_prepare(
    scope, compiled, definition, plan, layout,
  ).unwrap()
  assert_true(
    advance_client_node_model_read_state(value, compiled, definition, plan, 0)
    is @resources.StateWriteFailed(@resources.InvalidQuantum, work=0),
  )
  assert_true(
    advance_client_node_model_read_state(value, compiled, definition, plan, 1)
    is @resources.StateWriteContinue(work=1),
  )
  let before = @resources.ledger_usage(ledger)
  stop_client_node_model_read_state(value, scope, compiled, definition, plan).unwrap()
  assert_true(value.writer is None && value.read is Some(_))
  assert_true(
    advance_client_node_model_read_state(value, compiled, definition, plan, 1)
    is @resources.StateWriteFailed(@resources.Terminal, work=0),
  )
  assert_true(
    settle_client_node_model_read_state(
      value, compiled, definition, plan, false,
    )
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
  assert_true(value.read is None && value.writer is None)
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).planning_work, 17)
}

///|
test "Node original state Writer does not follow the normal descriptor issuer" {
  let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
    17,
  )
  let read = prepare_client_node_model_read_layout(
    scope,
    compiled,
    definition,
    plan,
    Some(layout),
    client_node_layout_test_installation(),
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    client_node_state_test_prepare(scope, compiled, definition, plan, layout)
    is Err(State(@resources.Original(@resources.SpentClaim))),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  stop_client_model_read_checked(scope, read, compiled, definition, plan).unwrap()
  settle_client_model_read_checked(read, compiled, definition, plan, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}
