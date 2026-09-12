///|
fn assert_program_definition(
  import_mode : Int,
  accepted : Bool,
  id : String,
  semantics_cid : String,
  expected : String,
  expected_cid : String,
) -> Unit raise {
  let (requests, stages) = fixture(
    used_bindings=true,
    import_mode~,
    accepted~,
    root_id=id,
  )
  let usage = check_declaration_usage(
    prepare(requests, stages, caps()).unwrap(),
    max_work=8000000,
  ).unwrap()
  let semantics = prepare_program_semantics(usage, semantics_limits()).unwrap()
  let v = prepare_program_definition(semantics, 10000, 1000, 100)
  assert_true(physical_equal(program_definition_semantics(v), semantics))
  assert_eq(program_definition_id(v), id)
  assert_eq(program_definition_semantics_cid(v), semantics_cid)
  let (bytes, nodes) = program_definition_hash_usage(v)
  let exact = prepare_program_definition(semantics, bytes, nodes, 100)
  assert_eq(program_definition_hash_usage(exact), (bytes, nodes))
  for
    (b, n, d) in [
      (bytes - 1, nodes, 100),
      (bytes, nodes - 1, 100),
      (bytes, nodes, 0),
    ] {
    try prepare_program_definition(semantics, b, n, d) catch {
      @encode.OutputLimit => ()
      e => raise e
    } noraise {
      _ => fail("partial preparation escaped")
    }
  }
  let writer = @encode.writer(10000, 1000, 100)
  emit_program_definition(v, writer)
  assert_eq(@encode.finish(writer), expected)
  assert_eq(program_definition_cid(v, 10000, 1000, 100), expected_cid)
  let measure = @encode.measuring_writer(10000, 1000, 100)
  emit_program_definition(v, measure)
  let size = @encode.finish_measurement(measure)
  // Object root and three scalar members; one container of depth one.
  assert_eq(program_definition_cid(v, size, 4, 1), expected_cid)
  for (b, n, d) in [(size - 1, 4, 1), (size, 3, 1), (size, 4, 0)] {
    try program_definition_cid(v, b, n, d) catch {
      @encode.OutputLimit => ()
      e => raise e
    } noraise {
      _ => fail("expected definition output limit")
    }
  }
  let failed = @encode.hashing_writer(size - 1, 4, 1)
  try emit_program_definition(v, failed) catch {
    @encode.OutputLimit => ()
    e => raise e
  } noraise {
    _ => fail("expected definition output limit")
  }
  try @encode.finish_hash(failed) catch {
    @encode.ClosedWriter => ()
    e => raise e
  } noraise {
    _ => fail("partial definition digest escaped")
  }
  assert_eq(program_definition_cid(v, size, 4, 1), expected_cid)
}
