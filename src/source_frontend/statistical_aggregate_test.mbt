///|
test "statistical aggregate query formats preserve common operation tags" {
  let cases : Array[(String, Format)] = [
    ("SELECT VAR_POP(id) AS v FROM records", Sql),
    ("FROM records |> AGGREGATE VAR_POP(id) AS v", Text),
  ]
  for (text, format) in cases {
    let program = lower(text, format, Some(test_context())).unwrap()
    assert_true(program.document.contains("\"fn\":\"var_pop\""))
  }
}
