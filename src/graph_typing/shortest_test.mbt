///|
fn shortest_body(source : String, target : String, options : String) -> String {
  "{\"source\":" +
  source +
  ",\"target\":" +
  target +
  ",\"direction\":\"out\",\"max_hops\":3" +
  options +
  "}"
}

///|
test "Shortest path admits composite single identities and its six-column contract" {
  let checked = @graph_typing.check_shortest(
    cursor(
      shortest_body(current_node_identity(2), current_node_identity(10), ""),
    ),
    current_scope_graph(),
    None,
    None,
    None,
    predicate_limits(),
  ).unwrap()
  assert_eq(@graph_typing.shortest_selection(checked), EachPair)
  assert_eq(@graph_typing.shortest_direction(checked), Outgoing)
  assert_eq(@graph_typing.shortest_maximum_hops(checked), 3.0)
  assert_eq(
    @graph_typing.selector_id_count(@graph_typing.shortest_starts(checked)),
    1,
  )
  assert_eq(
    @graph_typing.selector_id_count(@graph_typing.shortest_targets(checked)),
    1,
  )
  assert_true(@graph_typing.shortest_weight(checked) is None)
  let pending = @graph_typing.shortest_pending(checked)
  assert_true(pending.contains(ValidateEveryShortestWeight))
  assert_true(pending.contains(RejectSelectedOverrange))
  assert_true(pending.contains(RequireShortestMembership))
  assert_true(pending.contains(RespectShortestHopBound))
  assert_true(pending.contains(ResolveShortestResources))
  assert_false(pending.contains(EnforceShortestOutputGuard))
  let rows = @carrier.complete_schema(
    @carrier.relation_rows(@graph_typing.shortest_output(checked)).unwrap(),
  ).unwrap()
  assert_eq(@row.field_count(rows), 6)
  let names = [
    "edge_ids", "hop_count", "node_ids", "source_id", "target_id", "total_cost",
  ]
  for index in 0..<names.length() {
    let field = @row.field_at(rows, index).unwrap()
    assert_eq(field.name, Unqualified(names[index]))
    assert_false(field.contract.nullable)
    match index {
      3 | 4 => assert_true(field.contract.shape is @contract.Json)
      1 | 5 => assert_true(field.contract.shape is @contract.Number)
      _ => {
        guard field.contract.shape is @contract.Array(element, ..) else {
          fail("identity array")
        }
        assert_true(element.shape is @contract.Json)
        assert_false(element.nullable)
      }
    }
  }
}

