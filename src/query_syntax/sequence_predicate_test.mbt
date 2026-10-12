///|
test "sequence owns the original predicate AST spans and charged expression work" {
  let prefix="sequence(by: [], id: id, time: occurred_ms, pattern: [{as: first, where: "
  let text=prefix+"e.kind = 1"+"}, {as: second, where: TRUE}], within: 20, overlap: 'allow', contiguity: 'adjacent')"
  let call=parse_sga_call(text,query_limits(),source_path="authored-sequence.aql").unwrap()
  guard call.arguments[3].1 is ListValue(parts) && parts[0] is ObjectValue(fields) && fields[1].1 is ExpressionValue(predicate) else {fail("typed source expression role")}
  let expression=sga_predicate_expression(predicate)
  assert_true(expression_node(expression,expression_root(expression)).unwrap().kind is Binary("=",_,_))
  assert_true(expression_work(expression)>0)
  let origin=expression_origin(expression,expression_root(expression)).unwrap()
  assert_eq(@origin.kind(origin),Authored)
  assert_eq(@origin.start(origin).utf16_offset,prefix.length())
  assert_eq(@origin.end(origin).utf16_offset,prefix.length()+"e.kind = 1".length())
  let nodes=Array::makei(expression_node_count(expression),i=>expression_node(expression,i).unwrap())
  for node in nodes {
    if node.kind is Reference(path) { path.clear() }
  }
  assert_true(Array::makei(expression_node_count(expression),i=>expression_node(expression,i).unwrap()).any(node=>node.kind is Reference([_,_])))
}

///|
test "sequence opaque predicates are copied as original owners, not new parses" {
  let source="FROM records |> sequence(by: [], id: id, time: occurred_ms, pattern: [{as: first, where: kind = 1}, {as: second, where: kind = 2}], within: 20, overlap: 'allow', contiguity: 'adjacent')"
  let query=parse_query_script(source,query_limits()).unwrap() |> script_query
  let before=operation_at(query,0).unwrap()
  let again=operation_at(query,0).unwrap()
  guard before is GraphCall(before_call) && again is GraphCall(again_call) else {fail("observed sequence calls")}
  assert_eq(before_call,again_call)
  guard before is GraphCall(call) && call.arguments[3].1 is ListValue(parts) else {fail("original sequence call")}
  parts.clear()
  guard operation_at(query,0) is Some(GraphCall(retained)) && retained.arguments[3].1 is ListValue(parts) else {fail("immutable source argument array")}
  assert_eq(parts.length(),2)
}

///|
test "sequence predicates consume the containing expression node and depth budgets" {
  let source="sequence(by: [], id: id, time: occurred_ms, pattern: [{as: first, where: ((kind = 1))}, {as: second, where: kind = 2}], within: 20, overlap: 'allow', contiguity: 'adjacent')"
  for limits in [{..query_limits(),expression:{..query_limits().expression,max_nodes:2}}, {..query_limits(),expression:{..query_limits().expression,max_depth:1}}] {
    assert_true(parse_sga_call(source,limits) is Err({issue:Syntax(_),span:Some(_)}))
  }
}
