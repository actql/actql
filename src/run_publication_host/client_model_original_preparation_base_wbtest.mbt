///|
fn client_preparation_base_test_resource_wire() -> String {
  // Independent original node-state vector preserved from the pre-existing
  // Writer test. These fixture amounts are not a physical profile adoption.
  "[\"actql-original-ledger-state/0.1\",[\"17\",\"2\",\"3\",\"11\",\"7003\",\"3002\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"7003\",\"3002\",\"7003\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],\"-3\",[\"1\",\"0\",\"0\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null],[[\"-2\",\"0\",\"7000\",\"3000\",true,false,null,null,[false,false,false],null]],[],[]]"
}

///|
fn client_preparation_base_test_expected(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  layout : ClientNodeModelPreparationLayout,
) -> String {
  // Existing independent checked-origin fixture, not the new getter/finisher.
  // The resource payload/CID are separately fixed pre-existing expected bytes.
  client_original_origin_test_wire(compiled, definition, plan, layout)
  .replace(old="\"run_id\":\"state-original\"", new="\"run_id\":\"node-state\"")
  .replace(
    old=client_model_state_match_test_wire(),
    new=client_preparation_base_test_resource_wire(),
  )
  .replace(
    old="sha256:274329df872dc6b95ba33089f7a822419cb91c3169d893342df24fa6c2126da2",
    new="sha256:e6c6b87dc82a5b9e10b90e5546e57cf6d805587584df7cd796f8a61608350967",
  )
  .replace(
    old="\"storage_binding_cid\":\"sha256:" + "b".repeat(64) + "\"",
    new="\"storage_binding_cid\":\"sha256:78c803436a1ff3cb68ebd954f539a2353049544615e942931d7aa0ab6839e2a3\"",
  )
}

///|
fn client_preparation_base_test_finish(
  value : ClientNodeModelStateWriter,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  layout : ClientNodeModelPreparationLayout,
  max_bytes? : Int = 10000,
  max_nodes? : Int = 1000,
  max_depth? : Int = 16,
) -> Result[String, ClientModelOriginalPreparationBaseIssue] {
  let storage = @publication.seal_run_evidence_value(
    "model_original_storage_binding",
    client_original_storage_test_body(),
    2048,
    32,
    2,
  ).unwrap()
  finish_client_model_original_preparation_base(
    value,
    scope,
    compiled,
    definition,
    plan,
    Some(layout),
    client_node_layout_test_installation(),
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
    storage,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
test "original preparation base refuses insufficient original nominal envelope without consuming Writer" {
  let (compiled, definition, plan, ledger, scope) = client_model_state_test_scope(
    17,
  )
  let layout = client_node_layout_test_declaration(plan)
  let writer = @encode.writer(1000, 200, 10)
  let read = prepare_client_model_read_state(scope, writer, 7L, 5L).unwrap()
  assert_true(
    advance_client_model_read_state(read, compiled, definition, plan, 17)
    is @resources.StateWriteComplete(work=17),
  )
  let value : ClientNodeModelStateWriter = {
    read: Some(read),
    writer: Some(writer),
  }
  let before = @resources.ledger_usage(ledger)
  assert_true(
    client_preparation_base_test_finish(
      value, scope, compiled, definition, plan, layout,
    )
    is Err(Origin(Unavailable)),
  )
  assert_true(value.writer is Some(_) && value.read is Some(_))
  assert_eq(@resources.ledger_usage(ledger), before)
  settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "original preparation base emits exact original Writer data with null cut once" {
  for quantum in [1, 17] {
    let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
      17,
    )
    let value = client_node_state_test_prepare(
      scope, compiled, definition, plan, layout,
    ).unwrap()
    let read = client_node_model_state_read(value).unwrap()
    let work = for work = 0 {
      match
        advance_client_node_model_read_state(
          value, compiled, definition, plan, quantum,
        ) {
        @resources.StateWriteContinue(work=spent) => continue work + spent
        @resources.StateWriteComplete(work=spent) => break work + spent
        _ => break -1
      }
    }
    assert_eq(work, 17)
    let before = @resources.ledger_usage(ledger)
    let expected = client_preparation_base_test_expected(
      compiled, definition, plan, layout,
    )
    // ASCII fixture: this independent expected length is the exact outer byte
    // ceiling. The finisher cannot replace/drop/normalize the embedded body.
    let wire = client_preparation_base_test_finish(
      value,
      scope,
      compiled,
      definition,
      plan,
      layout,
      max_bytes=expected.length(),
    ).unwrap()
    assert_eq(wire, expected)
    assert_eq(@resources.ledger_usage(ledger), before)
    let document = @publication.read_model_original_resource_document(
      wire, 10000, 1000, 16,
    ).unwrap()
    check_client_model_original_storage_origin(
      scope,
      compiled,
      definition,
      plan,
      document,
      Some(layout),
      client_node_layout_test_installation(),
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
      @publication.seal_run_evidence_value(
        "model_original_storage_binding",
        client_original_storage_test_body(),
        2048,
        32,
        2,
      ).unwrap(),
    ).unwrap()
    assert_true(client_model_read_available(read, compiled, definition, plan))
    assert_true(value.writer is None && value.read is Some(_))
    assert_true(
      client_preparation_base_test_finish(
        value, scope, compiled, definition, plan, layout,
      )
      is Err(State(State(@resources.Terminal))),
    )
    // Data/shape and matching origin do not create a Store ACK/current cut.
    settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
    assert_true(value.read is None)
    assert_true(
      finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
    )
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(wire, expected)
  }
}

///|
test "original preparation base rejects unfinished foreign and invalid arguments before consuming Writer" {
  let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
    17,
  )
  let value = client_node_state_test_prepare(
    scope, compiled, definition, plan, layout,
  ).unwrap()
  assert_true(
    client_preparation_base_test_finish(
      value, scope, compiled, definition, plan, layout,
    )
    is Err(State(State(@resources.Terminal))),
  )
  assert_true(
    advance_client_node_model_read_state(value, compiled, definition, plan, 17)
    is @resources.StateWriteComplete(work=17),
  )
  let (
    other_compiled,
    other_definition,
    other_plan,
    other_ledger,
    other_scope,
    _,
  ) = client_node_state_test_scope(17)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    client_preparation_base_test_finish(
      value, other_scope, compiled, definition, plan, layout,
    )
    is Err(Origin(ForeignRun)),
  )
  let (_, foreign_definition, _) = client_model_read_test_run("base-foreign")
  assert_true(
    client_preparation_base_test_finish(
      value, scope, compiled, foreign_definition, plan, layout,
    )
    is Err(Origin(ForeignRun)),
  )
  assert_true(
    client_preparation_base_test_finish(
      value,
      scope,
      compiled,
      definition,
      plan,
      layout,
      max_bytes=-1,
    )
    is Err(InvalidBounds),
  )
  assert_true(value.writer is Some(_))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    client_preparation_base_test_finish(
      value, scope, compiled, definition, plan, layout,
    )
    is Ok(_),
  )
  settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  // The separate original scope was not mutated or consumed by the refusal.
  assert_eq(@resources.ledger_usage(other_ledger).reserved_retention_bytes, 3L)
  assert_true(
    finish_client_model_read_scope(
      other_scope, other_compiled, other_definition, other_plan, true,
    ).unwrap(),
  )
}

