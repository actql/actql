///|
fn current_node_identity(key : Int) -> String {
  "{\"definition\":\"N\",\"domain\":\"sha256:" +
  "0".repeat(64) +
  "\",\"key\":[" +
  key.to_string() +
  ",\"tenant\"],\"key_types\":[{\"kind\":\"number\"},{\"kind\":\"string\"}]}"
}

///|
test "current MATCH retains repeated full composite identities and ordered projection" {
  let body = cursor(
    "{\"definition\":\"N\",\"label\":\"Node\",\"bindings\":{\"identity\":\"element\"},\"ids\":[" +
    current_node_identity(2) +
    "," +
    current_node_identity(10) +
    "," +
    current_node_identity(2) +
    "],\"fields\":[\"title\",\"element\"]}",
  )
  let graph = current_scope_graph()
  let checked = @graph_typing.check_match(
    Nodes,
    body,
    graph,
    None,
    predicate_limits(),
  ).unwrap()
  assert_eq(@graph_typing.match_id_count(checked), 3)
  assert_eq(
    @graph_typing.match_field_at(checked, 0),
    Some(Unqualified("title")),
  )
  assert_eq(
    @graph_typing.match_field_at(checked, 1),
    Some(Unqualified("element")),
  )
  let detached = @graph_typing.match_ids(checked)
  for i in 0..<3 {
    assert_true(
      physical_equal(
        detached[i],
        @graph_typing.match_id_at(checked, i).unwrap(),
      ),
    )
  }
  detached.clear()
  assert_eq(@graph_typing.match_id_count(checked), 3)
  assert_true(@graph_typing.match_id_at(checked, -1) is None)
  assert_true(@graph_typing.match_id_at(checked, 3) is None)
  assert_true(
    indexed_obligation_copy(
      @graph_typing.match_pending(checked),
      @graph_typing.match_pending_count(checked),
      i => @graph_typing.match_pending_at(checked, i),
      (a, b) => a == b,
    ).contains(ValidateSelectedIdentityMembership),
  )
  let usage = @graph_typing.match_usage(checked)
  let exact = {
    ..predicate_limits(),
    max_work: usage.work,
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
    max_tokens: usage.tokens,
  }
  assert_true(
    @graph_typing.check_match(Nodes, body, graph, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_nodes: usage.nodes - 1, },
      { ..exact, max_text_bytes: usage.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_match(Nodes, body, graph, None, cap) is Err(_),
    )
  }
}

///|
test "current edge MATCH keeps label filtering separate from independent key and endpoints" {
  let graph = current_scope_graph()
  for types in ["[]", "[\"Edge\",\"Edge\"]"] {
    let source = cursor(
      "{\"definition\":\"E\",\"label\":\"Edge\",\"bindings\":{\"identity\":\"element\",\"source\":\"source_id\",\"target\":\"target_id\"},\"types\":" +
      types +
      ",\"where\":\"title = 'ok'\",\"fields\":[\"element\",\"source_id\",\"title\"]}",
    )
    let checked = @graph_typing.check_match(
      Edges,
      source,
      graph,
      None,
      predicate_limits(),
    ).unwrap()
    assert_true(@graph_typing.match_predicate(checked) is Some(_))
    let copy = @graph_typing.match_types(checked).unwrap()
    let count = copy.length()
    copy.clear()
    assert_eq(@graph_typing.match_type_count(checked), Some(count))
    assert_eq(@graph_typing.match_field_count(checked), 3)
    let rows = @carrier.relation_rows(@graph_typing.match_output(checked)).unwrap()
    assert_true(@carrier.lookup(rows, Unqualified("Edge")) is Absent)
    assert_true(@carrier.lookup(rows, Unqualified("edge_type")) is Absent)
    assert_true(
      indexed_obligation_copy(
        @graph_typing.match_pending(checked),
        @graph_typing.match_pending_count(checked),
        i => @graph_typing.match_pending_at(checked, i),
        (a, b) => a == b,
      ).contains(FilterSelectedEdgeTypes),
    )
  }
}
