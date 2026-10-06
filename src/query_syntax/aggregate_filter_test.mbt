///|
test "aggregate WHERE owns a separate parsed predicate" {
  for
    source in [
      "SELECT COUNT(* WHERE amount > 0) AS n FROM records", "FROM records |> AGGREGATE COUNT(* WHERE amount > 0) AS n",
      "SELECT SUM(DISTINCT amount WHERE id > 0) AS n FROM records", "SELECT ARRAY_AGG(id IGNORE NULLS WHERE amount > 0 ORDER BY id) AS ids FROM records",
      "SELECT COUNT(* WHERE amount > 0) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS n FROM records",
    ] {
    let query = parse_query(source, query_limits()).unwrap()
    match operation_at(query, 0) {
      Some(Group(_, projections, _)) => {
        let filter = projections[0].aggregate.unwrap().filter.unwrap()
        assert_true(
          expression_node(filter, expression_root(filter)).unwrap().kind
          is Binary(">", _, _),
        )
      }
      Some(Analytic(projections)) =>
        assert_true(
          projections[0].analytic.unwrap().aggregate.unwrap().filter is Some(_),
        )
      _ => fail(source)
    }
  }
}

///|
test "aggregate WHERE rejects missing and duplicated predicates with syntax reasons" {
  for
    source in [
      "SELECT COUNT(* WHERE) AS n", "SELECT SUM(1 WHERE TRUE WHERE FALSE) AS n",
      "SELECT ARRAY_AGG(1 WHERE TRUE IGNORE NULLS ORDER BY 1) AS ids",
    ] {
    assert_true(
      parse_query(source, query_limits()) is Err({ issue: Syntax(_), .. }),
      msg=source,
    )
  }
}
