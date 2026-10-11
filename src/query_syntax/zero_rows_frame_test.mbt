///|
test "zero ROWS literals retain their authored boundary direction" {
  for
    (text, start, end) in [
      ("0 PRECEDING", FrameBoundary::Preceding(0L), FrameBoundary::CurrentRow),
      (
        "BETWEEN 0 PRECEDING AND 0 FOLLOWING",
        FrameBoundary::Preceding(0L),
        FrameBoundary::Following(0L),
      ),
      (
        "BETWEEN 0 FOLLOWING AND 0 FOLLOWING",
        FrameBoundary::Following(0L),
        FrameBoundary::Following(0L),
      ),
      (
        "BETWEEN 0 PRECEDING AND 0 PRECEDING",
        FrameBoundary::Preceding(0L),
        FrameBoundary::Preceding(0L),
      ),
    ] {
    let query = parse_query(
      "SELECT SUM(amount) OVER (ORDER BY id ROWS " +
      text +
      ") AS total FROM orders",
      query_limits(),
    ).unwrap()
    match operation_at(query, 0) {
      Some(Analytic(projections)) => {
        let frame = projections[0].analytic.unwrap().window.frame.unwrap()
        assert_eq(frame.start, start)
        assert_eq(frame.end, end)
      }
      _ => fail("zero frame must retain its analytic operation")
    }
  }
}

///|
test "zero ROWS admission does not accept signed fractional or computed distances" {
  for boundary in ["-0", "0.0", "(0)", "0 + 1", "NULL", "amount"] {
    assert_true(
      parse_query(
        "SELECT SUM(amount) OVER (ORDER BY id ROWS " +
        boundary +
        " PRECEDING) AS total FROM orders",
        query_limits(),
      )
      is Err({ issue: Syntax(_), .. }),
      msg=boundary,
    )
  }
}
