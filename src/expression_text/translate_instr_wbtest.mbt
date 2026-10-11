///|
test "translate instr textual calls preserve exact authored arity and order" {
  assert_tree(
    "translate(s,source,target)", "{\"translate\":[{\"field\":\"s\"},{\"field\":\"source\"},{\"field\":\"target\"}]}",
  )
  assert_tree("instr(s,t)", "{\"instr\":[{\"field\":\"s\"},{\"field\":\"t\"}]}")
  assert_tree(
    "instr(s,t,p)", "{\"instr\":[{\"field\":\"s\"},{\"field\":\"t\"},{\"field\":\"p\"}]}",
  )
  assert_tree(
    "instr(s,t,p,o)", "{\"instr\":[{\"field\":\"s\"},{\"field\":\"t\"},{\"field\":\"p\"},{\"field\":\"o\"}]}",
  )
  assert_true(parse("translate()", test_limits()) is Err(_))
  assert_true(parse("translate(s)", test_limits()) is Err(_))
  assert_true(parse("translate(s,t)", test_limits()) is Err(_))
  assert_true(parse("translate(s,t,u,v)", test_limits()) is Err(_))
  assert_true(parse("instr()", test_limits()) is Err(_))
  assert_true(parse("instr(s)", test_limits()) is Err(_))
  assert_true(parse("instr(s,t,p,o,x)", test_limits()) is Err(_))
}
