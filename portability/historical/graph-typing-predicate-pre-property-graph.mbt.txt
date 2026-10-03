///|
fn predicate_limits() -> @graph_typing.PredicateLimits {
  {
    max_work: 100000,
    max_nodes: 100000,
    max_depth: 1000,
    max_text_bytes: 100000,
    max_tokens: 100000,
  }
}

///|
test "graph predicate checks only referenced typed properties with exact shared budgets" {
  let boolean = @contract.primitive(BooleanType, nullable=true)
  let props = @carrier.rows(
    [(Unqualified("active"), Some(boolean)), (Unqualified("untyped"), None)],
    field_set=Open,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let g = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    props,
    props,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  let source = cursor("{\"and\":[{\"field\":\"active\"},{\"literal\":true}]}")
  let c = @graph_typing.check_predicate(
    Nodes,
    source,
    g,
    None,
    predicate_limits(),
  ).unwrap()
  let u = @graph_typing.predicate_usage(c)
  let exact = {
    ..predicate_limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
    max_tokens: u.tokens,
  }
  assert_true(
    @graph_typing.check_predicate(Nodes, source, g, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_predicate(Nodes, source, g, None, cap) is Err(_),
    )
  }
  assert_true(
    @graph_typing.check_predicate(
      Nodes,
      cursor("{\"field\":\"untyped\"}"),
      g,
      None,
      predicate_limits(),
    )
    is Err(UntypedPredicateField(_)),
  )
  assert_true(
    @graph_typing.check_predicate(
      Nodes,
      cursor("{\"literal\":1}"),
      g,
      None,
      predicate_limits(),
    )
    is Err(ExpectedPredicateBoolean(_)),
  )
  assert_true(
    @graph_typing.check_predicate(
      Nodes,
      cursor("{\"literal\":null}"),
      g,
      None,
      predicate_limits(),
    )
    is Err(TypingIssue(_)),
  )
}

///|
test "graph predicate preserves nested and text reference locations" {
  let g = @carrier.unknown_carrier(GraphKind)
  let structured = cursor(
    "{\"and\":[{\"literal\":true},{\"field\":\"missing\"}]}",
  )
  guard @graph_typing.check_predicate(
      Nodes,
      structured,
      g,
      None,
      predicate_limits(),
    )
    is Err(UnknownPredicateField(reference)) else {
    abort("missing field accepted")
  }
  assert_eq(@decode.cursor_path(reference.location.source), [
    @source.Key("and"),
    @source.Index(1),
  ])
  let text = cursor("\"true AND missing\"")
  guard @graph_typing.check_predicate(Edges, text, g, None, predicate_limits())
    is Err(UnknownPredicateField(reference)) else {
    abort("missing text field accepted")
  }
  assert_eq(reference.name, "missing")
  assert_true(reference.location.range is Some(_))
  assert_true(
    @graph_typing.check_predicate(
      Nodes,
      cursor("{\"literal\":true}"),
      g,
      None,
      predicate_limits(),
    )
    is Ok(_),
  )
}
