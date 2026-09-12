///|
fn assert_local_body_identity(
  empty : Bool,
  index : Int,
  expected_text : String,
  expected_cid : String,
) -> Unit raise {
  for changed in [false, true] {
    let first = if empty {
      "[{\"derive\":{\"p_copy\":\"$p\",\"n_copy\":\"$n\"}}]"
    } else {
      "[{\"derive\":{\"p_copy\":\"$p\"}}]"
    }
    let second = if empty { "[]" } else { "[{\"derive\":{\"n_copy\":\"$n\"}}]" }
    let (ops, refs, bindings) = program_sources_fixture(
      steps=Some(first),
      second_steps=Some(second),
      accepted=changed,
      supplied=if changed {
        Some(cursor("{\"p\":\"abc\",\"n\":1}"))
      } else {
        None
      },
    )
    let identity = identify_program_sources(
      bind_program_sources(ops, refs, bindings, 10000000).unwrap(),
      identity_limits(),
    ).unwrap()
    let stage = program_identity_stage_at(identity, index).unwrap()
    let before = program_identity_usage(identity)
    assert_eq(stage_identity_local_body_cid(stage), expected_cid)
    assert_eq(program_identity_usage(identity), before)
    let text = @encode.writer(10000, 1000, 100)
    @program_refs.emit_stage_semantics(
      @program_refs.stage_definition_semantics(stage_identity_definition(stage)),
      text,
    )
    assert_eq(@encode.finish(text), expected_text)
    assert_not_eq(
      stage_identity_local_body_cid(stage),
      stage_identity_definition_cid(stage),
    )
    assert_not_eq(
      stage_identity_local_body_cid(stage),
      program_identity_definition_cid(identity),
    )
  }
}
