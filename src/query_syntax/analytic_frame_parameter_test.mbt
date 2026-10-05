///|
test "ROWS frame Parameters retain the authored direction and name" {
  for (boundary, preceding) in [("PRECEDING", true), ("FOLLOWING", false)] {
    let parsed = parse_query(
      "SELECT FIRST_VALUE(amount) OVER (ORDER BY id ROWS BETWEEN @start " +
      boundary +
      " AND @end " +
      boundary +
      ") AS first FROM orders",
      query_limits(),
    ).unwrap()
    match operation_at(parsed, 0) {
      Some(Analytic(projections)) => {
        let frame = projections[0].analytic.unwrap().window.frame.unwrap()
        if preceding {
          assert_true(frame.start is PrecedingParameter("start"))
          assert_true(frame.end is PrecedingParameter("end"))
        } else {
          assert_true(frame.start is FollowingParameter("start"))
          assert_true(frame.end is FollowingParameter("end"))
        }
      }
      _ => fail("expected analytic operation")
    }
  }
}

///|
test "ROWS numeric boundaries refuse expressions and preserve literal restrictions" {
  for
    boundary in [
      "@p + 1", "amount", "'1'", "NULL", "0", "-1", "1.5", "9007199254740992",
    ] {
    let text = "SELECT FIRST_VALUE(amount) OVER (ORDER BY id ROWS BETWEEN " +
      boundary +
      " PRECEDING AND CURRENT ROW) AS first FROM orders"
    assert_true(
      parse_query(text, query_limits()) is Err({ issue: Syntax(_), .. }),
    )
  }
  for boundary in ["1", "9007199254740991"] {
    assert_true(
      parse_query(
        "SELECT FIRST_VALUE(amount) OVER (ORDER BY id ROWS BETWEEN " +
        boundary +
        " PRECEDING AND CURRENT ROW) AS first FROM orders",
        query_limits(),
      )
      is Ok(_),
    )
  }
}
