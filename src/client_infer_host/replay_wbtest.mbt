///|
fn replay_fixture_original() -> (
  Execution,
  @model.VerifiedModelCapture,
  Ref[Int],
) raise {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let calls = Ref(0)
  let provider = @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
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
  assert_true(acquire_capture(active) is None)
  assert_true(fixture_finish(active) is Complete(_, ..))
  (active, acquire_capture(active).unwrap(), calls)
}

///|
test "reconstructed Infer replays only checked captures with independent custody" {
  let (original, saved, calls) = replay_fixture_original()
  let original_model = original.model.unwrap()
  let evidence = invocation_evidence(original, 0).unwrap()
  assert_true(!cleanup(original).unwrap())
  let prepared = fixture_prepared()
  let replay = start_replay(
    prepared,
    2,
    infer_fixture_registry,
    infer_fixture_values,
    saved,
    standard_limits(),
    call_identity_plan(prepared),
  ).unwrap()
  // A child acquires custody at start, including its long pre-model prefix.
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(!@model.release_verified_model_capture(saved))
  assert_true(!cleanup(original).unwrap())
  assert_true(fixture_finish(replay) is Complete(_, ..))
  assert_eq(calls.val, 1)
  assert_eq(
    @publication.run_evidence_value_json(
      invocation_evidence(replay, 0).unwrap(),
    ),
    @publication.run_evidence_value_json(evidence),
  )
  let model = replay.model.unwrap()
  let usage = @model.model_execution_resource_usage(model)
  assert_eq(usage.attempts, 0)
  assert_eq(usage.transferred_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  let observed = capture(replay).unwrap()
  assert_eq(observed.captures[0].provider_request_id, "request-1")
  assert_eq(observed.captures[0].input_tokens, 1L)
  assert_eq(observed.captures[0].output_tokens, 2L)
  assert_true(!cleanup(original).unwrap())
  assert_true(cleanup(replay).unwrap())
  assert_true(cleanup(original).unwrap())
  let released = @model.model_execution_resource_usage(original_model)
  assert_eq(released.reserved_transfer_bytes, 0L)
  assert_eq(released.reserved_retention_bytes, 0L)
  assert_eq(released.reserved_execution_bytes, 0L)
  assert_eq(calls.val, 1)
  assert_true(
    start_replay(
      prepared,
      2,
      infer_fixture_registry,
      infer_fixture_values,
      saved,
      standard_limits(),
      call_identity_plan(prepared),
    )
    is Err(Model(@model.OutputIdentity)),
  )
}

///|
test "replay work exact and one-short are charged without reserving model attempts" {
  let (original, saved, calls) = replay_fixture_original()
  // One replay-start transition, eight shared request-preparation transitions
  // (including typed key admission), and one accepted-capture transition.
  // These bounds come from the phases, not a successful execution counter.
  for work in [10, 9] {
    let prepared = fixture_prepared()
    let limits = standard_limits()
    let limits = { ..limits, model: { ..limits.model, max_work: work, }, }
    let replay = start_replay(
      prepared,
      2,
      infer_fixture_registry,
      infer_fixture_values,
      saved,
      limits,
      call_identity_plan(prepared),
    ).unwrap()
    let poll = fixture_finish(replay)
    if work == 10 {
      assert_true(poll is Complete(_, ..))
    } else {
      assert_true(poll is Failed(Model(@model.WorkLimit), ..))
      assert_true(acquire_output(replay) is None)
    }
    let usage = @model.model_execution_resource_usage(replay.model.unwrap())
    assert_eq(usage.attempts, 0)
    assert_eq(usage.transferred_bytes, 0L)
    assert_true(cleanup(replay).unwrap())
    assert_eq(calls.val, 1)
  }
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(cleanup(original).unwrap())
}

///|
test "changed completed input rejects replay without a provider alternative" {
  let (original, saved, calls) = replay_fixture_original()
  for
    source in [
      infer_fixture_program.replace(old="hello", new="changed"),
      infer_fixture_program.replace(old="\"id\":\"a\"", new="\"id\":\"b\""),
    ] {
    assert_true(source != infer_fixture_program)
    let prepared = fixture_prepared(source~)
    let replay = start_replay(
      prepared,
      2,
      infer_fixture_registry,
      infer_fixture_values,
      saved,
      standard_limits(),
      call_identity_plan(prepared),
    ).unwrap()
    assert_true(
      fixture_finish(replay) is Failed(Model(@model.OutputIdentity), ..),
    )
    assert_true(acquire_output(replay) is None)
    assert_true(acquire_capture(replay) is None)
    assert_true(cleanup(replay).unwrap())
    assert_eq(calls.val, 1)
  }
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(cleanup(original).unwrap())
}

///|
test "replay cancellation retains input and capture until stop and cleanup" {
  for during_model in [false, true] {
    let (original, saved, calls) = replay_fixture_original()
    let prepared = fixture_prepared()
    let replay = start_replay(
      prepared,
      2,
      infer_fixture_registry,
      infer_fixture_values,
      saved,
      standard_limits(),
      call_identity_plan(prepared),
    ).unwrap()
    assert_true(@model.release_verified_model_capture(saved))
    if during_model {
      for _ in 0..<2000 {
        if request_preflight_pending(replay) {
          break
        }
        assert_true(advance(replay, 1).unwrap() is Continue(_))
      }
      assert_true(request_preflight_pending(replay))
    } else {
      assert_true(advance(replay, 1).unwrap() is Continue(_))
    }
    assert_true(cancel(replay))
    assert_true(!cleanup(replay).unwrap())
    assert_true(!cleanup(original).unwrap())
    assert_true(advance(replay, 1).unwrap() is Stopped(_))
    assert_true(acquire_output(replay) is None)
    assert_true(!cleanup(original).unwrap())
    assert_true(cleanup(replay).unwrap())
    assert_true(cleanup(original).unwrap())
    assert_eq(calls.val, 1)
  }
}
