///|
test "cross join lowering retains projection assertion guard and inputs" {
  let pipeline = checked(
    ",{\"cross_join\":{\"with\":\"seed\",\"right_rows\":\"one\",\"max_output_rows\":3,\"select\":{\"l\":\"left.id\",\"r\":\"right.id\"}}}",
  )
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(pipeline, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(CrossJoinStep(kernel)) else {
    abort("cross join step")
  }
  assert_true(
    physical_equal(@lowering_relation.cross_join_kernel_owner(kernel), owner),
  )
  assert_eq(@lowering_relation.cross_join_kernel_step(kernel), 1)
  assert_eq(
    @lowering_relation.cross_join_kernel_input(kernel, true),
    "values_0",
  )
  assert_eq(
    @lowering_relation.cross_join_kernel_input(kernel, false),
    "values_0",
  )
  assert_eq(@lowering_relation.cross_join_kernel_output_limit(kernel), Some(3L))
  let profile = @lowering_relation.cross_join_kernel_profile(kernel)
  assert_true(@lowering_relation.cross_join_requires_one_right(profile))
  assert_true(@lowering_relation.cross_join_has_projection(profile))
  assert_eq(@lowering_relation.cross_join_field_count(profile), 2)
  let writer = @encode.writer(10000, 1000, 30)
  @encode.begin_array(writer)
  @lowering_relation.emit_cross_join_kernel(kernel, writer)
  @encode.end_array(writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"cross_join_1\",\"in\":[\"values_0\",\"values_0\"],\"op\":\"REL.cross_join\",\"params\":{\"right_rows\":\"one\",\"max_output_rows\":3,\"select\":{\"l\":\"left.id\",\"r\":\"right.id\"}}}]",
  )
}

///|
test "cross join lowering rejects invalid preparation limits" {
  let pipeline = checked(",{\"cross_join\":{\"with\":\"seed\"}}")
  let prepared = @lowering_relation.prepare(pipeline, limits()).unwrap()
  let owner = @lowering_relation.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  assert_true(
    @lowering_relation.prepare_cross_join_kernel(owner, 1, 1, 100)
    is Err(PreparationLimit),
  )
  assert_true(
    @lowering_relation.prepare_cross_join_kernel(owner, 1, 10, -1)
    is Err(InvalidLimits),
  )
}

///|
fn cross_join_parameter_owner(value : Int) -> @lowering_relation.BoundPrepared {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"cap\":{\"type\":\"number\",\"nullable\":false}}")),
    { max_parameters: 1, max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let pipeline = @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"cross_join\":{\"with\":\"seed\",\"max_output_rows\":{\"$param\":\"cap\"}}}]",
    ),
    [],
    Some(declarations),
    None,
    {
      max_steps: 10,
      max_work: 1000,
      max_text_bytes: 1000,
      max_nodes: 100,
      max_tokens: 100,
      max_depth: 20,
    },
  ).unwrap()
  let values = match
    @parameter.bind(
      declarations,
      Some(cursor("{\"cap\":" + value.to_string() + "}")),
      { max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
    ).unwrap() {
    Ready(values) => values
    NeedsBindings(_) => abort("complete cross join guard")
  }
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(pipeline, limits()).unwrap(),
    Some(values),
    max_parameters=1,
    max_name_bytes=3,
  ).unwrap()
}

///|
test "cross join lowering resolves positive parameter guards only" {
  let owner = cross_join_parameter_owner(3)
  guard @lowering_relation.prepare_sequence(owner, sequence_limits())
    is Ok(sequence) &&
    @lowering_relation.sequence_step(sequence, 1) is Some(CrossJoinStep(kernel)) else {
    abort("parameter cross join step")
  }
  assert_eq(@lowering_relation.cross_join_kernel_output_limit(kernel), Some(3L))
  assert_true(
    @lowering_relation.prepare_sequence(
      cross_join_parameter_owner(0),
      sequence_limits(),
    )
    is Err(CrossJoinFailure(1, InvalidGuard)),
  )
}
