///|
fn count_checked(
  by : String,
  aggregates : String,
) -> @relation.CheckedOperation {
  let pipeline = checked(
    ",{\"group\":{\"by\":" + by + ",\"aggregates\":" + aggregates + "}}",
  )
  guard @pipeline.step_at(pipeline, 1).unwrap().operation is @pipeline.Unary(op) else {
    abort("group operation")
  }
  op
}

///|
test "count profile retains repeated grouping occurrences and empty aggregate maps" {
  let operation = count_checked("[\"id\",\"id\"]", "{}")
  let group = @lowering_relation.prepare_count_group(operation, 2, 4).unwrap()
  assert_eq(@lowering_relation.count_group_key_count(group), 2)
  for i in 0..<2 {
    assert_eq(
      @schema.reference_name(
        @lowering_relation.count_group_key_at(group, i).unwrap(),
      ),
      "id",
    )
  }
  assert_eq(@lowering_relation.count_group_aggregate_count(group), 0)
  assert_true(
    @lowering_relation.prepare_count_group(operation, 1, 4)
    is Err(PreparationLimit),
  )
  assert_true(
    @lowering_relation.prepare_count_group(operation, 2, 3)
    is Err(PreparationLimit),
  )
  let global = @lowering_relation.prepare_count_group(
    count_checked("[]", "{}"),
    0,
    0,
  ).unwrap()
  assert_eq(@lowering_relation.count_group_key_count(global), 0)
  assert_eq(@lowering_relation.count_group_aggregate_count(global), 0)
}

///|
test "count profile preserves exact owner, key order and canonical count names" {
  let operation = count_checked(
    "[\"id\"]", "{\"z\":{\"fn\":\"count\",\"field\":\"id\"},\"a\":{\"fn\":\"count\"}}",
  )
  let group = @lowering_relation.prepare_count_group(operation, 3, 6).unwrap()
  assert_true(
    physical_equal(@lowering_relation.count_group_checked(group), operation),
  )
  assert_eq(@lowering_relation.count_group_key_count(group), 1)
  assert_eq(
    @schema.reference_name(
      @lowering_relation.count_group_key_at(group, 0).unwrap(),
    ),
    "id",
  )
  assert_eq(@lowering_relation.count_group_aggregate_count(group), 2)
  let first = @lowering_relation.count_group_aggregate_at(group, 0).unwrap()
  let second = @lowering_relation.count_group_aggregate_at(group, 1).unwrap()
  assert_eq(first.name, "a")
  assert_true(first.field is None)
  assert_eq(second.name, "z")
  assert_eq(@schema.reference_name(second.field.unwrap()), "id")
  assert_true(
    @lowering_relation.prepare_count_group(operation, 3, 5)
    is Err(PreparationLimit),
  )
  assert_true(
    @lowering_relation.prepare_count_group(operation, 2, 100)
    is Err(PreparationLimit),
  )
  assert_true(
    @lowering_relation.prepare_count_group(operation, -1, 100)
    is Err(InvalidLimits),
  )
}

///|
test "global count and explicit non-distinct stay admitted without expression roots" {
  let operation = count_checked(
    "[]", "{\"n\":{\"fn\":\"count\",\"field\":\"id\",\"distinct\":false}}",
  )
  let group = @lowering_relation.prepare_count_group(operation, 1, 3).unwrap()
  assert_eq(@lowering_relation.count_group_key_count(group), 0)
  assert_eq(@lowering_relation.count_group_aggregate_count(group), 1)
}

///|
test "count profile rejects other aggregates, expressions, filters and distinct" {
  for
    call in [
      "{\"fn\":\"sum\",\"field\":\"id\"}", "{\"fn\":\"count\",\"expr\":\"id + 1\"}",
      "{\"fn\":\"count\",\"field\":\"id\",\"filter\":\"id > 0\"}", "{\"fn\":\"count\",\"field\":\"id\",\"distinct\":true}",
    ] {
    let operation = count_checked("[]", "{\"n\":" + call + "}")
    assert_true(
      @lowering_relation.prepare_count_group(operation, 10, 100)
      is Err(UnsupportedAggregate(0)),
    )
  }
}

///|
test "count group lowering emits explicit canonical order and preserves distinct false" {
  let owner = expression_pipeline(
    ",{\"group\":{\"by\":[\"id\",\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\",\"field\":\"id\",\"distinct\":false}}}}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":1}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}},{\"id\":\"aggregate_1\",\"in\":[\"values_0\"],\"op\":\"REL.groupBy\",\"params\":{\"aggs\":{\"n\":{\"distinct\":false,\"field\":\"id\",\"fn\":\"count\"}},\"by\":[\"id\",\"id\"]}},{\"id\":\"group_1\",\"in\":[\"aggregate_1\"],\"op\":\"REL.orderByStable\",\"params\":{\"by\":[{\"dir\":\"asc\",\"field\":\"id\",\"nulls\":\"first\"},{\"dir\":\"asc\",\"field\":\"id\",\"nulls\":\"first\"}]}}]",
  )
  assert_eq(
    @lowering_relation.usage(@lowering_relation.bound_preparation(owner)).nodes,
    3,
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..sequence_limits(),
      max_bindings: 2,
    })
    is Err(KernelFailure(1, CountGroupFailure(PreparationLimit))),
  )
}
