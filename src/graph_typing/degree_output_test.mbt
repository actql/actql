///|
test "degree exposes exactly node_id and degree with the original non-null identity" {
  let graph = current_scope_graph()
  for direction in ["in", "out", "both"] {
    let checked = @graph_typing.check_degree(
      cursor("{\"direction\":\"" + direction + "\"}"),
      graph,
      limits(),
    ).unwrap()
    let rows = @carrier.complete_schema(
      @carrier.relation_rows(@graph_typing.degree_output(checked)).unwrap(),
    ).unwrap()
    assert_eq(@row.field_count(rows), 2)
    let identity = @row.lookup(rows, Unqualified("node_id")).unwrap()
    assert_eq(
      identity,
      @carrier.graph_identity(
        match graph {
          @carrier.GraphValue(value) => value
          _ => abort("complete Graph fixture")
        },
      ),
    )
    assert_false(identity.nullable)
    assert_true(@row.lookup(rows, Unqualified("node")) is None)
    let count = @row.lookup(rows, Unqualified("degree")).unwrap()
    assert_eq(count, @contract.primitive(NumberType, nullable=false))
  }
}
