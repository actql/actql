///|
fn assert_stage_definition(
  empty : Bool,
  index : Int,
  id : String,
  semantics_cid : String,
  expected : String,
  expected_cid : String,
) -> Unit raise {
  let (requests, stages) = fixture(used_bindings=true, empty~)
  let usage = check_declaration_usage(
    prepare(requests, stages, caps()).unwrap(),
    max_work=8000000,
  ).unwrap()
  let semantics = stage_semantics_at(usage, index).unwrap()
  let (renamed_requests, renamed_stages) = fixture(
    used_bindings=true,
    empty~,
    annotations=true,
  )
  let renamed_usage = check_declaration_usage(
    prepare(renamed_requests, renamed_stages, caps()).unwrap(),
    max_work=8000000,
  ).unwrap()
  let renamed = prepare_stage_definition(
    stage_semantics_at(renamed_usage, index).unwrap(),
    10000,
    1000,
    100,
  )
  assert_eq(stage_definition_id(renamed), "renamed-" + id)
  assert_eq(stage_definition_semantics_cid(renamed), semantics_cid)
  assert_not_eq(stage_definition_cid(renamed, 10000, 1000, 100), expected_cid)
  let renamed_writer = @encode.writer(10000, 1000, 100)
  emit_stage_definition(renamed, renamed_writer)
  assert_eq(
    @encode.finish(renamed_writer),
    expected.replace(
      old="\"id\":\"" + id + "\"",
      new="\"id\":\"renamed-" + id + "\"",
    ),
  )
  let v = prepare_stage_definition(semantics, 10000, 1000, 100)
  assert_true(physical_equal(stage_definition_semantics(v), semantics))
  assert_eq(stage_definition_id(v), id)
  assert_eq(stage_definition_semantics_cid(v), semantics_cid)
  let (bytes, nodes) = stage_definition_hash_usage(v)
  assert_eq(
    stage_definition_hash_usage(
      prepare_stage_definition(semantics, bytes, nodes, 100),
    ),
    (bytes, nodes),
  )
  for
    (b, n, d) in [
      (bytes - 1, nodes, 100),
      (bytes, nodes - 1, 100),
      (bytes, nodes, 0),
    ] {
    try prepare_stage_definition(semantics, b, n, d) catch {
      @encode.OutputLimit => ()
      e => raise e
    } noraise {
      _ => fail("partial stage preparation escaped")
    }
  }
  let writer = @encode.writer(10000, 1000, 100)
  emit_stage_definition(v, writer)
  assert_eq(@encode.finish(writer), expected)
  let measure = @encode.measuring_writer(10000, 1000, 100)
  emit_stage_definition(v, measure)
  let size = @encode.finish_measurement(measure)
  assert_eq(stage_definition_cid(v, size, 4, 1), expected_cid)
  for (b, n, d) in [(size - 1, 4, 1), (size, 3, 1), (size, 4, 0)] {
    try stage_definition_cid(v, b, n, d) catch {
      @encode.OutputLimit => ()
      e => raise e
    } noraise {
      _ => fail("expected definition output limit")
    }
  }
  let failed = @encode.hashing_writer(size - 1, 4, 1)
  try emit_stage_definition(v, failed) catch {
    @encode.OutputLimit => ()
    e => raise e
  } noraise {
    _ => fail("expected output limit")
  }
  try @encode.finish_hash(failed) catch {
    @encode.ClosedWriter => ()
    e => raise e
  } noraise {
    _ => fail("partial stage digest escaped")
  }
  // Parent identity is not a local definition member.
  let (other_requests, other_stages) = fixture(
    used_bindings=true,
    empty~,
    root_id="another-parent",
  )
  let other = check_declaration_usage(
    prepare(other_requests, other_stages, caps()).unwrap(),
    max_work=8000000,
  ).unwrap()
  let other_stage = stage_semantics_at(other, index).unwrap()
  assert_false(physical_equal(other_stage, semantics))
  assert_eq(
    stage_definition_cid(
      prepare_stage_definition(other_stage, 10000, 1000, 100),
      size,
      4,
      1,
    ),
    expected_cid,
  )
}
