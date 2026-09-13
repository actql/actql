///|
test "formal analytic subjects retain producer Unit and escaped call names without group relabeling" {
  let programs : Array[CheckedProgram] = []
  for _ in 0..<2 {
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      second_stage=true,
      analytic_limit=Some(1000),
      checked_results=programs,
      producer_suffix=",{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"current_row\",\"end\":\"current_row\"},\"functions\":{\"x/y~z\":{\"fn\":\"string_agg\",\"expr\":\"to_string(value)\",\"delimiter\":\",\"}}}},{\"select\":[\"id\",{\"value\":\"x/y~z\"}],\"as\":\"selected\"}",
      producer_result_from="selected",
      extra_step_budget=3,
    )
  }
  let first = unit_analytic_aggregate_source_at(programs[0], 0, 1, 0).unwrap()
  let second = unit_analytic_aggregate_source_at(programs[1], 0, 1, 0).unwrap()
  assert_eq(first.scope, "bytes")
  assert_eq(first.call.name, "x/y~z")
  let unit_cid = unit_definition_cid(programs[0], 0).unwrap()
  let expected = "unit:" +
    unit_cid +
    "#/steps/1/analytic/functions/x~1y~0z/bytes"
  let work = unit_cid.length() + 64 + first.call.name.length() * 4
  assert_eq(analytic_aggregate_subject(first, work), expected)
  assert_eq(analytic_aggregate_subject(second, work), expected)
  assert_false(physical_equal(first.call, second.call))
  assert_true(unit_group_aggregate_source_at(programs[0], 0, 1, 0) is None)
  for
    (stage, step, call) in [
      (-1, 1, 0),
      (0, 0, 0),
      (0, 1, -1),
      (0, 1, 1),
      (1, 1, 0),
    ] {
    assert_true(
      unit_analytic_aggregate_source_at(programs[0], stage, step, call) is None,
    )
  }
  try {
    let _ = analytic_aggregate_subject(first, work - 1)
    fail("subject work underflow accepted")
  } catch {
    UnitBuildFailure::BudgetExceeded => ()
    error => raise error
  }
}
