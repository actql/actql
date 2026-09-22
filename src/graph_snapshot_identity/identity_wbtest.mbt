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
