///|
test "endpoint-tuple projections explicitly reject definition-keyed Graphs" {
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
  let graph = @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [node],
    [],
    max_definitions=1,
    max_contract_work=100,
  ).unwrap()
  let source = cursor("{\"projection\":true}")
  let body = @decode.required(
    @decode.open_object(source).unwrap(),
    "projection",
  ).unwrap()
  for operation in [@carrier_projection.NodeRows, @carrier_projection.EdgeRows] {
    let rejected = @carrier_projection.check(operation, body, graph, limits()).unwrap_err()
    assert_eq(rejected.kind, @carrier_projection.UnsupportedGraphProfile)
    assert_eq(rejected.path, [@source.Key("projection")])
    assert_eq(rejected.span, @decode.cursor_span(body))
  }
}
