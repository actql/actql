///|
test "selected DATE and LTZ formats retain exact Common temporal values" {
  let columns =
    #|[{"name":"DAY","type":"DATE","nullable":false},{"name":"INSTANT","type":"TIMESTAMP_LTZ","nullable":false,"scale":9}]
  let result = project_result_set(
    test_body(columns, "[[\"2024-02-29\",\"1969-12-31T23:59:59.999999999Z\"]]"),
    test_limits(),
  ).unwrap()
  assert_true(result_set_cell(result, 0, 0).unwrap().value is @admitted.Date("2024-02-29"))
  assert_true(result_set_cell(result, 0, 1).unwrap().value is @admitted.Timestamp("1969-12-31T23:59:59.999999999Z"))
}