///|
test "Shortest set selectors require explicit selection and preserve occurrence order" {
  let ids = "{\"ids\":[" +
    current_node_identity(10) +
    "," +
    current_node_identity(2) +
    "," +
    current_node_identity(10) +
    "]}"
  for
    (selection, expected) in [
      ("each_pair", @graph_typing.EachPair),
      ("nearest_per_source", @graph_typing.NearestPerSource),
      ("nearest_pair", @graph_typing.NearestPair),
    ] {
    let checked = @graph_typing.check_shortest(
      cursor(
        shortest_body(
          ids,
          "{\"where\":\"false\"}",
          ",\"selection\":\"" + selection + "\"",
        ),
      ),
      current_scope_graph(),
      None,
      None,
      None,
      predicate_limits(),
    ).unwrap()
    assert_eq(@graph_typing.shortest_selection(checked), expected)
    assert_eq(
      @graph_typing.selector_id_count(@graph_typing.shortest_starts(checked)),
      3,
    )
    assert_eq(
      @graph_typing.selector_id_count(@graph_typing.shortest_targets(checked)),
      0,
    )
  }
  for extra in ["", ",\"selection\":\"first\""] {
    assert_true(
      @graph_typing.check_shortest(
        cursor(shortest_body(ids, current_node_identity(2), extra)),
        current_scope_graph(),
        None,
        None,
        None,
        predicate_limits(),
      )
      is Err(MatchStructure({ kind: InvalidBody, .. })),
    )
  }
  let body = shortest_body(
    current_node_identity(2),
    current_node_identity(10),
    "",
  )
  for
    invalid in [
      body.replace(old="\"max_hops\":3", new="\"max_hops\":0"),
      body.replace(old="\"max_hops\":3", new="\"max_hops\":1.5"),
      body.replace(old="\"out\"", new="\"sideways\""),
      shortest_body(
        current_node_identity(2),
        current_node_identity(10),
        ",\"max_paths\":1",
      ),
    ] {
    assert_true(
      @graph_typing.check_shortest(
        cursor(invalid),
        current_scope_graph(),
        None,
        None,
        None,
        predicate_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "Shortest nullable Relation and predicate selectors share existing typed admission" {
  let relation = @carrier.relation(
    @carrier.rows(
      [
        (
          Unqualified("element"),
          Some(@contract.primitive(JsonType, nullable=true)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=100,
    ).unwrap(),
  )
  let source = "{\"from\":\"selected\",\"id\":\"element\"}"
  let target = "{\"where\":\"title = 'selected'\"}"
  let checked = @graph_typing.check_shortest(
    cursor(
      shortest_body(source, target, ",\"selection\":\"nearest_per_source\""),
    ),
    current_scope_graph(),
    Some(relation),
    None,
    None,
    predicate_limits(),
  ).unwrap()
  assert_true(
    @graph_typing.selector_form(@graph_typing.shortest_starts(checked))
    is RelationIds(from="selected", field=Unqualified("element")),
  )
  assert_true(
    @graph_typing.selector_form(@graph_typing.shortest_targets(checked))
    is NodeWhere,
  )
  assert_true(
    @graph_typing.selector_predicate(@graph_typing.shortest_targets(checked))
    is Some(_),
  )
  for
    (source_relation, target_relation) in [
      (None, Some(relation)),
      (None, None),
      (Some(relation), Some(relation)),
    ] {
    assert_true(
      @graph_typing.check_shortest(
        cursor(
          shortest_body(source, target, ",\"selection\":\"nearest_per_source\""),
        ),
        current_scope_graph(),
        source_relation,
        target_relation,
        None,
        predicate_limits(),
      )
      is Err(_),
    )
  }
  assert_true(
    @graph_typing.check_shortest(
      cursor(
        shortest_body(
          "{\"where\":\"title = 'selected'\"}", "{\"where\":\"true\"}", ",\"selection\":\"each_pair\"",
        ),
      ),
      heterogeneous_traversal_graph(),
      None,
      None,
      None,
      predicate_limits(),
    )
    is Err(MatchPredicate(UnknownPredicateField(_))),
  )
}

///|
test "Shortest weight typing covers every edge definition even outside the label filter" {
  let body = shortest_body(
    "{\"where\":\"true\"}", "{\"where\":\"true\"}", ",\"selection\":\"each_pair\",\"edge_types\":[\"L1\",\"L1\"],\"weight\":\"shared\"",
  )
  let checked = @graph_typing.check_shortest(
    cursor(body),
    heterogeneous_traversal_graph(),
    None,
    None,
    None,
    predicate_limits(),
  ).unwrap()
  assert_eq(@graph_typing.shortest_weight(checked), Some("shared"))
  assert_eq(@graph_typing.shortest_weight_position(checked, 0), Some(0))
  assert_eq(@graph_typing.shortest_weight_position(checked, 1), Some(0))
  assert_eq(@graph_typing.shortest_edge_type_count(checked), Some(2))
  for weight in ["weight", "missing", ""] {
    let issue = @graph_typing.check_shortest(
      cursor(
        body.replace(
          old="\"weight\":\"shared\"",
          new="\"weight\":\"" + weight + "\"",
        ),
      ),
      heterogeneous_traversal_graph(),
      None,
      None,
      None,
      predicate_limits(),
    ).unwrap_err()
    assert_true(issue is MatchStructure({ kind: InvalidWeight, .. }))
  }
  assert_true(
    @graph_typing.check_shortest(
      cursor(
        shortest_body(
          current_node_identity(2),
          current_node_identity(10),
          ",\"weight\":\"title\"",
        ),
      ),
      current_scope_graph(),
      None,
      None,
      None,
      predicate_limits(),
    )
    is Err(MatchStructure({ kind: InvalidWeight, .. })),
  )
}

///|
test "Shortest checker and path schema preserve independently decomposed exact budgets" {
  let body = cursor(
    shortest_body(current_node_identity(2), current_node_identity(10), ""),
  )
  // The authored body has 25 nodes; each 11-node identity is scanned again.
  // Schema admission adds six fields and two wrappers: work 25+22+8, nodes
  // 25+22+2. Text is body 284 + selector names/values 252 + field names 53.
  let exact = {
    ..predicate_limits(),
    max_work: 55,
    max_nodes: 49,
    max_text_bytes: 589,
    max_tokens: 0,
  }
  let checked = @graph_typing.check_shortest(
    body,
    current_scope_graph(),
    None,
    None,
    None,
    exact,
  ).unwrap()
  let usage = @graph_typing.shortest_usage(checked)
  assert_eq(
    (usage.work, usage.nodes, usage.text_bytes, usage.tokens),
    (55, 49, 589, 0),
  )
  for
    cap in [
      { ..exact, max_work: 54, },
      { ..exact, max_nodes: 48, },
      { ..exact, max_text_bytes: 588, },
    ] {
    assert_true(
      @graph_typing.check_shortest(
        body,
        current_scope_graph(),
        None,
        None,
        None,
        cap,
      )
      is Err(MatchStructure({ kind: BudgetExceeded, .. })),
    )
  }
  let schema_exact = {
    ..limits(),
    max_work: 8,
    max_nodes: 2,
    max_text_bytes: 53,
  }
  assert_true(
    @graph_typing.check_path_contract(
      ShortestPaths,
      cursor("true"),
      current_scope_graph(),
      schema_exact,
    )
    is Ok(_),
  )
  for
    cap in [
      { ..schema_exact, max_work: 7, },
      { ..schema_exact, max_nodes: 1, },
      { ..schema_exact, max_text_bytes: 52, },
    ] {
    assert_true(
      @graph_typing.check_path_contract(
        ShortestPaths,
        cursor("true"),
        current_scope_graph(),
        cap,
      )
      is Err(_),
    )
  }
}

///|
test "Shortest weight contracts distinguish required finite numbers from nullable or absent values" {
  guard current_scope_graph() is @carrier.GraphValue(graph) else {
    fail("Graph")
  }
  let profile = @carrier.graph_definition(graph)
  for
    (nullable, presence, valid) in [
      (false, @row.Required, true),
      (true, @row.Required, false),
      (false, @row.Conditional, false),
    ] {
    let properties = @carrier.typed_rows(
      @row.from_presence_fields(
        [
          (
            Unqualified("cost"),
            @contract.primitive(NumberType, nullable~),
            presence,
          ),
        ],
        max_fields=1,
        max_name_bytes=4,
      ).unwrap(),
    )
    let definition = @carrier.graph_node_definition(
      "Weighted",
      [@contract.primitive(NumberType, nullable=false)],
      properties,
      ["Edge"],
      max_fields=1,
      max_name_bytes=100,
    )
    if presence == @row.Conditional {
      // A definition cannot promise a property that its own records may omit.
      // Preserve the existing Graph admission refusal before shortest typing.
      assert_true(definition is Err(@carrier.IncompleteProperties))
      continue
    }
    let edge = @carrier.graph_edge_definition(definition.unwrap(), "N", "N").unwrap()
    let weighted = @carrier.graph(
      @carrier.graph_domain(profile),
      [@carrier.graph_node_at(profile, 0).unwrap()],
      [edge],
      max_definitions=2,
      max_contract_work=1000,
    ).unwrap()
    let result = @graph_typing.check_shortest(
      cursor(
        shortest_body(
          current_node_identity(2),
          current_node_identity(10),
          ",\"weight\":\"cost\"",
        ),
      ),
      weighted,
      None,
      None,
      None,
      predicate_limits(),
    )
    assert_eq(result is Ok(_), valid)
    if !valid {
      assert_true(result is Err(MatchStructure({ kind: InvalidWeight, .. })))
    }
  }
}
