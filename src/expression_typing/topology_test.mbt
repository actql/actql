///|
test "typed topology preserves nested profile operands and immutable semantic bodies" {
  let source = syntax("\"substring(nfkc('ab'), 1, 2)\"")
  let typed = @expression_typing.check(source, env(), test_limits()).unwrap()
  assert_eq(@expression_typing.node_count(typed), 5)
  assert_eq(@expression_typing.child_count(typed, 0), Some(3))
  assert_eq(@expression_typing.child_at(typed, 0, 0), Some(1))
  assert_eq(@expression_typing.child_at(typed, 0, 1), Some(3))
  assert_eq(@expression_typing.child_at(typed, 0, 2), Some(4))
  assert_eq(@expression_typing.child_at(typed, 1, 0), Some(2))
  for
    (i, tag) in [
      (0, "substring"),
      (1, "nfkc"),
      (2, "literal"),
      (3, "literal"),
      (4, "literal"),
    ] {
    match @expression_typing.node_form(typed, i) {
      Some(Expression(actual, body)) => {
        assert_eq(actual, tag)
        assert_true(@decode.tree_index(@syntax.tree(source), body) is Some(_))
        let node = @expression_typing.node_at(typed, i).unwrap()
        assert_eq(node.role, @expression_typing.ExpressionNode)
        assert_true(@syntax.origin(source, node.source) is Some(_))
      }
      _ => fail("expected ordinary semantic node")
    }
  }
  assert_true(physical_equal(@expression_typing.expression(typed), source))
  for index in [-1, 5, 100] {
    assert_true(@expression_typing.node_form(typed, index) is None)
    assert_true(@expression_typing.child_count(typed, index) is None)
    assert_true(@expression_typing.child_at(typed, index, 0) is None)
    assert_true(
      @expression_typing.object_field_name_at(typed, index, 0) is None,
    )
  }
  assert_true(@expression_typing.child_at(typed, 0, -1) is None)
  assert_true(@expression_typing.child_at(typed, 0, 3) is None)
  assert_true(@expression_typing.child_at(typed, 2, 0) is None)
  assert_true(@expression_typing.object_field_name_at(typed, 0, 0) is None)
}

///|
test "typed CASE and membership topology distinguish implicit NULL and literal list values" {
  let typed = @expression_typing.check(
    syntax("\"CASE WHEN TRUE THEN 'a' END\""),
    env(),
    test_limits(),
  ).unwrap()
  assert_eq(@expression_typing.child_count(typed, 0), Some(3))
  assert_true(@expression_typing.node_form(typed, 3) is Some(ImplicitNull))
  assert_eq(
    @expression_typing.node_at(typed, 3).unwrap().role,
    @expression_typing.ImplicitElse,
  )
  let typed = @expression_typing.check(
    syntax("\"1 IN (1, NULL, $p)\""),
    env(parameters="{\"p\":{\"type\":\"number\"}}"),
    test_limits(),
  ).unwrap()
  assert_eq(@expression_typing.child_count(typed, 0), Some(2))
  let list = @expression_typing.child_at(typed, 0, 1).unwrap()
  assert_true(
    @expression_typing.node_form(typed, list) is Some(MembershipList(_)),
  )
  assert_eq(
    @expression_typing.node_at(typed, list).unwrap().role,
    @expression_typing.MembershipList,
  )
  assert_eq(@expression_typing.child_count(typed, list), Some(3))
  for i in 0..<3 {
    let child = @expression_typing.child_at(typed, list, i).unwrap()
    assert_eq(
      @expression_typing.node_at(typed, child).unwrap().role,
      @expression_typing.MembershipElement,
    )
    match @expression_typing.node_form(typed, child) {
      Some(Expression(tag, body)) => {
        assert_eq(tag, if i == 2 { "$param" } else { "literal" })
        if i == 1 {
          assert_true(@decode.is_null(body))
        }
      }
      _ => fail("membership element form")
    }
  }
}

///|
test "object field names follow child ordinals and topology traverses without rescanning source" {
  let typed = @expression_typing.check(
    syntax("{\"object\":{\"b\":{\"literal\":2},\"a\":{\"literal\":1}}}"),
    env(),
    test_limits(),
  ).unwrap()
  assert_eq(@expression_typing.child_count(typed, 0), Some(2))
  for i in 0..<2 {
    let name = @expression_typing.object_field_name_at(typed, 0, i).unwrap()
    let child = @expression_typing.child_at(typed, 0, i).unwrap()
    match @expression_typing.node_form(typed, child) {
      Some(Expression("literal", body)) =>
        assert_eq(
          @decode.finite_number(body).unwrap(),
          if name == "a" {
            1.0
          } else {
            2.0
          },
        )
      _ => fail("object child")
    }
  }
  assert_true(@expression_typing.object_field_name_at(typed, 0, 2) is None)
  let text = "nfkc(".repeat(10000) + "'a'" + ")".repeat(10000)
  let source = syntax("\"" + text + "\"")
  let typed = @expression_typing.check(source, env(), test_limits()).unwrap()
  let mut current = 0
  let mut count = 1
  while @expression_typing.child_at(typed, current, 0) is Some(child) {
    assert_true(child > current)
    current = child
    count += 1
  }
  assert_eq(count, 10001)
  assert_eq(count, @expression_typing.node_count(typed))
}
