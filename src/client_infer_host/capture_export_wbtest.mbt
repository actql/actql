///|
fn capture_export_limits() -> @model.ModelCaptureExportLimits {
  {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
    max_chunk_bytes: 65536,
    max_work: 10000,
  }
}

///|
test "formal capture export retains checked raw response and owner through cleanup" {
  let (original, saved, calls) = replay_fixture_original()
  let stream = @model.start_model_capture_export(saved, capture_export_limits()).unwrap()
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(!cleanup(original).unwrap())
  assert_true(@model.model_capture_export_identity(stream) is None)
  let wire = StringBuilder()
  let mut last = 0L
  let mut done = false
  for _ in 0..<1000 {
    let (terminal, chunk, work) = @model.advance_model_capture_export(stream, 1).unwrap()
    assert_eq(work - last, 1L)
    last = work
    wire.write_string(chunk)
    if terminal {
      done = true
      break
    }
    assert_true(@model.model_capture_export_identity(stream) is None)
  }
  assert_true(done)
  let body = wire.to_string()
  assert_true(body.contains("\"version\":\"actql-model-capture-bundle/0.1\""))
  assert_true(
    body.contains("\"structured_response\":{\"reason\":null,\"risk\":\"high\"}"),
  )
  assert_true(
    body.contains(
      "\"bundle_cid\":\"" +
      @model.model_capture_export_identity(stream).unwrap() +
      "\"",
    ),
  )
  assert_true(!cleanup(original).unwrap())
  assert_true(@model.cleanup_model_capture_export(stream).unwrap())
  assert_true(@model.cleanup_model_capture_export(stream).unwrap())
  assert_true(@model.model_capture_export_identity(stream) is None)
  assert_true(cleanup(original).unwrap())
  assert_eq(calls.val, 1)
}

///|
test "capture export stop and limit failure do not issue a completed bundle" {
  for stop in [true, false] {
    let (original, saved, calls) = replay_fixture_original()
    let limits = capture_export_limits()
    let stream = @model.start_model_capture_export(saved, {
      ..limits,
      max_work: 2,
    }).unwrap()
    assert_true(@model.release_verified_model_capture(saved))
    assert_true(!@model.advance_model_capture_export(stream, 1).unwrap().0)
    if stop {
      assert_true(@model.cancel_model_capture_export(stream))
      assert_true(!@model.cleanup_model_capture_export(stream).unwrap())
      assert_true(
        @model.advance_model_capture_export(stream, 1) is Err(@model.Cancelled),
      )
    } else {
      assert_true(!@model.advance_model_capture_export(stream, 1).unwrap().0)
      assert_true(
        @model.advance_model_capture_export(stream, 1) is Err(@model.WorkLimit),
      )
    }
    assert_true(@model.model_capture_export_identity(stream) is None)
    assert_true(!cleanup(original).unwrap())
    assert_true(@model.cleanup_model_capture_export(stream).unwrap())
    assert_true(cleanup(original).unwrap())
    assert_eq(calls.val, 1)
  }
}
