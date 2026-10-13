///|
test "pre-restore origin DATA guard compares all eleven checked getters without a Scope argument" {
  let (compiled, definition, plan, ledger, _) = client_model_state_test_scope(17)
  let layout = client_node_layout_test_declaration(plan)
  let wire = client_original_origin_test_wire(compiled, definition, plan, layout)
  let document = @publication.read_model_original_resource_document(
    wire, 10000, 1000, 16,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let check = fn(value) {
    check_client_model_original_pre_restore_origin(
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
  assert_true(check(document) is Ok(_))
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
          "other-run"
        } else {
          "sha256:" + "0".repeat(64)
        }) +
        "\"",
    )
    assert_true(
      check(
        @publication.read_model_original_resource_document(
          changed, 10000, 1000, 16,
        ).unwrap(),
      )
      is Err(OriginMismatch(actual)) && actual == field,
    )
    assert_eq(@resources.ledger_usage(ledger), before)
  }
  // The independently changed storage field still passes this DATA-only
  // subset: success is explicitly NOT actual same-Store custody admission.
  let changed = wire.replace(
    old="\"storage_binding_cid\":\"sha256:" + "b".repeat(64) + "\"",
    new="\"storage_binding_cid\":\"sha256:" + "c".repeat(64) + "\"",
  )
  assert_true(
    check(@publication.read_model_original_resource_document(
      changed, 10000, 1000, 16,
    ).unwrap())
    is Ok(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
}

///|
test "pre-restore origin DATA guard refuses foreign checked Run and missing layout" {
  let (compiled, definition, plan, ledger, _) = client_model_state_test_scope(17)
  let (other, _, _, _, _) = client_model_state_test_scope(17)
  let layout = client_node_layout_test_declaration(plan)
  let document = @publication.read_model_original_resource_document(
    client_original_origin_test_wire(compiled, definition, plan, layout),
    10000,
    1000,
    16,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    check_client_model_original_pre_restore_origin(
      other,
      definition,
      plan,
      document,
      Some(layout),
      client_node_layout_test_installation(),
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(ForeignRun),
  )
  assert_true(
    check_client_model_original_pre_restore_origin(
      compiled,
      definition,
      plan,
      document,
      None,
      client_node_layout_test_installation(),
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Layout(Unavailable)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
}
