///|
fn union_fold_test_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn union_fold_test_carrier(reordered? : Bool = false) -> @carrier.Carrier {
  let number = @contract.primitive(NumberType, nullable=true)
  let fields : Array[(@schema.FieldName, @contract.Contract?)] = if reordered {
    [
      (@schema.Unqualified("Q"), Some(number)),
      (@schema.Unqualified("p"), Some(number)),
    ]
  } else {
    [
      (@schema.Unqualified("p"), Some(number)),
      (@schema.Unqualified("q"), Some(number)),
    ]
  }
  let properties = @carrier.rows(
    fields,
    field_set=Closed,
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  let key = @contract.primitive(NumberType, nullable=false)
  let node = @carrier.property_node_definition(
    "N",
    [key],
    properties,
    ["Entity"],
    key_columns=["node_key"],
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  let edge = @carrier.property_edge_definition(
    @carrier.property_node_definition(
      "E",
      [key],
      properties,
      ["Connection"],
      key_columns=["edge_key"],
      max_fields=10,
      max_name_bytes=100,
    ).unwrap(),
    "N",
    "N",
  ).unwrap()
  @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [node],
    [edge],
    max_definitions=10,
    max_contract_work=1000,
  ).unwrap()
}

///|
fn union_fold_test_limits() -> @storage.Limits {
  {
    max_input_rows: 100,
    max_nodes: 100,
    max_edges: 100,
    max_value_bytes: 10000,
    max_total_value_bytes: 1000000,
    max_retained_value_bytes: 1000000,
    max_value_nodes: 100,
    max_value_depth: 100,
    max_contract_work: 10000,
    max_work: 1000000,
    max_workspace_slots: 100000,
  }
}

///|
fn union_fold_test_input(
  carrier : @carrier.Carrier,
  reordered? : Bool = false,
  conflict? : Bool = false,
) -> @storage.Storage {
  let builder = @storage.prepare(
    carrier,
    DeclaredNodes,
    union_fold_test_limits(),
  ).unwrap()
  let number = @contract.primitive(NumberType, nullable=false)
  let nullable = @contract.primitive(NumberType, nullable=true)
  let key = (value : Double) => {
    union_property_test_value(number, value.to_string())
  }
  // Author the opposite order from canonical identity order. Q/p declaration
  // order differs in the peer; semantic q=7 and p=2 remain independent.
  let props = if reordered {
    [
      union_property_test_value(nullable, "7"),
      union_property_test_value(nullable, "2"),
    ]
  } else {
    [
      union_property_test_value(nullable, "2"),
      union_property_test_value(nullable, "7"),
    ]
  }
  @storage.append_property_node(builder, 0, [key(2)], props).unwrap()
  @storage.append_property_node(builder, 0, [key(1)], props).unwrap()
  @storage.append_property_edge(
    builder,
    0,
    [key(11)],
    [key(1)],
    [key(2)],
    props,
  ).unwrap()
  @storage.append_property_edge(
    builder,
    0,
    [key(10)],
    [key(1)],
    [key(if conflict { 1 } else { 2 })],
    props,
  ).unwrap()
  @storage.finish(builder).unwrap()
}

///|
fn union_fold_test_checked(
  left : @carrier.Carrier,
  right : @carrier.Carrier,
) -> @graph_type.CheckedUnion {
  @graph_type.check_union(
    union_fold_test_cursor(
      "{\"with\":\"peer\",\"merge\":{\"node_properties\":{\"p\":\"number_sum\"},\"edge_properties\":{\"p\":\"number_sum\"}}}",
    ),
    [left, right],
    {
      max_work: 100000,
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
fn union_fold_test_finish(
  value : UnionFoldPreparation,
  quantum : Int,
) -> (@storage.Storage, Int) raise {
  let mut work = 0
  for _ in 0..<100000 {
    match advance_union_fold(value, quantum) {
      UnionFoldContinue(used) => {
        assert_true(used > 0 && used <= quantum)
        work += used
      }
      UnionFoldComplete(storage, used) => {
        assert_true(used > 0 && used <= quantum)
        return (storage, work + used)
      }
      UnionFoldFailed(issue, _) =>
        abort("unexpected union fold failure " + @debug.to_string(issue))
    }
  }
  abort("finite union fixture failed to finish")
}

///|
test "union fold aligns shared node and edge properties and retains parallel identities" {
  let left_carrier = union_fold_test_carrier()
  let right_carrier = union_fold_test_carrier(reordered=true)
  let left = union_fold_test_input(left_carrier)
  let right = union_fold_test_input(right_carrier, reordered=true)
  let checked = union_fold_test_checked(left_carrier, right_carrier)
  let mut expected_work = None
  for quantum in [1, 7, 64] {
    let builder = @storage.prepare(
      @graph_type.union_fold_output(checked, 0).unwrap(),
      DeclaredNodes,
      union_fold_test_limits(),
    ).unwrap()
    let value = prepare_union_fold(
      checked,
      0,
      Accumulated(left),
      Accumulated(right),
      builder,
      union_fold_test_limits(),
      100000,
    ).unwrap()
    let (output, work) = union_fold_test_finish(value, quantum)
    if expected_work is Some(previous) {
      assert_eq(work, previous)
    } else {
      expected_work = Some(work)
    }
    cleanup_union_fold(value)
    assert_eq(@storage.node_count(output), 2)
    assert_eq(@storage.edge_count(output), 2)
    for node in 0..<2 {
      // Independent canonical identity, not an expectation derived from union.
      let expected = "{\"definition\":\"N\",\"domain\":\"sha256:" +
        "0".repeat(64) +
        "\",\"key\":[" +
        (node + 1).to_string() +
        "],\"key_types\":[{\"kind\":\"number\"}]}"
      assert_eq(
        union_property_test_wire(@storage.node_identity(output, node).unwrap()),
        expected,
      )
      assert_eq(
        union_property_test_wire(
          @storage.node_property(output, node, 0).unwrap(),
        ),
        "4",
      )
      assert_eq(
        union_property_test_wire(
          @storage.node_property(output, node, 1).unwrap(),
        ),
        "7",
      )
    }
    for edge in 0..<2 {
      let expected = "{\"definition\":\"E\",\"domain\":\"sha256:" +
        "0".repeat(64) +
        "\",\"key\":[" +
        (edge + 10).to_string() +
        "],\"key_types\":[{\"kind\":\"number\"}]}"
      assert_eq(
        union_property_test_wire(@storage.edge_identity(output, edge).unwrap()),
        expected,
      )
      assert_eq(
        union_property_test_wire(
          @storage.edge_property(output, edge, 0).unwrap(),
        ),
        "4",
      )
      assert_eq(
        union_property_test_wire(
          @storage.edge_property(output, edge, 1).unwrap(),
        ),
        "7",
      )
      assert_eq(@storage.edge_endpoints(output, edge), Some((0, 1)))
    }
    assert_true(
      @canonical.compare_utf16(
        @storage.node_identity_order_key(output, 0).unwrap(),
        @storage.node_identity_order_key(output, 1).unwrap(),
      ) <
      0,
    )
    assert_true(
      @canonical.compare_utf16(
        @storage.edge_identity_order_key(output, 0).unwrap(),
        @storage.edge_identity_order_key(output, 1).unwrap(),
      ) <
      0,
    )
    assert_true(
      @storage.available(left) &&
      @storage.available(right) &&
      @storage.available(output),
    )
    @storage.discard(output)
  }
}

///|
test "union fold rejects endpoint collision after positive work without exposing output or reclaiming inputs" {
  let carrier = union_fold_test_carrier()
  let left = union_fold_test_input(carrier)
  let right = union_fold_test_input(carrier, conflict=true)
  let checked = union_fold_test_checked(carrier, carrier)
  let builder = @storage.prepare(
    @graph_type.union_fold_output(checked, 0).unwrap(),
    DeclaredNodes,
    union_fold_test_limits(),
  ).unwrap()
  let value = prepare_union_fold(
    checked,
    0,
    Accumulated(left),
    Accumulated(right),
    builder,
    union_fold_test_limits(),
    100000,
  ).unwrap()
  let mut total = 0
  for _ in 0..<100000 {
    match advance_union_fold(value, 1) {
      UnionFoldContinue(work) => total += work
      UnionFoldFailed(UnionEndpointConflict, work) => {
        total += work
        break
      }
      _ => abort("endpoint collision did not refuse atomically")
    }
  } nobreak {
    abort("collision fixture did not terminate")
  }
  assert_true(total > 0)
  assert_eq(@storage.builder_node_count(builder), 2)
  assert_eq(@storage.builder_edge_count(builder), 0)
  cleanup_union_fold(value)
  cleanup_union_fold(value)
  assert_eq(@storage.builder_node_count(builder), 0)
  assert_true(@storage.available(left) && @storage.available(right))
  assert_eq(@storage.edge_count(left), 2)
  assert_eq(@storage.edge_count(right), 2)
}

///|
test "empty union fold has independent scan and completion work with an exact one short boundary" {
  let carrier = union_fold_test_carrier()
  let left = @storage.finish(
    @storage.prepare(carrier, DeclaredNodes, union_fold_test_limits()).unwrap(),
  ).unwrap()
  let right = @storage.finish(
    @storage.prepare(carrier, DeclaredNodes, union_fold_test_limits()).unwrap(),
  ).unwrap()
  let checked = union_fold_test_checked(carrier, carrier)
  // For each entity kind: empty left scan, empty right scan. The fifth action
  // seals the private Store. Empty input never waives composition admission.
  let scan = 2 * 2
  let seal = 1
  let total = scan + seal
  assert_eq(total, 5)
  for quantum in [1, 64] {
    for ceiling in [total - 1, total] {
      let builder = @storage.prepare(
        @graph_type.union_output(checked),
        DeclaredNodes,
        union_fold_test_limits(),
      ).unwrap()
      let active = prepare_union_fold(
        checked,
        0,
        Accumulated(left),
        Accumulated(right),
        builder,
        union_fold_test_limits(),
        ceiling,
      ).unwrap()
      let mut work = 0
      for _ in 0..<10 {
        match advance_union_fold(active, quantum) {
          UnionFoldContinue(used) => work += used
          UnionFoldComplete(result, used) => {
            work += used
            assert_eq(ceiling, total)
            assert_eq(work, total)
            assert_eq(@storage.node_count(result), 0)
            assert_eq(@storage.edge_count(result), 0)
            @storage.discard(result)
            break
          }
          UnionFoldFailed(UnionFoldWorkLimit, used) => {
            work += used
            assert_eq(ceiling, total - 1)
            assert_eq(work, scan)
            break
          }
          _ => abort("unexpected empty union work boundary")
        }
      } nobreak {
        abort("empty union did not terminate")
      }
      cleanup_union_fold(active)
      assert_true(@storage.available(left) && @storage.available(right))
    }
  }
}
