///|
test "date calendar evaluates exact days and the containing month" {
  for
    (source, date) in [
      (
        (
          #|{"date_interval_add":[{"date_literal":"2000-02-29"},{"literal":"1"},{"literal":"d"}]}
        ),
        "2000-03-01",
      ),
      (
        (
          #|{"date_interval_add":[{"date_literal":"1900-03-01"},{"literal":"-1"},{"literal":"d"}]}
        ),
        "1900-02-28",
      ),
      (
        (
          #|{"date_boundary_trunc":[{"date_literal":"1969-12-31"},{"literal":"month"}]}
        ),
        "1969-12-01",
      ),
    ] {
    assert_true(
      run_expr(source) is Ok(Captured(@admitted.Date(actual))) && actual == date,
      msg=source,
    )
  }
  assert_true(
    run_expr(
      (
        #|{"date_boundary_diff":[{"date_literal":"2000-02-28"},{"date_literal":"2000-03-01"},{"literal":"d"}]}
      ),
    )
    is Ok(Captured(@admitted.Signed64(-2L))),
  )
}

///|
test "date calendar bounds interval scaling and keeps strict child evaluation" {
  for
    source in [
      (
        #|{"date_interval_add":[{"date_literal":"9999-12-31"},{"literal":"1"},{"literal":"d"}]}
      ),
      (
        #|{"date_interval_add":[{"date_literal":"2000-02-29"},{"literal":"-9223372036854775808"},{"literal":"d"}]}
      ),
      (
        #|{"date_interval_add":[{"literal":null},{"integer_divide":[{"cast":{"target":{"type":"int64"},"value":{"literal":"1"}}},{"cast":{"target":{"type":"int64"},"value":{"literal":"0"}}}]},{"literal":"d"}]}
      ),
    ] {
    assert_true(
      run_expr(source) is Err({ kind: Scalar(ArithmeticFailure), .. }),
      msg=source,
    )
  }
  assert_true(
    run_expr(
      (
        #|{"date_boundary_diff":[{"literal":null},{"date_literal":"2000-03-01"},{"literal":"d"}]}
      ),
    )
    is Ok(Null),
  )
}