///|
test "original preparation base preserves actual raw Unicode and newline Run ID" {
  let run_id = "base-e\u{0301}\r\n"
  let (compiled, definition, plan) = client_model_read_test_run(run_id)
  let layout = client_node_layout_test_declaration(plan)
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
  let value = client_node_state_test_prepare(
    scope, compiled, definition, plan, layout,
  ).unwrap()
  assert_true(
    advance_client_node_model_read_state(value, compiled, definition, plan, 17)
    is @resources.StateWriteComplete(work=17),
  )
  let expected = client_preparation_base_test_expected(
    compiled, definition, plan, layout,
  ).replace(
    old="\"run_id\":\"node-state\"",
    new="\"run_id\":\"base-e\u{0301}\\r\\n\"",
  )
  let wire = client_preparation_base_test_finish(
    value, scope, compiled, definition, plan, layout,
  ).unwrap()
  assert_eq(wire, expected)
  let document = @publication.read_model_original_resource_document(
    wire, 10000, 1000, 16,
  ).unwrap()
  assert_eq(
    @publication.model_original_resource_origin_field(document, "run_id"),
    Some(run_id),
  )
  assert_true(wire.contains("\"cut\":null"))
  settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "original preparation base output limits keep same stopped read pending until actual cleanup" {
  for kind in ["bytes", "nodes", "depth"] {
    let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
      17,
    )
    let value = client_node_state_test_prepare(
      scope, compiled, definition, plan, layout,
    ).unwrap()
    assert_true(
      advance_client_node_model_read_state(
        value, compiled, definition, plan, 17,
      )
      is @resources.StateWriteComplete(work=17),
    )
    let read = client_node_model_state_read(value).unwrap()
    let expected = client_preparation_base_test_expected(
      compiled, definition, plan, layout,
    )
    let before = @resources.ledger_usage(ledger)
    assert_true(
      client_preparation_base_test_finish(
        value,
        scope,
        compiled,
        definition,
        plan,
        layout,
        max_bytes=if kind == "bytes" { expected.length() - 1 } else { 10000 },
        max_nodes=if kind == "nodes" { 1 } else { 1000 },
        max_depth=if kind == "depth" { 0 } else { 16 },
      )
      is Err(Encoding),
    )
    assert_true(value.writer is None && value.read is Some(_))
    assert_false(client_model_read_available(read, compiled, definition, plan))
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_true(
      settle_client_node_model_read_state(
        value, compiled, definition, plan, false,
      )
      is Err(Resource(@resources.CleanupPending)),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_true(
      client_preparation_base_test_finish(
        value, scope, compiled, definition, plan, layout,
      )
      is Err(_),
    )
    settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
    assert_true(value.read is None && value.writer is None)
    assert_true(
      finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
    )
  }
}
