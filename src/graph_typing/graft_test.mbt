///|
test "graft owns a binary exact-equal composition and joins property extents" {
  let left = union_test_graph([
    union_test_node("N", [
      (
        "p",
        union_test_contract(
          "{\"type\":\"string\",\"nullable\":false,\"max_utf8_bytes\":3}",
        ),
      ),
    ]),
  ])
  let right = union_test_graph([
    union_test_node("N", [
      (
        "p",
        union_test_contract(
          "{\"type\":\"string\",\"nullable\":true,\"max_utf8_bytes\":9}",
        ),
      ),
    ]),
  ])
  let checked = @graph_typing.check_graft(
    cursor("{\"with\":\"peer\"}"),
    [left, right],
    limits(),
  ).unwrap()
  assert_true(@graph_typing.union_is_graft(checked))
  assert_eq(@graph_typing.union_input_count(checked), 2)
  assert_eq(@graph_typing.union_pending_count(checked), 6)
  assert_eq(
    @graph_typing.union_pending_at(checked, 5),
    Some(@graph_typing.ResolveUnionResources),
  )
  let field = @graph_typing.union_field_at(checked, 0, 0, 0, edge=false).unwrap()
  assert_eq(field.2, @graph_typing.UnionExactEqual)
  assert_true(
    !@graph_typing.union_is_graft(
      @graph_typing.check_union(
        cursor("{\"with\":\"peer\"}"),
        [left, right],
        limits(),
      ).unwrap(),
    ),
  )
}

///|
test "graft refuses lists policies foreign domains and missing properties before execution" {
  let graph = union_test_graph([union_test_node("N", [])])
  for
    body in ["{}", "{\"with\":[\"peer\"]}", "{\"with\":\"peer\",\"merge\":{}}"] {
    assert_true(
      @graph_typing.check_graft(cursor(body), [graph, graph], limits())
      is Err(_),
      msg=body,
    )
  }
  let foreign = union_test_graph(
    [union_test_node("N", [])],
    domain="sha256:" + "1".repeat(64),
  )
  assert_true(
    @graph_typing.check_graft(
      cursor("{\"with\":\"peer\"}"),
      [graph, foreign],
      limits(),
    )
    is Err(_),
  )
  let extra = union_test_graph([
    union_test_node("N", [("p", @contract.primitive(NumberType, nullable=true))]),
  ])
  assert_true(
    @graph_typing.check_graft(
      cursor("{\"with\":\"peer\"}"),
      [graph, extra],
      limits(),
    )
    is Err(_),
  )
}
