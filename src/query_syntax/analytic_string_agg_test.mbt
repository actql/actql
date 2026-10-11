///|
test "window STRING_AGG uses OVER order and the ordinary literal decoder" {
  for
    (call, delimiter) in [
      ("STRING_AGG(name)", ","),
      ("STRING_AGG(name, (('|')))", "|"),
      ("`sTrInG_aGg`(name, '' /* separator */ '\\r' '\\n')", "\r\n"),
    ] {
    let query = parse_query(
      "SELECT " +
      call +
      " OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS names FROM records",
      query_limits(),
    ).unwrap()
    match operation_at(query, 0) {
      Some(Analytic(projections)) => {
        let call = projections[0].analytic.unwrap()
        let aggregate = call.aggregate.unwrap()
        assert_eq(aggregate.function_name, "STRING_AGG")
        assert_eq(aggregate.delimiter, Some(delimiter))
        assert_eq(aggregate.order_by.length(), 0)
        assert_eq(call.window.order_by.length(), 1)
      }
      _ => fail("expected analytic projection")
    }
  }
}

///|
test "ordinary STRING_AGG retains its explicit order profile" {
  assert_true(
    parse_query("SELECT STRING_AGG(name) AS names FROM records", query_limits())
    is Err({ issue: Syntax("Expected ORDER"), .. }),
  )
}
