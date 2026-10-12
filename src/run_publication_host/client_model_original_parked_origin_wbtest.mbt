///|
fn client_parked_origin_test_prepare() -> (
  ClientCompiledRun,
  @publication.PublicationContract,
  ClientInferPlanGraph,
  ClientModelReadScope,
  ClientModelReadConsumer,
  ClientModelResourcePark,
) {
  let (compiled, definition, plan, _, scope) = client_model_state_test_scope(17)
  let read = prepare_client_model_read(scope, 7L, 5L).unwrap()
  let consumer = claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  let park = park_client_model_read_consumer(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  (compiled, definition, plan, scope, consumer, park)
}

///|
test "parked original origin rechecks all eleven actual fields without enabling initial admission" {
  let (compiled, definition, plan, scope, consumer, park) = client_parked_origin_test_prepare()
  let layout = client_node_layout_test_declaration(plan)
  let wire = client_original_origin_test_wire(
    compiled, definition, plan, layout,
  )
  let document = @publication.read_model_original_resource_document(
    wire, 10000, 1000, 16,
  ).unwrap()
  let before = @resources.ledger_usage(scope.ledger)
  let check = fn(value) {
    check_client_model_original_parked_origin(
      park,
      scope,
      compiled,
      definition,
      plan,
      value,
      Some(layout),
      client_node_layout_test_installation(),
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
  }
  assert_false(@resources.original_ledger_inventory_available(scope.identity))
  assert_true(check(document) is Ok(_))
  assert_true(
    check_client_model_original_checked_origin(
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
    )
    is Err(Unavailable),
  )
  for
    field in [
      "run_id", "run_definition_cid", "prepared_invocation_cid", "host_policy_cid",
      "execution_context_cid", "program_definition_cid", "parameter_values_cid",
      "barrier_cid", "runtime_artifact_cid", "layout_artifact_cid", "response_profile_cid",
    ] {
    let old = @publication.model_original_resource_origin_field(document, field).unwrap()
    let changed = wire.replace(
      old="\"" + field + "\":\"" + old + "\"",
      new="\"" +
        field +
        "\":\"" +
        (if field == "run_id" {
          "foreign-run"
        } else {
          "sha256:" + "0".repeat(64)
        }) +
        "\"",
    )
    let value = @publication.read_model_original_resource_document(
      changed, 10000, 1000, 16,
    ).unwrap()
    assert_true(check(value) is Err(OriginMismatch(actual)) && actual == field)
    assert_eq(@resources.ledger_usage(scope.ledger), before)
  }
  assert_true(
    settle_client_model_read_consumer(consumer, false)
    is Err(Resource(@resources.Resource(@resources.ResourceParked))),
  )
  assert_true(
    client_model_resource_park_current(park, scope, compiled, definition, plan)
    is Some(_),
  )
  // Original admission, current census and Store/journal authority remain
  // separate. No real invalidation receipt exists; retain original custody.
}

///|
test "parked original origin checks twelfth Store data without granting physical custody" {
  let (compiled, definition, plan, scope, _, park) = client_parked_origin_test_prepare()
  let layout = client_node_layout_test_declaration(plan)
  let document = client_original_storage_test_document(
    compiled, definition, plan, layout,
  )
  let storage = @publication.seal_run_evidence_value(
    "model_original_storage_binding",
    client_original_storage_test_body(),
    2048,
    32,
    2,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(storage),
    "sha256:78c803436a1ff3cb68ebd954f539a2353049544615e942931d7aa0ab6839e2a3",
  )
  let before = @resources.ledger_usage(scope.ledger)
  let check = fn(value) {
    check_client_model_original_parked_storage_origin(
      park,
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
      value,
    )
  }
  assert_true(check(storage) is Ok(_))
  let copy = @publication.admit_run_evidence_value(
    "model_original_storage_binding",
    @publication.run_evidence_value_json(storage),
    2048,
    32,
    2,
  ).unwrap()
  // Equal data does not prove SAME physical port or exact opaque handle.
  assert_true(check(copy) is Ok(_))
  assert_true(
    check(@publication.run_publication_prepared(compiled.admission))
    is Err(OriginMismatch("storage_binding_cid")),
  )
  let changed = @publication.seal_run_evidence_value(
    "model_original_storage_binding",
    client_original_storage_test_body().replace(
      old="\"key_generation_cid\":\"sha256:" + "2".repeat(64) + "\"",
      new="\"key_generation_cid\":\"sha256:" + "3".repeat(64) + "\"",
    ),
    2048,
    32,
    2,
  ).unwrap()
  assert_true(check(changed) is Err(OriginMismatch("storage_binding_cid")))
  // This installed Profile closes the namespace at evidence admission, before
  // the origin guard. Preserve that stronger refusal rather than fabricate
  // an admitted foreign evidence value or loosen the existing schema.
  assert_true(
    @publication.seal_run_evidence_value(
      "model_original_storage_binding",
      client_original_storage_test_body().replace(
        old="\"private_namespace\":\"local-continuation-private\"",
        new="\"private_namespace\":\"foreign-private\"",
      ),
      2048,
      32,
      2,
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  assert_false(@resources.original_ledger_inventory_available(scope.identity))
}

///|
test "parked original origin rejects foreign lifecycle and missing or replaced layout" {
  let (compiled, definition, plan, scope, consumer, park) = client_parked_origin_test_prepare()
  let (other, other_definition, other_plan, other_scope, _, other_park) = client_parked_origin_test_prepare()
  let (_, foreign_definition, _) = client_model_read_test_run(
    "foreign-parked-origin",
  )
  let layout = client_node_layout_test_declaration(plan)
  let installation = client_node_layout_test_installation()
  let document = @publication.read_model_original_resource_document(
    client_original_origin_test_wire(compiled, definition, plan, layout),
    10000,
    1000,
    16,
  ).unwrap()
  let before = @resources.ledger_usage(scope.ledger)
  assert_true(
    check_client_model_original_parked_origin(
      park,
      scope,
      compiled,
      foreign_definition,
      plan,
      document,
      Some(layout),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(ForeignRun),
  )
  assert_true(
    check_client_model_original_parked_origin(
      other_park,
      scope,
      compiled,
      definition,
      plan,
      document,
      Some(layout),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Unavailable),
  )
  assert_true(
    check_client_model_original_parked_origin(
      park,
      other_scope,
      other,
      other_definition,
      other_plan,
      document,
      Some(layout),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Unavailable),
  )
  assert_true(
    check_client_model_original_parked_origin(
      park,
      scope,
      compiled,
      definition,
      plan,
      document,
      None,
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Layout(Unavailable)),
  )
  assert_true(
    check_client_model_original_parked_origin(
      park,
      scope,
      compiled,
      definition,
      plan,
      document,
      Some(layout),
      { ..installation, builder_revision: "2", },
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Layout(_)),
  )
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  // Only the inner Resource transition is exercised here. This fixture does
  // not authenticate actual journal COMMIT: the real A caller must do that.
  let request = begin_client_model_resource_invalidation(
    park, scope, compiled, definition, plan,
  ).unwrap()
  consume_client_model_resource_invalidation(
    request, park, scope, compiled, definition, plan,
  ).unwrap()
  assert_true(
    check_client_model_original_parked_origin(
      park,
      scope,
      compiled,
      definition,
      plan,
      document,
      Some(layout),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Unavailable),
  )
  assert_true(settle_client_model_read_consumer(consumer, false) is Err(_))
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  settle_client_model_read_consumer(consumer, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_true(
    check_client_model_original_parked_origin(
      park,
      scope,
      compiled,
      definition,
      plan,
      document,
      Some(layout),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Unavailable),
  )
}
