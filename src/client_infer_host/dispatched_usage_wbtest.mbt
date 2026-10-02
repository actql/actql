///|
test "dispatched usage survives invalid responses cancellation and cleanup" {
  let two = infer_fixture_program.replace(
    old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"hello\"}]",
  )
  // The installed request ceiling is 1000 and the response ceiling is 65536.
  // Neither is an observation of bytes actually sent or received.
  let per_call = 66536L
  for variant in ["identity", "shape", "nodes", "cancel"] {
    let calls = Ref(0)
    let reference : Ref[Execution?] = Ref(None)
    let provider = @model.install_model_provider("models/fixture", _ => {
      calls.val += 1
      if variant == "cancel" {
        cancel(reference.val.unwrap()) |> ignore
      }
      Ok({
        value: if variant == "shape" {
          @admitted.text_value("invalid output object", 100).unwrap()
        } else {
          @admitted.object_value([
            ("reason", @admitted.null_value()),
            ("risk", @admitted.text_value("high", 100).unwrap()),
          ]).unwrap()
        },
        provider_model: if variant == "identity" {
          ""
        } else {
          "fixture"
        },
        provider_request_id: "request-a",
        input_tokens: 1L,
        output_tokens: 2L,
        observed_at: "2026-10-01T00:00:00.000Z",
      })
    }).unwrap()
    let base = standard_limits()
    let limits = if variant == "nodes" {
      {
        ..base,
        model: {
          ..base.model,
          value_limits: { ..base.model.value_limits, max_nodes: 2, },
        },
      }
    } else {
      base
    }
    let active = start(
      fixture_prepared(source=two),
      2,
      infer_fixture_registry,
      infer_fixture_values,
      provider,
      "sha256:" + "1".repeat(64),
      limits,
    ).unwrap()
    reference.val = Some(active)
    let poll = fixture_finish(active)
    match variant {
      "identity" =>
        assert_true(poll is Failed(Model(@model.OutputIdentity), ..))
      "shape" | "nodes" =>
        assert_true(poll is Failed(Model(@model.OutputValue), ..))
      "cancel" => assert_true(poll is Stopped(_))
      _ => abort("unknown test variant")
    }
    assert_eq(calls.val, 1)
    assert_true(acquire_output(active) is None)
    assert_true(acquire_capture(active) is None)
    let model = active.model.unwrap()
    let before = @model.model_execution_resource_usage(model)
    assert_eq(before.attempts, 2)
    assert_eq(before.transferred_bytes, 0L)
    assert_eq(before.uncertain_transfer_bytes, per_call)
    assert_eq(before.reserved_transfer_bytes, per_call)
    assert_eq(before.reserved_retention_bytes, 2L * per_call)
    assert_true(cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
    let after = @model.model_execution_resource_usage(model)
    assert_eq(after.uncertain_transfer_bytes, per_call)
    assert_eq(after.transferred_bytes, 0L)
    assert_eq(after.reserved_transfer_bytes, 0L)
    assert_eq(after.reserved_retention_bytes, 0L)
    assert_eq(after.reserved_execution_bytes, 0L)
    assert_eq(after.held_bytes, 0L)
    assert_eq(calls.val, 1)
  }
}

///|
test "valid model content does not fabricate an exact transfer observation" {
  let calls = Ref(0)
  let active = fixture_start(fixture_prepared(), () => calls.val += 1)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let model = active.model.unwrap()
  let before = @model.model_execution_resource_usage(model)
  assert_eq(before.transferred_bytes, 0L)
  assert_eq(before.uncertain_transfer_bytes, 66536L)
  assert_eq(before.reserved_transfer_bytes, 0L)
  assert_true(cleanup(active).unwrap())
  assert_eq(
    @model.model_execution_resource_usage(model).uncertain_transfer_bytes,
    66536L,
  )
  assert_eq(calls.val, 1)
}
