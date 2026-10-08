///|
test "short ROWS frame preserves boundary and supplies only the implicit end" {
  for
    (text, boundary) in [
      ("UNBOUNDED PRECEDING", FrameBoundary::UnboundedPreceding),
      ("CURRENT ROW", FrameBoundary::CurrentRow),
      ("2 PRECEDING", FrameBoundary::Preceding(2L)),
      ("@before PRECEDING", FrameBoundary::PrecedingParameter("before")),
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
        assert_eq(frame.start, boundary)
        assert_true(frame.end is CurrentRow)
      }
      _ => fail("short ROWS aggregate must retain its analytic operation")
    }
  }
}
