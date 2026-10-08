///|
test "quoted aggregate names retain ordinary aggregate clauses" {
  for
    (name, expected) in [
      ("`COUNT`", "COUNT"),
      ("`vAr_PoP`", "VAR_POP"),
      ("`\\x56AR_POP`", "VAR_POP"),
    ] {
    let argument = if expected == "COUNT" { "*" } else { "amount" }
    let query = parse_query(
      "SELECT " + name + "(" + argument + ") AS n FROM orders",
      query_limits(),
    ).unwrap()
    guard operation_at(query, 0) is Some(Group(_, projections, SqlSelect)) else {
      fail("decoded aggregate call must create Group")
    }
    assert_eq(projections[0].aggregate.unwrap().function_name, expected)
  }
}

///|
test "quoted aggregate spelling does not loosen star or argument restrictions" {
  for
    text in [
      "SELECT `VAR_POP`(*) AS n FROM orders", "SELECT `COUNT`(DISTINCT *) AS n FROM orders",
      "SELECT `VAR_POP`() AS n FROM orders", "SELECT `VAR_POP`(amount, id) AS n FROM orders",
    ] {
    assert_true(
      parse_query(text, query_limits()) is Err({ issue: Syntax(_), .. }),
      msg=text,
    )
  }
}
