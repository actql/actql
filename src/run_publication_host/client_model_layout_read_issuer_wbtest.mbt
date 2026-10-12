///|
test "checked Node layout read issuer validates originals before descriptor and byte admission" {
  let (compiled, definition, plan) = client_model_read_test_run("layout-read")
  let (foreign, foreign_definition, foreign_plan) = client_model_read_test_run(
    "foreign-layout-read",
  )
  let layout = client_node_layout_test_declaration(plan)
  let installation = client_node_layout_test_installation()
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 7003L,
    execution_bytes: 3002L,
  }).unwrap()
  @resources.configure_quantities(ledger, {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 2, 0, 0,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let quantities = @resources.quantity_usage(ledger)
  assert_true(
    prepare_client_node_model_read_layout(
      scope,
      compiled,
      definition,
      plan,
      None,
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Unavailable),
  )
  assert_true(
    prepare_client_node_model_read_layout(
      scope,
      compiled,
      foreign_definition,
      plan,
      Some(layout),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Read(ForeignRun)),
  )
  assert_true(
    prepare_client_node_model_read_layout(
      scope,
      foreign,
      foreign_definition,
      foreign_plan,
      Some(client_node_layout_test_declaration(foreign_plan)),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Read(ForeignRun)),
  )
  assert_true(
    prepare_client_node_model_read_layout(
      scope,
      compiled,
      definition,
      plan,
      Some(layout),
      installation,
      "sha256:" + "f".repeat(64),
      layout.layout_artifact_cid,
      None,
    )
    is Err(RuntimeMismatch),
  )
  assert_true(
    prepare_client_node_model_read_layout(
      scope,
      compiled,
      definition,
      plan,
      Some({ ..layout, parameter_values_cid: "sha256:" + "f".repeat(64), }),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(PreparationMismatch),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.quantity_usage(ledger), quantities)
  let read = prepare_client_node_model_read_layout(
    scope,
    compiled,
    definition,
    plan,
    Some(layout),
    installation,
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 7003L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 3002L)
  assert_eq(@resources.quantity_usage(ledger), quantities)
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
  enter_client_model_read_consumer(
    consumer, compiled, definition, plan, 7000L, 3000L,
  ).unwrap()
  stop_client_model_read(read).unwrap()
  assert_true(
    settle_client_model_read(read, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 7003L)
  settle_client_model_read(read, true).unwrap()
  assert_false(
    client_model_read_consumer_available(
      consumer, compiled, definition, plan, 7000L, 3000L,
    ),
  )
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
}

///|
test "checked Node layout read issuer uses exact complete same Ledger envelope" {
  let (compiled, definition, plan) = client_model_read_test_run("layout-read")
  let layout = client_node_layout_test_declaration(plan)
  let installation = client_node_layout_test_installation()
  // Independent predicate fixture only: no physical normal policy. The read
  // needs 7000/3000 in addition to its already funded 3/2 bootstrap; a one-byte
  // shortage on either axis must not reserve a reduced/fallback envelope.
  for
    (retained_limit, execution_limit) in [
      (7002L, 3002L),
      (7003L, 3001L),
      (7003L, 3002L),
    ] {
    let ledger = @resources.create_ledger({
      planning_work: 3,
      attempts: 2,
      holdings: 3,
      transfer_bytes: 11L,
      retained_bytes: retained_limit,
      execution_bytes: execution_limit,
    }).unwrap()
    let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
    let scope = begin_client_model_read_scope(
      compiled, definition, plan, ledger, bootstrap, 2, 0, 0,
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let issued = prepare_client_node_model_read_layout(
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
    if retained_limit == 7002L {
      assert_true(
        issued
        is Err(Read(Resource(@resources.Resource(@resources.RetentionLimit)))),
      )
      assert_eq(@resources.ledger_usage(ledger), before)
    } else if execution_limit == 3001L {
      assert_true(
        issued
        is Err(Read(Resource(@resources.Resource(@resources.ExecutionLimit)))),
      )
      assert_eq(@resources.ledger_usage(ledger), before)
    } else {
      let read = issued.unwrap()
      assert_true(
        client_model_read_preparation_available(
          read,
          compiled,
          definition,
          plan,
          3000L,
          retained_bytes=7000L,
        ),
      )
      assert_false(
        client_model_read_preparation_available(
          read,
          compiled,
          definition,
          plan,
          3001L,
          retained_bytes=7000L,
        ),
      )
      stop_client_model_read(read).unwrap()
      settle_client_model_read(read, true).unwrap()
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 3L)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 2L)
    }
    assert_true(
      @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
    )
  }
}
