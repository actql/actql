///|
fn semantics_limits() -> ProgramSemanticsLimits {
  {
    max_work: 8000000,
    max_stages: 2,
    max_hash_bytes: 10000,
    max_hash_nodes: 1000,
    max_depth: 100,
  }
}

///|
fn assert_program_semantics(
  import_mode : Int,
  accepted : Bool,
  expected : String,
  expected_cid : String,
) -> Unit raise {
  let (requests, stages) = fixture(used_bindings=true, import_mode~, accepted~)
  let usage = check_declaration_usage(
    prepare(requests, stages, caps()).unwrap(),
    max_work=8000000,
  ).unwrap()
  let limits = semantics_limits()
  let v = prepare_program_semantics(usage, limits).unwrap()
  let (renamed_requests, renamed_stages) = fixture(
    used_bindings=true,
    import_mode~,
    accepted~,
    root_id="another-program",
  )
  let renamed = prepare_program_semantics(
    check_declaration_usage(
      prepare(renamed_requests, renamed_stages, caps()).unwrap(),
      max_work=8000000,
    ).unwrap(),
    limits,
  ).unwrap()
  // Root ID belongs to Program Definition, not Program semantics.
  assert_eq(program_semantics_cid(renamed, 10000, 1000, 100), expected_cid)
  assert_true(physical_equal(program_semantics_usage(v), usage))
  for i in [-1, 2, 2147483647] {
    assert_true(program_semantics_stage_cid(v, i) is None)
  }
  for i in 0..<2 {
    assert_eq(
      program_semantics_stage_cid(v, i).unwrap(),
      stage_semantics_cid(
        stage_semantics_at(usage, i).unwrap(),
        10000,
        1000,
        100,
      ),
    )
  }
  let writer = @encode.writer(10000, 1000, 100)
  emit_program_semantics(v, writer)
  assert_eq(@encode.finish(writer), expected)
  assert_eq(program_semantics_cid(v, 10000, 1000, 100), expected_cid)
  let measure = @encode.measuring_writer(10000, 1000, 100)
  emit_program_semantics(v, measure)
  let output_bytes = @encode.finish_measurement(measure)
  assert_eq(program_semantics_cid(v, output_bytes, 1000, 100), expected_cid)
  let (bytes, nodes) = program_semantics_hash_usage(v)
  let exact = {
    ..limits,
    max_work: program_semantics_work(v),
    max_hash_bytes: bytes,
    max_hash_nodes: nodes,
  }
  assert_true(prepare_program_semantics(usage, exact) is Ok(_))
  assert_true(
    prepare_program_semantics(usage, { ..exact, max_work: exact.max_work - 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_program_semantics(usage, { ..exact, max_stages: 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_program_semantics(usage, { ..exact, max_hash_bytes: bytes - 1, })
    is Err(StageHash(1, _)),
  )
  assert_true(
    prepare_program_semantics(usage, { ..exact, max_hash_nodes: nodes - 1, })
    is Err(StageHash(1, _)),
  )
  assert_true(
    prepare_program_semantics(usage, { ..exact, max_depth: 0, })
    is Err(StageHash(0, _)),
  )
  for
    bad in [
      { ..limits, max_work: -1, },
      { ..limits, max_stages: -1, },
      { ..limits, max_hash_bytes: -1, },
      { ..limits, max_hash_nodes: -1, },
      { ..limits, max_depth: -1, },
    ] {
    assert_true(prepare_program_semantics(usage, bad) is Err(InvalidLimits))
  }
  for
    (b, n, d) in [
      (output_bytes - 1, 1000, 100),
      (output_bytes, 0, 100),
      (output_bytes, 1000, 0),
    ] {
    try program_semantics_cid(v, b, n, d) catch {
      @encode.OutputLimit => ()
      e => raise e
    } noraise {
      _ => fail("expected output limit")
    }
  }
  let failed = @encode.hashing_writer(output_bytes - 1, 1000, 100)
  try emit_program_semantics(v, failed) catch {
    @encode.OutputLimit => ()
    e => raise e
  } noraise {
    _ => fail("expected output limit")
  }
  try @encode.finish_hash(failed) catch {
    @encode.ClosedWriter => ()
    e => raise e
  } noraise {
    _ => fail("partial digest escaped")
  }
}
