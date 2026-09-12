///|
fn assert_stage_declarations(
  empty : Bool,
  index : Int,
  parameters : String?,
  expected : String,
  expected_cid : String,
) -> Unit raise {
  for annotations in [false, true] {
    let (requests, stages) = fixture(
      used_bindings=true,
      empty~,
      annotations~,
      parameters~,
      root_id=if annotations { "renamed-parent" } else { "p" },
    )
    let usage = check_declaration_usage(
      prepare(requests, stages, caps()).unwrap(),
      max_work=8000000,
    ).unwrap()
    let semantics = stage_semantics_at(usage, index).unwrap()
    let text = @encode.writer(10000, 1000, 100)
    emit_stage_parameter_declarations(semantics, text)
    assert_eq(@encode.finish(text), expected)
    let hash = @encode.hashing_writer(10000, 1000, 100)
    emit_stage_parameter_declarations(semantics, hash)
    let (digest, bytes, nodes) = @encode.finish_hash_usage(hash)
    assert_eq("sha256:" + digest, expected_cid)
    let measure = @encode.measuring_writer(bytes, nodes, 100)
    emit_stage_parameter_declarations(semantics, measure)
    assert_eq(@encode.finish_measurement(measure), bytes)
    assert_eq(
      stage_parameter_declarations_cid(semantics, bytes, nodes, 100),
      expected_cid,
    )
    for
      (b, n, d) in [
        (bytes - 1, nodes, 100),
        (bytes, nodes - 1, 100),
        (bytes, nodes, 0),
      ] {
      try stage_parameter_declarations_cid(semantics, b, n, d) catch {
        @encode.OutputLimit => ()
        e => raise e
      } noraise {
        _ => fail("partial declaration projection escaped")
      }
    }
    let failed = @encode.hashing_writer(bytes - 1, nodes, 100)
    try emit_stage_parameter_declarations(semantics, failed) catch {
      @encode.OutputLimit => ()
      e => raise e
    } noraise {
      _ => fail("expected declaration output limit")
    }
    try @encode.finish_hash(failed) catch {
      @encode.ClosedWriter => ()
      e => raise e
    } noraise {
      _ => fail("partial declaration digest escaped")
    }
  }
}
