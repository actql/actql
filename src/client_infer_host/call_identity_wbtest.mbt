///|
fn call_identity_fixture(
  prepared : @publication_host.PreparedClientProgram,
) -> (
  @input.ClientInferInputExecution,
  @relation.PreparedInferRows,
  @publication_host.ClientInferCallScope,
  String,
) raise {
  let limits = standard_limits()
  let input = @input.start_client_infer_input(
    prepared,
    0,
    2,
    infer_fixture_registry,
    infer_fixture_values,
    limits.input,
    limits.measurement,
    limits.mapping,
  ).unwrap()
  let mut rows = None
  for _ in 0..<2000 {
    match @input.advance_client_infer_input(input, 1).unwrap() {
      @input.Complete(value, ..) => {
        rows = Some(value)
        break
      }
      @input.Continue(_) => ()
      _ => abort("ordinary Program prefix failed")
    }
  }
  let rows = rows.unwrap()
  let completed = @input.client_infer_completed_input(input).unwrap()
  // The receipt comes from the actual bounded prefix, not manually created
  // completion state, and identity traversal shares its advance quantum.
  let wire : @relation.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }
  let stream = @relation.start_completed_relation_identity_scan(
    completed,
    10,
    limits.output_values,
    wire,
    wire,
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    10000,
    10000,
  ).unwrap()
  while !@relation.advance_completed_relation_identity_scan(stream, 1).unwrap().0 {
    ()
  }
  let receipt = @relation.finish_completed_relation_identity_scan(stream).unwrap()
  let plan = call_identity_plan(prepared)
  let scope = @publication_host.issue_prepared_client_infer_call_scope(
    prepared, plan, 2, completed, receipt, 100000, 10000, 100,
  ).unwrap()
  assert_true(
    @publication_host.issue_prepared_client_infer_call_scope(
      fixture_prepared(),
      plan,
      2,
      completed,
      receipt,
      100000,
      10000,
      100,
    )
    is Err(@publication_host.ForeignOwner),
  )
  assert_true(
    @publication_host.issue_prepared_client_infer_call_scope(
      prepared, plan, 1, completed, receipt, 100000, 10000, 100,
    )
    is Err(@publication_host.ForeignOwner),
  )
  (
    input,
    rows,
    scope,
    @publication_host.client_infer_plan_graph_request_cid(plan),
  )
}

///|
fn call_identity_plan(
  prepared : @publication_host.PreparedClientProgram,
) -> @publication_host.ClientInferPlanGraph {
  let execution_wire =
    #|{"backoff_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","default_publication":"outcomes","max_attempts_per_slot":2,"max_total_attempts":4,"max_total_cost_units":0,"max_total_duration_ms":1000,"max_total_token_reservation":128,"max_total_wire_bytes":2048,"media_input_contracts":{},"model_task_contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","retry_classification_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","self_cid":"sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da","version":"actql-model-execution-contract/0.1"}
  let model_execution = @publication_host.read_prepared_client_infer_model_execution(
    prepared,
    2,
    @utf8.encode(execution_wire),
    "sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
  @publication_host.issue_prepared_client_infer_plan_graph(
    prepared,
    2,
    model_execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  ).unwrap()
}

///|
test "normal Infer owner identifies its own completed prefix before scoped dispatch" {
  let slots : Array[String] = []
  for _ in 0..<2 {
    let prepared = fixture_prepared()
    let plan = call_identity_plan(prepared)
    let calls = Ref(0)
    let provider = @model.install_model_provider("models/fixture", request => {
      calls.val += 1
      slots.push(request.slot_cid)
      Ok({
        value: @admitted.object_value([
          ("reason", @admitted.null_value()),
          ("risk", @admitted.text_value("high", 100).unwrap()),
        ]).unwrap(),
        provider_model: "fixture-risk-model",
        provider_request_id: "request-1",
        input_tokens: 1L,
        output_tokens: 2L,
        observed_at: "2026-10-01T00:00:00.000Z",
      })
    }).unwrap()
    let active = start(
      prepared,
      2,
      infer_fixture_registry,
      infer_fixture_values,
      provider,
      @publication_host.client_infer_plan_graph_request_cid(plan),
      standard_limits(),
      plan=Some(plan),
    ).unwrap()
    assert_true(fixture_finish(active) is Complete(_, ..))
    assert_eq(calls.val, 1)
    let provisional = capture(active).unwrap()
    assert_eq(provisional.captures[0].slot_cid, slots[slots.length() - 1])
    assert_eq(
      provisional.captures[0].input_key_cid,
      "sha256:042a400915c1e3c348ec713c0e6b496f28dcde211e33c64fbada352b6e6e7011",
    )
    assert_true(call_scope(active) is Some(_))
    assert_true(cleanup(active).unwrap())
    assert_true(call_scope(active) is None)
    assert_eq(calls.val, 1)
  }
  assert_eq(slots[0], slots[1])
}

///|
test "scoped Infer identity cancellation retains input and makes no model call" {
  let payload = Array::make(500, "0").join(",")
  let source = infer_fixture_program
    .replace(
      old="\"text\":{\"type\":\"string\",\"nullable\":true}",
      new="\"payload\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}},\"text\":{\"type\":\"string\",\"nullable\":true}",
    )
    .replace(
      old="\"text\":\"hello\"",
      new="\"text\":\"hello\",\"payload\":[" + payload + "]",
    )
  assert_true(source != infer_fixture_program)
  let environment_wire = infer_fixture_environment
    .replace(
      old="\"max_nested_value_bytes\":1000",
      new="\"max_nested_value_bytes\":10000",
    )
    .replace(
      old="\"max_artifact_bytes\":1000",
      new="\"max_artifact_bytes\":10000",
    )
  let prepared = fixture_prepared(source~, environment_wire~)
  let plan = call_identity_plan(prepared)
  let calls = Ref(0)
  let provider = @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
    Err(@model.ProviderError)
  }).unwrap()
  let active = start(
    prepared,
    2,
    infer_fixture_registry,
    infer_fixture_values,
    provider,
    @publication_host.client_infer_plan_graph_request_cid(plan),
    standard_limits(),
    plan=Some(plan),
  ).unwrap()
  for _ in 0..<20000 {
    if identity_pending(active) {
      break
    }
    assert_true(advance(active, 1).unwrap() is Continue(_))
  }
  assert_true(identity_pending(active))
  for _ in 0..<100 {
    assert_true(advance(active, 1).unwrap() is Continue(_))
  }
  assert_true(identity_pending(active))
  let completed = @input.client_infer_completed_input(active.input).unwrap()
  assert_true(cancel(active))
  assert_true(@relation.completed_output_available(completed))
  assert_true(!cleanup(active).unwrap())
  assert_true(advance(active, 1).unwrap() is Stopped(_))
  assert_eq(calls.val, 0)
  assert_true(acquire_output(active) is None)
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
  assert_true(
    start(
      fixture_prepared(),
      2,
      infer_fixture_registry,
      infer_fixture_values,
      provider,
      @publication_host.client_infer_plan_graph_request_cid(plan),
      standard_limits(),
      plan=Some(plan),
    )
    is Err(Model(@model.RequestIdentity)),
  )
}

