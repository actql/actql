///|
fn assert_stage_semantics(
  empty : Bool,
  index : Int,
  expected : String,
  expected_cid : String,
) -> Unit raise {
  let (requests, stages) = fixture(used_bindings=true, empty~)
  let inventory = prepare(requests, stages, caps()).unwrap()
  let usage = check_declaration_usage(inventory, max_work=8000000).unwrap()
  let value = stage_semantics_at(usage, index).unwrap()
  let (annotated_requests, annotated_stages) = fixture(
    used_bindings=true,
    empty~,
    annotations=true,
  )
  let annotated_usage = check_declaration_usage(
    prepare(annotated_requests, annotated_stages, caps()).unwrap(),
    max_work=8000000,
  ).unwrap()
  assert_eq(
    stage_semantics_cid(
      stage_semantics_at(annotated_usage, index).unwrap(),
      10000,
      1000,
      100,
    ),
    expected_cid,
  )
  assert_true(physical_equal(stage_semantics_usage(value), usage))
  assert_eq(stage_semantics_index(value), index)
  for invalid in [-1, 2, 2147483647] {
    assert_true(stage_semantics_at(usage, invalid) is None)
  }
  let writer = @encode.writer(10000, 1000, 100)
  emit_stage_semantics(value, writer)
  assert_eq(@encode.finish(writer), expected)
  assert_eq(stage_semantics_cid(value, 10000, 1000, 100), expected_cid)
  let measure = @encode.measuring_writer(10000, 1000, 100)
  emit_stage_semantics(value, measure)
  let bytes = @encode.finish_measurement(measure)
  assert_eq(stage_semantics_cid(value, bytes, 1000, 100), expected_cid)
  for (b, n, d) in [(bytes - 1, 1000, 100), (bytes, 0, 100), (bytes, 1000, 0)] {
    try stage_semantics_cid(value, b, n, d) catch {
      @encode.OutputLimit => ()
      e => raise e
    } noraise {
      _ => fail("expected output budget rejection")
    }
  }
  // The emitter is shared with bounded hash sinks, including their failure and
  // finalization discipline. No partial prefix hash survives a failed output.
  let small = @encode.hashing_writer(bytes - 1, 1000, 100)
  try emit_stage_semantics(value, small) catch {
    @encode.OutputLimit => ()
    e => raise e
  } noraise {
    _ => fail("expected output budget rejection")
  }
  try @encode.finish_hash(small) catch {
    @encode.ClosedWriter => ()
    e => raise e
  } noraise {
    _ => fail("failed writer exposed prefix digest")
  }
}
