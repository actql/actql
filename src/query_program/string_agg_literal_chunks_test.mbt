///|
test "STRING_AGG literal chunks match the independent delimiter Program" {
  let expected = aggregate_property_order_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent literal-delimited Program is closed")
  }
  for
    text in [
      "SELECT STRING_AGG(name, '' /* separator */ '|' ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "FROM objects |> AGGREGATE STRING_AGG(name, r'' \"|\" '''''' ORDER BY payload.score NULLS LAST, id) AS names",
    ] {
    let actual = checked_aggregate_property_order(text)
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
}
