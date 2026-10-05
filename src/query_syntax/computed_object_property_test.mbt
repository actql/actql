///|
test "computed object property access has highest precedence and original spans" {
  let text = "-COALESCE(payload, other).`nested`.score + 1"
  let expression = parse_expression(
    text,
    expression_limits(),
    source_path="computed.sql",
  ).unwrap()
  match kind(expression, expression_root(expression)) {
    Binary("+", left, _) =>
      match kind(expression, left) {
        Unary("-", access) =>
          match kind(expression, access) {
            Property(receiver, name) => {
              assert_eq(name, { value: "score", quoted: false, })
              match kind(expression, receiver) {
                Property(call, name) => {
                  assert_eq(name, { value: "nested", quoted: true, })
                  assert_true(kind(expression, call) is Call(_, _))
                }
                _ => fail("postfix chains must preserve each receiver")
              }
              let node = expression_node(expression, access).unwrap()
              assert_eq(node.start, 1)
              assert_eq(node.end, 40)
              assert_eq(
                @origin.span(expression_origin(expression, access).unwrap()).source_path,
                "computed.sql",
              )
            }
            _ => fail("property access binds inside unary minus")
          }
        _ => fail("expected unary receiver expression")
      }
    _ => fail("arithmetic must enclose postfix access")
  }
}

///|
test "computed object property children retain their receiver owner and remapped indices" {
  let expression = parse_expression(
    "1 + COALESCE(@first, @second).score",
    expression_limits(),
  ).unwrap()
  match kind(expression, expression_root(expression)) {
    Binary(_, _, access) => {
      let child = expression_child(expression, access).unwrap()
      assert_eq(expression_node_count(child), 4)
      match kind(child, expression_root(child)) {
        Property(receiver, _) =>
          match kind(child, receiver) {
            Call(_, args) => {
              assert_eq(kind(child, args[0]), ParameterReference("first"))
              assert_eq(kind(child, args[1]), ParameterReference("second"))
            }
            _ => fail("receiver descendants must not become foreign indices")
          }
        _ => fail("expected access subtree")
      }
    }
    _ => fail("expected enclosing arithmetic")
  }
}

///|
test "computed object property parsing preserves node depth and work ceilings" {
  let text = "COALESCE(@a, @b).nested.score"
  let expression = parse_expression(text, expression_limits()).unwrap()
  let nodes = expression_node_count(expression)
  let work = expression_work(expression)
  assert_true(
    parse_expression(text, {
      ..expression_limits(),
      max_nodes: nodes,
      max_depth: 4,
      max_work: work,
    })
    is Ok(_),
  )
  for
    limited in [
      { ..expression_limits(), max_nodes: nodes - 1, },
      { ..expression_limits(), max_depth: 3, },
      { ..expression_limits(), max_work: work - 1, },
    ] {
    assert_true(
      parse_expression(text, limited) is Err({ issue: Syntax(_), .. }),
    )
  }
  for text in ["COALESCE(@a, @b).", "(@a).1", "(@a)..score"] {
    assert_true(
      parse_expression(text, expression_limits())
      is Err({ issue: Syntax(_), .. }),
    )
  }
}
