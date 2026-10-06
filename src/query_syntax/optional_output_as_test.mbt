///|
test "optional output AS retains names in SQL Pipe and aggregate projections" {
  for
    text in [
      "SELECT id next_id FROM records WHERE id > 0 ORDER BY next_id", "FROM records |> SELECT id `next_id` |> ORDER BY next_id",
      "FROM records |> EXTEND id + 1 next_id |> SELECT next_id", "SELECT COUNT(*) n FROM records",
      "FROM records |> AGGREGATE COUNT(*) n", "SELECT COUNT(*) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) n FROM records",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    let mut found = false
    for index in 0..<operation_count(query) {
      match operation_at(query, index) {
        Some(Select(projections, _))
        | Some(Extend(projections))
        | Some(Group(_, projections, _)) =>
          for projection in projections {
            if projection.name is Some(_) {
              found = true
            }
          }
        _ => ()
      }
    }
    assert_true(found, msg=text)
  }
  let query = parse_query("SELECT 1 `FROM`, 'hello' `GROUP`", query_limits()).unwrap()
  match operation_at(query, 0) {
    Some(Select(projections, _)) => {
      assert_eq(projections[0].name, Some({ value: "FROM", quoted: true, }))
      assert_eq(projections[1].name, Some({ value: "GROUP", quoted: true, }))
    }
    _ => fail("expected two authored quoted output aliases")
  }
}

///|
test "optional AS does not swallow clause starters or incomplete syntax" {
  for
    text in [
      "SELECT id FROM records WHERE id > 0 ORDER BY id LIMIT 1", "SELECT id FROM records UNION ALL SELECT id FROM records ORDER BY id",
      "SELECT id, COUNT(*) n FROM records GROUP BY id HAVING n > 0 ORDER BY id",
      "SELECT 1 id WHERE TRUE", "SELECT 1 id;",
    ] {
    assert_true(parse_query(text, query_limits()) is Ok(_), msg=text)
  }
  for
    text in [
      "SELECT 1 QUALIFY TRUE", "SELECT 1 WINDOW w", "SELECT 1 id extra", "SELECT 1 id FROM",
      "SELECT COUNT(*) FROM records", "SELECT * alias FROM records",
    ] {
    assert_true(
      parse_query(text, query_limits()) is Err({ issue: Syntax(_), .. }),
      msg=text,
    )
  }
}
