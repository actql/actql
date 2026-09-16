///|
test "managed checked view composition preserves exact copies and ordered shadowing" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true))
  let receiver = typed_receiver(
    owner, "[{\"derive\":[{\"a\":\"n\"},{\"n\":\"n + 1\"}]},{\"derive\":[{\"b\":\"a\"},{\"a\":\"n\"},{\"c\":\"b\"}]},{\"select\":[\"a\",\"b\",\"c\",\"n\",\"s\"]}]",
  )
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0), row_kernel(receiver, 1), row_kernel(receiver, 2)],
    1000,
    10000,
    100,
  ).unwrap()
  assert_eq(managed_view_plan_rows(plan), AllRows)
  assert_eq(Array::makei(5, i => managed_view_plan_column(plan, i)), [
    None,
    Some(0),
    Some(0),
    None,
    Some(1),
  ])
  assert_true(managed_view_plan_column_facts(plan, 0) is None)
  let copied = managed_view_plan_column_facts(plan, 2).unwrap()
  assert_eq(copied.source_column, 0)
  assert_eq(copied.exact_measurement.unwrap().bytes, 2)
  assert_true(managed_view_plan_matches(plan, input, Step(2)))
  assert_false(managed_view_plan_matches(plan, input, Step(1)))
  let other = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  assert_false(managed_view_plan_matches(plan, other, Step(2)))
}

///|
test "managed filter derive sort take carries universal bounds but not selected totals" {
  let owner = capture_fixture()
  let live = Ref(true)
  let source = managed_read_fixture(owner, live)
  let receiver = typed_receiver(
    owner, "[{\"select\":[\"n\",\"s\"]},{\"filter\":\"n > 0\"},{\"derive\":{\"copy\":\"s\",\"new\":\"n + 1\"}},{\"sort\":[]},{\"take\":1}]",
  )
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let kernels = Array::makei(5, i => row_kernel(receiver, i))
  let plan = prepare_managed_view_plan(input, kernels, 1000, 10000, 100).unwrap()
  assert_eq(managed_view_plan_rows(plan), SelectedRows)
  assert_eq(Array::makei(4, i => managed_view_plan_column(plan, i)), [
    Some(1),
    Some(0),
    None,
    Some(1),
  ])
  let copy = managed_view_plan_column_facts(plan, 0).unwrap()
  assert_eq(copy.max_value_bytes_bound, 6)
  assert_true(copy.null_free)
  assert_true(copy.exact_measurement is None)
  assert_true(
    prepare_managed_view_plan(input, kernels, 1, 10000, 100) is Err(Limit),
  )
  assert_true(
    prepare_managed_view_plan(input, kernels, 1000, 1, 100) is Err(Limit),
  )
  assert_true(
    prepare_managed_view_plan(input, kernels, 1000, 10000, 1) is Err(Limit),
  )
  assert_true(
    prepare_managed_view_plan(input, [kernels[1]], 1000, 10000, 100)
    is Err(InvalidPath),
  )
  assert_true(
    prepare_managed_view_plan(input, [row_kernel(owner, 1)], 1000, 10000, 100)
    is Err(InvalidPath),
  )
  kernels.clear()
  assert_eq(managed_view_plan_column(plan, 0), Some(1))
  live.val = false
  assert_true(managed_view_plan_column_facts(plan, 0) is None)
  assert_false(managed_view_plan_matches(plan, input, Step(4)))
  assert_true(
    prepare_managed_view_plan(input, [], 1000, 10000, 100) is Err(ForeignInput),
  )
}

///|
test "managed permutation keeps exact column totals without asserting logical identity" {
  let owner = capture_fixture()
  let source = managed_read_fixture(owner, Ref(true))
  let receiver = typed_receiver(owner, "[{\"sort\":[{\"n\":\"desc\"}]}]")
  let input = prepare_managed_producer_read(
    receiver, 0, owner, source, 1000, 10000,
  ).unwrap()
  let plan = prepare_managed_view_plan(
    input,
    [row_kernel(receiver, 0)],
    1000,
    10000,
    100,
  ).unwrap()
  assert_eq(managed_view_plan_rows(plan), PermutedRows)
  assert_eq(
    managed_view_plan_column_facts(plan, 1).unwrap().exact_measurement.unwrap().bytes,
    10,
  )
  let grouped = typed_receiver(
    owner, "[{\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
  )
  let group_input = prepare_managed_producer_read(
    grouped, 0, owner, source, 1000, 10000,
  ).unwrap()
  assert_true(
    prepare_managed_view_plan(
      group_input,
      [row_kernel(grouped, 0)],
      1000,
      10000,
      100,
    )
    is Err(UnsupportedKernel),
  )
}
