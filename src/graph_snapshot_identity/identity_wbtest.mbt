///|
fn limits() -> Limits {
  {
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
    value_limits: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  }
}

///|
fn number(value : Double) -> @value.CheckedValue {
  let contract = @contract.primitive(NumberType, nullable=false)
  @value.recheck_runtime_value(
    @value.number_value(value).unwrap(),
    contract,
    limits().value_limits,
  ).unwrap()
}

///|
fn text(value : String) -> @value.CheckedValue {
  @value.checked_text_value(
    value,
    @contract.primitive(StringType, nullable=false),
  ).unwrap()
}

///|
fn snapshot(reverse_properties? : Bool = false) -> String {
  let builder = prepare(
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    limits(),
  ).unwrap()
  begin_node(builder, number(1.0)).unwrap()
  if reverse_properties {
    append_property(builder, "z", text("last")).unwrap()
    return match append_property(builder, "a", number(2.0)) {
      Err(InvalidPropertyOrder) => "invalid"
      _ => "accepted"
    }
  }
  append_property(builder, "a", number(2.0)).unwrap()
  append_property(builder, "z", text("last")).unwrap()
  end_node(builder).unwrap()
  end_nodes(builder).unwrap()
  begin_edge(builder, number(1.0), number(1.0), None).unwrap()
  end_edge(builder).unwrap()
  finish(builder).unwrap()
}

///|
test "graph snapshot identity has an independently fixed preimage" {
  assert_eq(
    snapshot(),
    "sha256:cb6e72527d57d5cc88e9144b16f985ff80a11f9939ce287bcff0314297b804f5",
  )
}

///|
test "graph snapshot identity rejects noncanonical record order" {
  let builder = prepare(
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    limits(),
  ).unwrap()
  begin_node(builder, number(2.0)).unwrap()
  end_node(builder).unwrap()
  assert_eq(begin_node(builder, number(1.0)), Err(InvalidNodeOrder))
  assert_eq(snapshot(reverse_properties=true), "invalid")
}

///|
/// Canonical typed node-ID order puts 9 before 10; the canonical key encoding
/// would put "10" first. The expected CID is the SHA-256 of the specified
/// preimage computed outside this implementation.
test "graph snapshot identity orders numeric IDs by typed value" {
  let builder = prepare(
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    limits(),
  ).unwrap()
  for id in [9.0, 10.0] {
    begin_node(builder, number(id)).unwrap()
    end_node(builder).unwrap()
  }
  end_nodes(builder).unwrap()
  for edge in [(9.0, 10.0, None), (9.0, 10.0, Some("a")), (10.0, 9.0, None)] {
    let (source, target, label) = edge
    begin_edge(builder, number(source), number(target), label.map(text)).unwrap()
    end_edge(builder).unwrap()
  }
  assert_eq(
    finish(builder),
    Ok(
      "sha256:58e79d832142c356f3d84c82aaefe02107299e2c35ad0ee4ea7f9b775462e8b2",
    ),
  )
}

///|
test "graph snapshot identity rejects encoding order where typed order differs" {
  let nodes = prepare(
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    limits(),
  ).unwrap()
  begin_node(nodes, number(10.0)).unwrap()
  end_node(nodes).unwrap()
  assert_eq(begin_node(nodes, number(9.0)), Err(InvalidNodeOrder))
  let edges = prepare(
    "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    limits(),
  ).unwrap()
  end_nodes(edges).unwrap()
  begin_edge(edges, number(9.0), number(10.0), Some(text("a"))).unwrap()
  end_edge(edges).unwrap()
  // An absent label sorts before a present one on the same endpoints.
  assert_eq(
    begin_edge(edges, number(9.0), number(10.0), None),
    Err(InvalidEdgeOrder),
  )
  begin_edge(edges, number(10.0), number(9.0), None).unwrap()
  end_edge(edges).unwrap()
  assert_eq(
    begin_edge(edges, number(9.0), number(11.0), None),
    Err(InvalidEdgeOrder),
  )
}
