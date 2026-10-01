///|
fn keyed_profile() -> @carrier.Carrier {
  let empty = @carrier.rows(
    [],
    field_set=@carrier.Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let node = @carrier.property_node_definition(
    "N",
    [@contract.primitive(@contract.NumberType, nullable=false)],
    empty,
    ["Node"],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  @carrier.property_graph(
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    [node],
    [],
    max_definitions=1,
    max_contract_work=100,
  ).unwrap()
}

///|
fn keyed_path_body(mode : String, emit? : String = "paths") -> String {
  let identity = "{\"definition\":\"N\",\"domain\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}"
  "{\"start\":{\"ids\":[" +
  identity +
  "]},\"hops\":[{\"direction\":\"out\"}],\"emit\":\"" +
  emit +
  "\"" +
  mode +
  "}"
}

///|
test "keyed traversal has explicit modes full edge identities and separate profile obligations" {
  for
    (text, mode) in [
      ("walk", @graph_typing.Walk),
      ("trail", @graph_typing.Trail),
      ("acyclic", @graph_typing.Acyclic),
    ] {
    let source = cursor(keyed_path_body(",\"path_mode\":\"" + text + "\""))
    let checked = @graph_typing.check_traverse(
      source,
      keyed_profile(),
      None,
      None,
      predicate_limits(),
    ).unwrap()
    assert_eq(@graph_typing.traverse_property_path_mode(checked), Some(mode))
    let pending = @graph_typing.traverse_pending(checked)
    assert_true(pending.contains(@graph_typing.EnumeratePropertyPaths))
    assert_true(
      pending.contains(@graph_typing.ResolvePropertyGraphTraversalProfile),
    )
    assert_false(pending.contains(@graph_typing.EnumerateSimplePaths))
    assert_false(pending.contains(@graph_typing.ResolveTraversalProfile))
    let rows = @carrier.complete_schema(
      @carrier.relation_rows(@graph_typing.traverse_output(checked)).unwrap(),
    ).unwrap()
    guard @row.lookup(rows, Unqualified("edge_ids")).unwrap().shape
      is @contract.Array(edge, ..) else {
      abort("expected independent edge identity array")
    }
    assert_true(edge.shape is @contract.Json)
    let usage = @graph_typing.traverse_usage(checked)
    let exact = {
      ..predicate_limits(),
      max_work: usage.work,
      max_nodes: usage.nodes,
      max_text_bytes: usage.text_bytes,
      max_tokens: usage.tokens,
    }
    assert_true(
      @graph_typing.check_traverse(source, keyed_profile(), None, None, exact)
      is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: usage.work - 1, },
        { ..exact, max_nodes: usage.nodes - 1, },
        { ..exact, max_text_bytes: usage.text_bytes - 1, },
      ] {
      assert_true(
        @graph_typing.check_traverse(source, keyed_profile(), None, None, cap)
        is Err(_),
      )
    }
  }
}

///|
test "path profile boundaries reject omission reinterpretation and unsupported modes" {
  for
    body in [
      keyed_path_body(""),
      keyed_path_body(",\"path_mode\":\"simple\""),
      keyed_path_body(",\"path_mode\":\"trail\"", emit="nodes"),
    ] {
    assert_true(
      @graph_typing.check_traverse(
        cursor(body),
        keyed_profile(),
        None,
        None,
        predicate_limits(),
      )
      is Err(_),
    )
  }
  let legacy = match_graph()
  let legacy_body = cursor(
    "{\"start\":{\"ids\":[2]},\"hops\":[{\"direction\":\"out\"}],\"emit\":\"paths\"}",
  )
  assert_true(
    @graph_typing.check_traverse(
      legacy_body,
      legacy,
      None,
      None,
      predicate_limits(),
    )
    is Ok(_),
  )
  assert_true(
    @graph_typing.check_traverse(
      cursor(
        "{\"start\":{\"ids\":[2]},\"hops\":[{\"direction\":\"out\"}],\"emit\":\"paths\",\"path_mode\":\"walk\"}",
      ),
      legacy,
      None,
      None,
      predicate_limits(),
    )
    is Err(_),
  )
  assert_true(
    @graph_typing.check_path_contract(
      @graph_typing.TraversedPaths,
      cursor("true"),
      legacy,
      limits(),
      property_paths=true,
    )
    is Err({ kind: @graph_typing.UnsupportedGraphProfile, .. }),
  )
  assert_true(
    @graph_typing.check_selector(
      cursor("{\"ids\":[2]}"),
      legacy,
      None,
      None,
      predicate_limits(),
      property_graph=true,
    )
    is Err(
      @graph_typing.MatchStructure(
        { kind: @graph_typing.UnsupportedGraphProfile, .. }
      )
    ),
  )
}

///|
test "unsupported legacy unary operators explicitly refuse the keyed profile" {
  for
    (operation, body) in [
      (@graph_typing.NormalizeGraph, "true"),
      (@graph_typing.Degree, "{\"direction\":\"out\"}"),
      (@graph_typing.Components, "{\"kind\":\"weak\"}"),
      (@graph_typing.GraphBounds, "{\"max_nodes\":1}"),
    ] {
    guard @graph_typing.check(
        operation,
        cursor(body),
        keyed_profile(),
        None,
        limits(),
      )
      is Err(issue) else {
      abort("unsupported keyed operator was accepted")
    }
    assert_eq(issue.kind, @graph_typing.UnsupportedGraphProfile)
    // Existing contracts retain the same acceptance even for unknown properties.
    assert_true(
      @graph_typing.check(
        operation,
        cursor(body),
        graph(@contract.primitive(NumberType, nullable=false)),
        None,
        limits(),
      )
      is Ok(_),
    )
  }
}

///|
test "legacy property and path schemas never erase keyed graph structure" {
  for entity in [@graph_typing.Nodes, @graph_typing.Edges] {
    guard @graph_typing.check_scope(
        entity,
        cursor("true"),
        keyed_profile(),
        limits(),
      )
      is Err(issue) else {
      abort("legacy homogeneous scope accepted a keyed profile")
    }
    assert_eq(issue.kind, @graph_typing.UnsupportedGraphProfile)
  }
  for kind in [@graph_typing.TraversedPaths, @graph_typing.ShortestPaths] {
    guard @graph_typing.check_path_contract(
        kind,
        cursor("true"),
        keyed_profile(),
        limits(),
      )
      is Err(issue) else {
      abort("endpoint-tuple path contract accepted independent edge identity")
    }
    assert_eq(issue.kind, @graph_typing.UnsupportedGraphProfile)
  }
}

///|
test "legacy equality refuses either keyed operand instead of fabricating a common simple graph" {
  let legacy = complete_graph(
    @contract.primitive(NumberType, nullable=false),
    @contract.primitive(NumberType, nullable=false),
    "a",
  )
  for
    (left, right) in [
      (keyed_profile(), legacy),
      (legacy, keyed_profile()),
      (keyed_profile(), keyed_profile()),
    ] {
    guard @graph_typing.check_equality(
        cursor("{\"with\":\"peer\"}"),
        left,
        right,
        limits(),
      )
      is Err(issue) else {
      abort("incompatible profiles were compared")
    }
    assert_eq(issue.kind, @graph_typing.UnsupportedGraphProfile)
  }
}
