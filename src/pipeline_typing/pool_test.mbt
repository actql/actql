///|
test "pooling composes with vector projection and retains conditional input keys" {
  guard vector_input() is @carrier.VectorValue(v) else { abort("vectors") }
  let relation = @carrier.relation(@carrier.vector_records(v))
  let declaration = @evidence.declare_primary_key(
    cursor("[\"id\"]"),
    relation,
    { max_fields: 1, max_name_bytes: 2, },
  ).unwrap()
  let source = cursor(
    "[{\"pool_vectors\":{\"vector\":\"embedding\",\"by\":[\"id\"],\"method\":\"mean\"},\"as\":\"pooled\"},{\"vectors\":true},{\"select\":[\"id\",\"member_count\"]}]",
  )
  let inputs = [("rows", @pipeline_typing.KeyedInput(declaration))]
  let p = @pipeline_typing.check_with_evidence(
    source,
    inputs,
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.input_key(p, 0) is Some(_))
  assert_true(@pipeline_typing.input_key(p, -1) is None)
  assert_true(@pipeline_typing.input_key(p, 1) is None)
  let step = @pipeline_typing.step_at(p, 0).unwrap()
  guard step.operation is Pool(checked) else { abort("pool") }
  assert_true(@vector.pool_key_declaration(checked) is Some(_))
  assert_true(@vector.pool_encodes_member_key(checked))
  assert_true(
    @vector.pool_pending(checked).contains(
      ValidateDeclaredPoolKey(
        ValidateWholeTupleUniquenessAfterInputNormalization,
      ),
    ),
  )
  assert_eq(@pipeline_typing.input_occurrences(step)[0].target, Input(0))
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 2)
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, cap)
      is Err(_),
    )
  }
  assert_true(
    @pipeline_typing.check_carriers(
      source,
      [("rows", relation)],
      None,
      None,
      limits(),
    )
    is Err({ kind: MissingKeyEvidence, .. }),
  )
  let ordinary = @pipeline_typing.check_carriers(
    source,
    [("v", vector_input())],
    None,
    None,
    limits(),
  ).unwrap()
  guard @pipeline_typing.step_at(ordinary, 0).unwrap().operation is Pool(c) else {
    abort("pool")
  }
  assert_true(@vector.pool_key_declaration(c) is None)
}

///|
test "pooling retains every key alias through filter projection and deletion" {
  guard vector_input() is @carrier.VectorValue(v) else { abort("vectors") }
  let relation = @carrier.relation(@carrier.vector_records(v))
  let declaration = @evidence.declare_primary_key(
    cursor("[\"id\"]"),
    relation,
    { max_fields: 1, max_name_bytes: 2, },
  ).unwrap()
  let inputs = [("rows", @pipeline_typing.KeyedInput(declaration))]
  for
    select in [
      "[{\"a\":\"id\"},{\"b\":\"id\"},\"embedding\"]", "[{\"b\":\"id\"},{\"a\":\"id\"},\"embedding\"]",
    ] {
    let source = cursor(
      "[{\"filter\":\"id > 0\"},{\"select\":" +
      select +
      "},{\"drop\":[\"a\"]},{\"pool_vectors\":{\"vector\":\"embedding\",\"by\":[\"b\"],\"method\":\"sum\"}}]",
    )
    let p = @pipeline_typing.check_with_evidence(
      source,
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    let aliases = @pipeline_typing.candidate_key(p, Step(1)).unwrap()
    assert_eq(@evidence.key_alias_count(aliases, 0), 2)
    assert_true(@evidence.key_alias_at(aliases, 0, 2) is None)
    let kept = @pipeline_typing.candidate_key(p, Step(2)).unwrap()
    assert_eq(@evidence.key_field_at(kept, 0).unwrap().name, Unqualified("b"))
    assert_eq(
      @decode.cursor_path(@evidence.key_source(kept)),
      @decode.cursor_path(@evidence.key_source(declaration)),
    )
    guard @pipeline_typing.step_at(p, 3).unwrap().operation is Pool(c) else {
      abort("pool")
    }
    assert_eq(
      @evidence.key_field_at(@vector.pool_key_declaration(c).unwrap(), 0).unwrap().name,
      Unqualified("b"),
    )
    let u = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
      is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
      ] {
      assert_true(
        @pipeline_typing.check_with_evidence(source, inputs, None, None, cap)
        is Err(_),
      )
    }
  }
  for
    prefix in [
      "{\"distinct\":true}", "{\"derive\":{}}", "{\"sort\":[]}", "{\"rename\":{}}",
    ] {
    let p = @pipeline_typing.check_with_evidence(
      cursor("[" + prefix + "]"),
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(@pipeline_typing.candidate_key(p, Step(0)) is Some(_))
  }
  for prefix in ["{\"derive\":[{\"id\":\"0\"}]}", "{\"drop\":[\"id\"]}"] {
    let p = @pipeline_typing.check_with_evidence(
      cursor("[" + prefix + "]"),
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(@pipeline_typing.candidate_key(p, Step(0)) is None)
  }
}
