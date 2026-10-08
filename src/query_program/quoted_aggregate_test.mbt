///|
test "quoted statistical calls match the independent complete common Program" {
  let expected = statistical_expected_program()
  check_statistical_program(expected)
  for
    text in [
      "SELECT VAR_POP(amount + 1) AS v FROM orders", "SELECT `VAR_POP`(amount + 1) AS v FROM orders",
      "FROM orders |> AGGREGATE `vAr_PoP`(amount + 1) AS v", "SELECT `\\x56AR_POP`(amount + 1) AS v FROM orders",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      values_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
    check_statistical_program(program)
  }
}
