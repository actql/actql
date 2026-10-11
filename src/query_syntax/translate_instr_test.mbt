///|
test "SQL and Pipe parse translate instr with ordinary nested expressions" {
  assert_true(
    parse_query("SELECT TRANSLATE('ab','ab','ba') AS value", query_limits())
    is Ok(_),
  )
  assert_true(
    parse_query(
      "SELECT TRUE AS seed |> SELECT INSTR('aaaa','aa',-1,2) AS value",
      query_limits(),
    )
    is Ok(_),
  )
  assert_true(
    parse_query(
      "SELECT TRANSLATE(@s,@f,@t), INSTR(@s,@t,@p,@o)",
      query_limits(),
    )
    is Ok(_),
  )
  assert_true(
    parse_query(
      "SELECT `INSTR`(`TRANSLATE`('a','a','b'),'b') AS value",
      query_limits(),
    )
    is Ok(_),
  )
  assert_true(
    parse_query("SELECT IF(FALSE,INSTR('a','a',0),9) AS value", query_limits())
    is Ok(_),
  )
}
