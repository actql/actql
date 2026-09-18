///|
fn inner_checked(
  options : String,
  kind? : String = "inner",
) -> @join.CheckedJoin {
  let pipeline = checked(
    ",{\"join\":{\"with\":\"seed\",\"kind\":\"" +
    kind +
    "\",\"on\":[{\"left\":\"id\",\"right\":\"id\"},{\"left\":\"id\",\"right\":\"id\"}]" +
    options +
    "}}",
  )
  guard @pipeline.step_at(pipeline, 1).unwrap().operation is Join(checked~, ..) else {
    abort("join")
  }
  checked
}

///|
test "inner join preparation retains exact checked ownership repeated keys and every alias" {
  let checked = inner_checked(
    ",\"select\":{\"z\":\"left.id\",\"a\":\"left.id\"},\"cardinality\":\"one_to_one\",\"null_key\":\"fail\",\"max_output_rows\":3",
  )
  let join = @lowering_relation.prepare_inner_join(checked, 4, 100).unwrap()
  assert_true(
    physical_equal(@lowering_relation.inner_join_checked(join), checked),
  )
  assert_eq(@lowering_relation.inner_join_key_count(join), 2)
  for index in 0..<2 {
    assert_eq(
      @lowering_relation.inner_join_key_at(join, index),
      Some((@schema.Unqualified("id"), @schema.Unqualified("id"))),
    )
  }
  assert_eq(@lowering_relation.inner_join_field_count(join), 2)
  for (index, name) in [(0, "a"), (1, "z")] {
    let field = @lowering_relation.inner_join_field_at(join, index).unwrap()
    assert_eq(field.output, @schema.Unqualified(name))
    assert_eq(field.input, @schema.Qualified(Left, "id"))
  }
  assert_eq(
    @join.assertion(@lowering_relation.inner_join_checked(join)),
    Some(OneToOne),
  )
  assert_eq(
    @join.null_key(@lowering_relation.inner_join_checked(join)),
    @join.Fail,
  )
  assert_eq(
    @join.output_guard(@lowering_relation.inner_join_checked(join)),
    Some(Literal(3L)),
  )
  assert_true(
    @lowering_relation.prepare_inner_join(checked, 3, 100)
    is Err(PreparationLimit),
  )
  assert_true(
    @lowering_relation.prepare_inner_join(checked, 4, 0)
    is Err(PreparationLimit),
  )
}

///|
test "inner join omitted projection retains both qualified sides without inventing assertions" {
  let checked = inner_checked("")
  let join = @lowering_relation.prepare_inner_join(checked, 4, 100).unwrap()
  assert_eq(@join.assertion(@lowering_relation.inner_join_checked(join)), None)
  assert_eq(
    @join.null_key(@lowering_relation.inner_join_checked(join)),
    @join.NoMatch,
  )
  for (index, side) in [(0, @schema.Left), (1, @schema.Right)] {
    let field = @lowering_relation.inner_join_field_at(join, index).unwrap()
    assert_eq(field.output, @schema.Qualified(side, "id"))
    assert_eq(field.input, field.output)
  }
  assert_true(@lowering_relation.inner_join_field_at(join, 2) is None)
  assert_true(@lowering_relation.inner_join_key_at(join, -1) is None)
  for kind in ["left", "full", "semi", "anti"] {
    let prepared = @lowering_relation.prepare_inner_join(
      inner_checked("", kind~),
      4,
      100,
    ).unwrap()
    assert_eq(
      @lowering_relation.inner_join_kind(prepared),
      match kind {
        "left" => @join.Left
        "full" => @join.Full
        "semi" => @join.Semi
        _ => @join.Anti
      },
    )
  }
}

///|
test "join sequence preserves two self input occurrences and emits checked projection after join" {
  let pipeline = checked(
    ",{\"join\":{\"with\":\"seed\",\"kind\":\"inner\",\"on\":\"id\",\"max_output_rows\":3,\"select\":{\"x\":\"left.id\"}}}",
  )
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(pipeline, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1) is Some(JoinStep(kernel)) else {
    abort("binary step")
  }
  assert_true(
    physical_equal(@lowering_relation.join_kernel_owner(kernel), owner),
  )
  assert_eq(@lowering_relation.join_kernel_step(kernel), 1)
  assert_eq(@lowering_relation.join_kernel_input(kernel, true), "values_0")
  assert_eq(@lowering_relation.join_kernel_input(kernel, false), "values_0")
  assert_eq(@lowering_relation.join_kernel_output_limit(kernel), Some(3L))
  assert_eq(
    @lowering_relation.sequence_canonical_node_count(sequence, 1),
    Some(2),
  )
  for
    (index, id, operation) in [
      (0, "join_raw_1", "REL.join"),
      (1, "join_1", "REL.select"),
    ] {
    let node = @lowering_relation.sequence_canonical_node_at(sequence, 1, index).unwrap()
    assert_eq((node.source_step, node.id, node.operation), (1, id, operation))
  }
  assert_true(
    @lowering_relation.prepare_kernel_roots(sequence, 1, {
      max_roots: 10,
      max_pointer_bytes: 100,
      max_work: 100,
    })
    is Err(NotExpressionKernel),
  )
  let writer = @encode.writer(10000, 1000, 30)
  @encode.begin_array(writer)
  @lowering_relation.emit_join_kernel(kernel, writer)
  @encode.end_array(writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"join_raw_1\",\"in\":[\"values_0\",\"values_0\"],\"op\":\"REL.join\",\"params\":{\"how\":\"inner\",\"key_pairs\":[{\"left\":\"id\",\"right\":\"id\"}],\"max_output_rows\":3,\"null_key\":\"no_match\",\"on\":{\"left\":{\"path\":[\"left\",\"id\"],\"type\":\"col\"},\"op\":\"eq\",\"right\":{\"path\":[\"right\",\"id\"],\"type\":\"col\"},\"type\":\"cmp\"},\"on_duplicate\":\"fail\"}},{\"id\":\"join_1\",\"in\":[\"join_raw_1\"],\"op\":\"REL.select\",\"params\":{\"columns\":[{\"from\":\"left.id\",\"to\":\"x\"}]}}]",
  )
}

///|
test "join emission retains every checked equality kind" {
  for kind in ["left", "full", "semi", "anti"] {
    let pipeline = checked(
      ",{\"join\":{\"with\":\"seed\",\"kind\":\"" + kind + "\",\"on\":\"id\"}}",
    )
    let owner = @lowering_relation.bind_parameters(
      @lowering_relation.prepare(pipeline, limits()).unwrap(),
      None,
      max_parameters=0,
      max_name_bytes=0,
    ).unwrap()
    let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
    guard @lowering_relation.sequence_step(sequence, 1)
      is Some(JoinStep(kernel)) else {
      abort("binary step")
    }
    let writer = @encode.writer(10000, 1000, 30)
    @encode.begin_array(writer)
    @lowering_relation.emit_join_kernel(kernel, writer)
    @encode.end_array(writer)
    assert_true(@encode.finish(writer).contains("\"how\":\"" + kind + "\""))
  }
}
