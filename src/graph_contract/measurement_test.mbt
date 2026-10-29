///|
test "Graph construction measurement shares the complete keyed contract and all three bounds" {
  let number = @value.primitive(NumberType, nullable=false)
  let carrier = with_properties(
    @carrier.rows(
      [(@row.Unqualified("é"), Some(number))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=10,
    ).unwrap(),
  )
  let original = @graph_contract.admit(carrier, caps()).unwrap()
  let wire = @graph_contract.stringify(original, caps())
  let tree = @canonical.from_json(@json.parse(wire), 10000, 1000, 100000)
  let out = @encode.measuring_writer(100000, 10000, 1000)
  @canonical.emit_value(tree, out)
  let extent = @encode.finish_measurement_usage(out)
  let (bytes, nodes, depth) = extent
  let limits : @graph_contract.Limits = {
    max_bytes: bytes,
    max_nodes: nodes,
    max_depth: depth,
  }
  assert_eq(@graph_contract.measure(carrier, limits).unwrap(), extent)
  for
    short in [
      { ..limits, max_bytes: bytes - 1, },
      { ..limits, max_nodes: nodes - 1, },
      { ..limits, max_depth: depth - 1, },
    ] {
    assert_true(@graph_contract.measure(carrier, short) is Err(BudgetExceeded))
    assert_true(@graph_contract.admit(carrier, short) is Err(BudgetExceeded))
  }
  let again = @graph_contract.admit(carrier, limits).unwrap()
  assert_eq(@graph_contract.cid(again), @graph_contract.cid(original))
  assert_eq(@graph_contract.stringify(again, limits), wire)
  assert_true(
    @graph_contract.measure(@carrier.unknown_carrier(GraphKind), limits)
    is Err(IncompleteGraph),
  )
  assert_true(
    @graph_contract.measure(carrier, { ..limits, max_nodes: -1, })
    is Err(InvalidLimits),
  )
}
