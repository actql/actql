///|
test "quoted Graph macros retain their closed binding roles and namespaces" {
  let node : GraphBinding = {
    variable: { value: "a", quoted: false, },
    prefix: "",
    fields: ["id"],
    kind: NodeIdentity("identity"),
    hops: 0,
    label_field: None,
  }
  let edge : GraphBinding = {
    variable: { value: "e", quoted: false, },
    prefix: "edge_",
    fields: ["src", "dst", "label"],
    kind: Edge,
    hops: 0,
    label_field: Some("label"),
  }
  let path : GraphBinding = {
    variable: { value: "p", quoted: false, },
    prefix: "path_",
    fields: ["hop_count"],
    kind: Path,
    hops: 2,
    label_field: None,
  }
  for
    (name, argument, field) in [
      ("NODE_ID", "a", "identity"),
      ("EDGE_SOURCE", "e", "edge_src"),
      ("EDGE_TARGET", "e", "edge_dst"),
      ("EDGE_LABEL", "e", "edge_label"),
      ("PATH_LENGTH", "p", "path_hop_count"),
    ] {
    assert_true(
      graph_macro_value(
        [{ value: name, quoted: true, }],
        [{ value: argument, quoted: true, }],
        [node, edge, path],
      )
      is Some(@expression.Field(value)) &&
      value == field,
      msg=name,
    )
  }
  for
    (name, argument) in [
      ("NODE_ID", "p"),
      ("PATH_LENGTH", "a"),
      ("EDGE_SOURCE", "a"),
      ("UNKNOWN", "e"),
      ("ACTQL.NODE_ID", "a"),
      ("NODE_ID", "missing"),
    ] {
    assert_true(
      graph_macro_value(
        [{ value: name, quoted: true, }],
        [{ value: argument, quoted: false, }],
        [node, edge, path],
      )
      is None,
      msg=name,
    )
  }
  assert_true(
    graph_macro_value(
      [{ value: "ACTQL", quoted: true, }, { value: "NODE_ID", quoted: true, }],
      [{ value: "a", quoted: true, }],
      [node],
    )
    is None,
  )
}
