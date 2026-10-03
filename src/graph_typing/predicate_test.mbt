///|
fn current_match_predicate(body : String) -> @decode.Cursor {
  cursor(
    "{\"definition\":\"N\",\"label\":\"Node\",\"bindings\":{\"identity\":\"element\"},\"where\":" +
    body +
    ",\"fields\":[\"title\",\"element\"]}",
  )
}

///|
test "current Graph predicates use the checked definition scope and exact shared budgets" {
  let graph = current_scope_graph()
  let source = current_match_predicate("\"title = 'ok' AND true\"")
  let checked = @graph_typing.check_match(
    Nodes,
    source,
    graph,
    None,
    predicate_limits(),
  ).unwrap()
  let predicate = @graph_typing.match_predicate(checked).unwrap()
  assert_eq(@graph_typing.predicate_reference_count(predicate), 1)
  let usage = @graph_typing.match_usage(checked)
  let exact = {
    ..predicate_limits(),
    max_work: usage.work,
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
    max_tokens: usage.tokens,
  }
  assert_true(
    @graph_typing.check_match(Nodes, source, graph, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_nodes: usage.nodes - 1, },
      { ..exact, max_text_bytes: usage.text_bytes - 1, },
      { ..exact, max_tokens: usage.tokens - 1, },
    ] {
    assert_true(
      @graph_typing.check_match(Nodes, source, graph, None, cap) is Err(_),
    )
  }
  for invalid in ["{\"literal\":1}", "{\"literal\":null}"] {
    assert_true(
      @graph_typing.check_match(
        Nodes,
        current_match_predicate(invalid),
        graph,
        None,
        predicate_limits(),
      )
      is Err(@graph_typing.MatchPredicate(_)),
    )
  }
}

///|
test "current Graph predicate diagnostics preserve structured and text reference locations" {
  let graph = current_scope_graph()
  let structured = current_match_predicate(
    "{\"and\":[{\"literal\":true},{\"field\":\"missing\"}]}",
  )
  guard @graph_typing.check_match(
      Nodes,
      structured,
      graph,
      None,
      predicate_limits(),
    )
    is Err(@graph_typing.MatchPredicate(UnknownPredicateField(reference))) else {
    fail("undefined business property accepted")
  }
  assert_eq(@decode.cursor_path(reference.location.source), [
    @source.Key("where"),
    @source.Key("and"),
    @source.Index(1),
  ])
  let text = current_match_predicate("\"true AND missing\"")
  guard @graph_typing.check_match(Nodes, text, graph, None, predicate_limits())
    is Err(@graph_typing.MatchPredicate(UnknownPredicateField(reference))) else {
    fail("undefined text property accepted")
  }
  assert_eq(reference.name, "missing")
  assert_true(reference.location.range is Some(_))
  // A label is not a synthesized property column.
  assert_true(
    @graph_typing.check_match(
      Nodes,
      current_match_predicate("\"Node = 'Node'\""),
      graph,
      None,
      predicate_limits(),
    )
    is Err(@graph_typing.MatchPredicate(UnknownPredicateField(_))),
  )
}