///|
test "checked call identity survives reconstruction without a runtime row position" {
  let identities : Array[String] = []
  for index in 0..<3 {
    let prepared = if index == 2 {
      fixture_prepared(
        source=infer_fixture_program.replace(old="hello", new="changed"),
      )
    } else {
      fixture_prepared()
    }
    let (input, rows, scope, fixed) = call_identity_fixture(prepared)
    let calls = Ref(0)
    let slots : Array[String] = []
    let provider = @model.install_model_provider("models/fixture", request => {
      calls.val += 1
      slots.push(request.slot_cid)
      Ok({
        value: @admitted.object_value([
          ("reason", @admitted.null_value()),
          ("risk", @admitted.text_value("high", 100).unwrap()),
        ]).unwrap(),
        provider_model: "fixture-risk-model",
        provider_request_id: "request-1",
        input_tokens: 1L,
        output_tokens: 2L,
        observed_at: "2026-10-01T00:00:00.000Z",
      })
    }).unwrap()
    assert_true(
      @model.start_model_execution(
        rows,
        provider,
        "sha256:" + "f".repeat(64),
        standard_limits().model,
        call_scope=Some(scope),
      )
      is Err(@model.RequestIdentity),
    )
    let active = @model.start_model_execution(
      rows,
      provider,
      fixed,
      standard_limits().model,
      call_scope=Some(scope),
    ).unwrap()
    let mut terminal = false
    for _ in 0..<2000 {
      match @model.advance_model_execution(active, 1).unwrap() {
        @model.Completed(bundle, _, _) => {
          assert_eq(calls.val, 1)
          assert_eq(bundle.captures[0].slot_cid, slots[0])
          // Independent canonical hash of the typed string key contract/value
          // and authored field name, not the private raw key array spelling.
          assert_eq(
            bundle.captures[0].input_key_cid,
            "sha256:042a400915c1e3c348ec713c0e6b496f28dcde211e33c64fbada352b6e6e7011",
          )
          identities.push(slots[0])
          terminal = true
          break
        }
        @model.Continue(_, _) => ()
        _ => abort("model fixture failed")
      }
    }
    assert_true(terminal)
    assert_true(@model.cleanup_model_execution(active).unwrap())
    assert_true(@input.cleanup_client_infer_input(input).unwrap())
    assert_true(@input.client_infer_completed_input(input) is None)
    assert_eq(calls.val, 1)
  }
  assert_eq(identities[0], identities[1])
  assert_true(identities[0] != identities[2])
}
