///|
fn captured_protocol_rule_height(
  nodes : Array[ProtocolSchemaRule],
  index : Int,
  memo : Array[Int],
) -> Int raise {
  assert_true(index >= 0 && index < nodes.length())
  if memo[index] > 0 {
    return memo[index]
  }
  let children : Array[Int] = match nodes[index] {
    ArrayRule(item, _, _, _) => [item]
    TupleRule(items) | OneOfRule(items) | AnyOfRule(items) | AllOfRule(items) =>
      items
    ObjectRule(properties, _, additional, _, _, _) => {
      let children = properties.map(pair => pair.1)
      children.push(additional)
      children
    }
    NotRule(item) => [item]
    ConditionalRule(a, b, c) => [a, b, c]
    _ => []
  }
  let mut height = 1
  for child in children {
    if child < 0 {
      continue
    }
    // Pinned generated schema is a backward-reference DAG, not recursive data.
    assert_true(child < index)
    height = Int::max(
      height,
      1 + captured_protocol_rule_height(nodes, child, memo),
    )
  }
  memo[index] = height
  height
}

///|
test "captured protocol validation stack is schema-bounded not row-count bounded" {
  let nodes = protocol_schema_nodes()
  // Other protocols may extend the schema DAG. Only the reachable captured
  // Run rules determine this constructor's independently priced stack.
  assert_true(nodes.length() > 0)
  for complete in [false, true] {
    let root = generated_protocol_schema_root("captured_run", complete).unwrap()
    assert_true(root >= 0 && root < nodes.length())
    let height = captured_protocol_rule_height(
      nodes,
      root,
      Array::make(nodes.length(), 0),
    )
    // One continuation per recursive rule visit. The priced24 also includes
    // current/pop/growth carriers, without charging one frame for every row.
    assert_true(2 * height + 4 <= 24)
  }
  assert_true(nodes.any(node => node is ObjectRule(_, _, -2, _, _, _)))
}
