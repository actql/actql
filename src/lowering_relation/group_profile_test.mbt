///|
fn group_profile_checked(
  aggregate_source : String,
  declarations? : @parameter.Declarations? = None,
) -> @pipeline.CheckedPipeline {
  @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{" +
      "\"b\":{\"type\":\"boolean\",\"nullable\":true}," +
      "\"d\":{\"type\":\"decimal\",\"precision\":10," +
      "\"scale\":2,\"nullable\":true}," +
      "\"k\":{\"type\":\"number\",\"nullable\":true}," +
      "\"n\":{\"type\":\"number\",\"nullable\":true}," +
      "\"s\":{\"type\":\"string\",\"nullable\":true}}," +
      "\"rows\":[]},\"as\":\"seed\"}," +
      "{\"group\":{\"by\":[\"k\"],\"aggregates\":" +
      aggregate_source +
      "}}]",
    ),
    [],
    declarations,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
fn group_profile_owner(aggregates : String) -> @lowering_relation.BoundPrepared {
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(group_profile_checked(aggregates), limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "selected group boundary includes existing count and general providers" {
  for
    (aggregates, expected) in [
      ("{\"n\":{\"fn\":\"count\"}}", true),
      ("{\"n\":{\"fn\":\"count\",\"field\":\"n\"}}", true),
      ("{\"n\":{\"fn\":\"sum\",\"field\":\"n\"}}", true),
      ("{\"n\":{\"fn\":\"count\",\"field\":\"n\",\"distinct\":true}}", true),
      ("{\"n\":{\"fn\":\"count\",\"filter\":\"b\"}}", true),
      ("{\"n\":{\"fn\":\"max\",\"expr\":\"n\",\"filter\":\"b\"}}", true),
    ] {
    let owner = group_profile_owner(aggregates)
    let node = @lowering_relation.node_at(
      @lowering_relation.bound_preparation(owner),
      1,
    ).unwrap()
    assert_eq(
      @lowering_relation.node_supports_selected_managed_execution(node),
      expected,
    )
  }
}

///|
test "group profile retains every aggregate kind and typed modifier" {
  let aggregates = "{" +
    "\"a00\":{\"fn\":\"count\"}," +
    "\"a01\":{\"fn\":\"count_if\",\"field\":\"b\"}," +
    "\"a02\":{\"fn\":\"sum\",\"field\":\"n\",\"distinct\":true}," +
    "\"a03\":{\"fn\":\"avg\",\"field\":\"n\"}," +
    "\"a04\":{\"fn\":\"min\",\"field\":\"n\"}," +
    "\"a05\":{\"fn\":\"max\",\"field\":\"n\"}," +
    "\"a06\":{\"fn\":\"array_agg\",\"expr\":\"n + 1\"," +
    "\"filter\":\"b\",\"distinct\":true,\"max_items\":3," +
    "\"order_by\":[{\"k\":\"asc\"}]}," +
    "\"a07\":{\"fn\":\"string_agg\",\"field\":\"s\"," +
    "\"delimiter\":\",\",\"distinct\":true,\"max_bytes\":9," +
    "\"order_by\":[{\"k\":\"asc\"}]}," +
    "\"a08\":{\"fn\":\"first\",\"field\":\"s\"," +
    "\"order_by\":[{\"k\":\"asc\"}]}," +
    "\"a09\":{\"fn\":\"last\",\"field\":\"s\"," +
    "\"order_by\":[{\"k\":\"asc\"}]}," +
    "\"a10\":{\"fn\":\"percentile_disc\",\"field\":\"n\"," +
    "\"fraction\":0.25}," +
    "\"a11\":{\"fn\":\"percentile_cont\",\"field\":\"n\"," +
    "\"fraction\":0.75}," +
    "\"a12\":{\"fn\":\"var_pop\",\"field\":\"n\"}," +
    "\"a13\":{\"fn\":\"var_samp\",\"field\":\"n\"}," +
    "\"a14\":{\"fn\":\"stddev_pop\",\"field\":\"n\"}," +
    "\"a15\":{\"fn\":\"stddev_samp\",\"field\":\"n\"}}"
  let (group, remaining) = @lowering_relation.prepare_group(
    group_profile_owner(aggregates),
    1,
    100,
    1000,
    expression_limits(),
  ).unwrap()
  assert_eq(@lowering_relation.group_key_count(group), 1)
  assert_eq(@lowering_relation.group_aggregate_count(group), 16)
  assert_true(remaining.max_work < expression_limits().max_work)
  let expected = [
    @relation.Count,
    @relation.CountIf,
    @relation.Sum,
    @relation.Avg,
    @relation.Min,
    @relation.Max,
    @relation.ArrayAgg,
    @relation.StringAgg,
    @relation.First,
    @relation.Last,
    @relation.PercentileDisc,
    @relation.PercentileCont,
    @relation.VarPop,
    @relation.VarSamp,
    @relation.StddevPop,
    @relation.StddevSamp,
  ]
  for i in 0..<expected.length() {
    let aggregate = @lowering_relation.group_aggregate_at(group, i).unwrap()
    let suffix = if i < 10 { "0" } else { "" }
    assert_eq(
      @lowering_relation.group_aggregate_name(aggregate),
      "a" + suffix + i.to_string(),
    )
    assert_eq(
      @lowering_relation.group_aggregate_function(aggregate),
      expected[i],
    )
    assert_eq(
      @lowering_relation.group_aggregate_requires_numeric_observation(aggregate),
      i == 2 || i == 3,
    )
  }
  let array = @lowering_relation.group_aggregate_at(group, 6).unwrap()
  assert_true(
    @lowering_relation.group_aggregate_argument(array)
    is @lowering_relation.AggregateExpression(_),
  )
  assert_true(@lowering_relation.group_aggregate_filter(array) is Some(_))
  assert_eq(@lowering_relation.group_aggregate_distinct(array), Some(true))
  assert_eq(@lowering_relation.group_aggregate_item_limit(array), Some(3L))
  assert_eq(@lowering_relation.group_aggregate_order_count(array), 1)
  let string = @lowering_relation.group_aggregate_at(group, 7).unwrap()
  assert_eq(@lowering_relation.group_aggregate_byte_limit(string), Some(9L))
  assert_eq(@lowering_relation.group_aggregate_delimiter(string), Some(","))
  assert_eq(
    @lowering_relation.group_aggregate_fraction(
      @lowering_relation.group_aggregate_at(group, 10).unwrap(),
    ),
    Some(0.25),
  )
}

///|
test "group profile resolves aggregate guard and fraction parameters" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"items\":{\"type\":\"number\",\"nullable\":false}," +
        "\"bytes\":{\"type\":\"number\",\"nullable\":false}," +
        "\"fraction\":{\"type\":\"number\",\"nullable\":false}}",
      ),
    ),
    { max_parameters: 3, max_nodes: 20, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  let checked = group_profile_checked(
    "{" +
    "\"a\":{\"fn\":\"array_agg\",\"field\":\"n\"," +
    "\"max_items\":{\"$param\":\"items\"}," +
    "\"order_by\":[{\"k\":\"asc\"}]}," +
    "\"b\":{\"fn\":\"string_agg\",\"field\":\"s\"," +
    "\"delimiter\":\"|\",\"max_bytes\":{\"$param\":\"bytes\"}," +
    "\"order_by\":[{\"k\":\"asc\"}]}," +
    "\"p\":{\"fn\":\"percentile_disc\",\"field\":\"n\"," +
    "\"fraction\":{\"$param\":\"fraction\"}}}",
    declarations=Some(declarations),
  )
  let prepared = @lowering_relation.prepare(checked, limits()).unwrap()
  let values = match
    @parameter.bind(
      declarations,
      Some(cursor("{\"items\":4,\"bytes\":11,\"fraction\":0.5}")),
      { max_nodes: 20, max_depth: 10, max_text_bytes: 100, },
    ).unwrap() {
    Ready(values) => values
    NeedsBindings(_) => abort("complete group parameters")
  }
  let owner = @lowering_relation.bind_parameters(
    prepared,
    Some(values),
    max_parameters=3,
    max_name_bytes=18,
  ).unwrap()
  let (group, _) = @lowering_relation.prepare_group(
    owner,
    1,
    20,
    100,
    expression_limits(),
  ).unwrap()
  assert_eq(
    @lowering_relation.group_aggregate_item_limit(
      @lowering_relation.group_aggregate_at(group, 0).unwrap(),
    ),
    Some(4L),
  )
  assert_eq(
    @lowering_relation.group_aggregate_byte_limit(
      @lowering_relation.group_aggregate_at(group, 1).unwrap(),
    ),
    Some(11L),
  )
  assert_eq(
    @lowering_relation.group_aggregate_fraction(
      @lowering_relation.group_aggregate_at(group, 2).unwrap(),
    ),
    Some(0.5),
  )
  let invalid_values = match
    @parameter.bind(
      declarations,
      Some(cursor("{\"items\":4,\"bytes\":11,\"fraction\":2}")),
      { max_nodes: 20, max_depth: 10, max_text_bytes: 100, },
    ).unwrap() {
    Ready(values) => values
    NeedsBindings(_) => abort("complete invalid group parameters")
  }
  let invalid_owner = @lowering_relation.bind_parameters(
    prepared,
    Some(invalid_values),
    max_parameters=3,
    max_name_bytes=18,
  ).unwrap()
  assert_true(
    @lowering_relation.prepare_group(
      invalid_owner,
      1,
      20,
      100,
      expression_limits(),
    )
    is Err(InvalidGroupParameter("fraction")),
  )
}

///|
test "group profile retains exact decimal sum outside numeric observation" {
  let (group, _) = @lowering_relation.prepare_group(
    group_profile_owner("{\"total\":{\"fn\":\"sum\",\"field\":\"d\"}}"),
    1,
    10,
    100,
    expression_limits(),
  ).unwrap()
  let aggregate = @lowering_relation.group_aggregate_at(group, 0).unwrap()
  assert_false(
    @lowering_relation.group_aggregate_requires_numeric_observation(aggregate),
  )
  assert_true(
    @lowering_relation.group_aggregate_result(aggregate).shape
    is @contract.Decimal(precision=38, scale=2),
  )
}

///|
test "general group connects typed kernel roots and canonical AoA params" {
  let owner = expression_pipeline(
    ",{\"group\":{\"by\":[\"id\"],\"aggregates\":{" +
    "\"items\":{\"fn\":\"array_agg\",\"expr\":\"id + 1\"," +
    "\"filter\":\"id > 0\",\"distinct\":true,\"max_items\":3," +
    "\"order_by\":[{\"field\":\"id\",\"dir\":\"desc\"," +
    "\"nulls\":\"first\"}]}}}}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("group kernel")
  }
  let group = @lowering_relation.kernel_group(kernel).unwrap()
  assert_true(@lowering_relation.kernel_count_group(kernel) is None)
  assert_true(
    physical_equal(
      @lowering_relation.group_checked(group),
      @lowering_relation.kernel_checked(kernel),
    ),
  )
  let roots = @lowering_relation.prepare_kernel_roots(
    sequence,
    1,
    root_limits(),
  ).unwrap()
  assert_eq(@lowering_relation.root_count(roots), 2)
  let expression = @lowering_relation.root_at(roots, 0).unwrap()
  let filter = @lowering_relation.root_at(roots, 1).unwrap()
  assert_eq(expression.parameter_pointer, "/aggs/items/expr")
  assert_eq(filter.parameter_pointer, "/aggs/items/filter")
  guard @lowering_relation.group_aggregate_at(group, 0) is Some(aggregate) else {
    fail("group aggregate")
  }
  guard @lowering_relation.group_aggregate_argument(aggregate)
    is @lowering_relation.AggregateExpression(argument) else {
    fail("group expression")
  }
  assert_true(physical_equal(expression.expression, argument))
  assert_true(
    physical_equal(
      filter.expression,
      @lowering_relation.group_aggregate_filter(aggregate).unwrap(),
    ),
  )
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\"," +
    "\"params\":{\"rows\":[{\"id\":1}],\"schema\":{\"id\":{" +
    "\"nullable\":false,\"type\":\"number\"}}}},{\"id\":" +
    "\"aggregate_1\",\"in\":[\"values_0\"],\"op\":\"REL.groupBy\"," +
    "\"params\":{\"aggs\":{\"items\":{\"distinct\":true," +
    "\"expr\":{\"add\":[{\"field\":\"id\"},{\"literal\":1}]}," +
    "\"filter\":{\"gt\":[{\"field\":\"id\"},{\"literal\":0}]},\"fn\":" +
    "\"array_agg\",\"max_items\":3,\"order_by\":[{\"dir\":" +
    "\"desc\",\"field\":\"id\",\"nulls\":\"first\"}]}},\"by\":" +
    "[\"id\"]}},{\"id\":\"group_1\",\"in\":[\"aggregate_1\"]," +
    "\"op\":\"REL.orderByStable\",\"params\":{\"by\":[{\"dir\":" +
    "\"asc\",\"field\":\"id\",\"nulls\":\"first\"}]}}]",
  )
}

///|
test "count-only group keeps the narrow kernel path" {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(
      ",{\"group\":{\"by\":[\"id\"],\"aggregates\":{" +
      "\"n\":{\"fn\":\"count\"}}}}",
    ),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("count group kernel")
  }
  assert_true(@lowering_relation.kernel_count_group(kernel) is Some(_))
  assert_true(@lowering_relation.kernel_group(kernel) is None)
}
