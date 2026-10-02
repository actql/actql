///|
fn restored_replay_fixture() -> (
  @publication.ModelCaptureBundleRead,
  String,
  Ref[Int],
) raise {
  let (original, saved, calls) = replay_fixture_original()
  let stream = @model.start_model_capture_export(saved, capture_export_limits()).unwrap()
  let wire = StringBuilder()
  let mut done = false
  for _ in 0..<1000 {
    let (terminal, chunk, _) = @model.advance_model_capture_export(stream, 1).unwrap()
    wire.write_string(chunk)
    if terminal {
      done = true
      break
    }
  }
  assert_true(done)
  let identity = @model.model_capture_export_identity(stream).unwrap()
  let body = wire.to_string()
  assert_true(@model.cleanup_model_capture_export(stream).unwrap())
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(cleanup(original).unwrap())
  let captured = @publication.read_model_capture_bundle(
    body, identity, 100000, 10000, 100,
  ).unwrap()
  (captured, body, calls)
}

///|
test "saved capture replays under a fresh input without retaining old execution" {
  let (saved, body, calls) = restored_replay_fixture()
  let evidence = @publication.model_capture_record_evidence(
    @publication.model_capture_bundle_record(saved, 0).unwrap(),
  )
  assert_true(body.contains(@publication.run_evidence_value_identity(evidence)))
  let prepared = fixture_prepared()
  let replay = start_restored_replay(
    prepared,
    2,
    infer_fixture_registry,
    infer_fixture_values,
    saved,
    standard_limits(),
    call_identity_plan(prepared),
  ).unwrap()
  assert_true(@publication.release_model_capture_bundle_read(saved))
  assert_true(!@publication.release_model_capture_bundle_read(saved))
  assert_true(fixture_finish(replay) is Complete(_, ..))
  assert_eq(
    @publication.run_evidence_value_json(
      invocation_evidence(replay, 0).unwrap(),
    ),
    @publication.run_evidence_value_json(evidence),
  )
  assert_eq(
    capture(replay).unwrap().captures[0].provider_request_id,
    "request-1",
  )
  let usage = @model.model_execution_resource_usage(replay.model.unwrap())
  assert_eq(usage.attempts, 0)
  assert_eq(usage.transferred_bytes, 0L)
  assert_eq(calls.val, 1)
  let held = acquire_output(replay).unwrap()
  assert_true(!cleanup(replay).unwrap())
  assert_true(release_output(held))
  assert_true(cleanup(replay).unwrap())
  guard replay.source is Restored(read) else {
    assert_true(false)
    return
  }
  assert_true(@publication.model_capture_bundle_identity(read) is None)
}

///|
test "saved replay rejects a changed logical input without redispatch" {
  let (saved, _, calls) = restored_replay_fixture()
  let source = infer_fixture_program.replace(old="hello", new="changed")
  let prepared = fixture_prepared(source~)
  let replay = start_restored_replay(
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
  assert_true(cleanup(replay).unwrap())
  assert_true(@publication.release_model_capture_bundle_read(saved))
  assert_eq(calls.val, 1)
}
