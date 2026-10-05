///|
fn subtraction_fold_checked(
  carrier : @carrier.Carrier,
  merge : String,
) -> @graph_type.CheckedUnion {
  @graph_type.subtraction_composition(
    @graph_type.check_subtraction(
      union_fold_test_cursor("{\"with\":\"peer\"" + merge + "}"),
      carrier,
      carrier,
      {
        max_work: 100000,
        max_nodes: 10000,
        max_text_bytes: 100000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn subtraction_fold_input(
  carrier : @carrier.Carrier,
  nodes : Array[Double],
  edges : Array[Double],
  conflict? : Bool = false,
  p? : String = "2",
  null_node? : Double? = None,
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
  let properties = [
    union_property_test_value(nullable, p),
    union_property_test_value(nullable, "7"),
  ]
  for node in nodes {
    let values = if null_node == Some(node) {
      [union_property_test_value(nullable, "null"), properties[1]]
    } else {
      properties
    }
    @storage.append_property_node(builder, 0, [key(node)], values).unwrap()
  }
  for edge in edges {
    @storage.append_property_edge(
      builder,
      0,
      [key(edge)],
      [key(1)],
      [key(if conflict { 1 } else { 2 })],
      properties,
    ).unwrap()
  }
  @storage.finish(builder).unwrap()
}

///|
fn subtraction_fold_prepare(
  carrier : @carrier.Carrier,
  left : @storage.Storage,
  right : @storage.Storage,
  merge : String,
  work? : Int = 100000,
) -> (UnionFoldPreparation, @storage.Builder) {
  let checked = subtraction_fold_checked(carrier, merge)
  let builder = @storage.prepare(
    @graph_type.union_fold_output(checked, 0).unwrap(),
    DeclaredNodes,
    union_fold_test_limits(),
  ).unwrap()
  (
    prepare_union_fold(
      checked,
      0,
      Accumulated(left),
      Accumulated(right),
      builder,
      union_fold_test_limits(),
      work,
      subtraction=true,
    ).unwrap(),
    builder,
  )
}

///|
test "subtraction fold distinguishes removing shared entities and explicitly retaining transformations" {
  let carrier = union_fold_test_carrier()
  let input = union_fold_test_input(carrier)
  for
    (merge, nodes, edges, p) in [
      ("", 0, 0, "2"),
      (",\"merge\":{\"node_properties\":{\"p\":\"exact_equal\"}}", 2, 0, "2"),
      (
        ",\"merge\":{\"node_properties\":{\"p\":\"number_sum\"},\"edge_properties\":{\"p\":\"number_sum\"}}",
        2, 2, "4",
      ),
    ] {
    let mut expected_work = None
    for quantum in [1, 7, 64] {
      let (active, _) = subtraction_fold_prepare(carrier, input, input, merge)
      let (output, work) = union_fold_test_finish(active, quantum)
      assert_eq(@storage.node_count(output), nodes)
      assert_eq(@storage.edge_count(output), edges)
      if expected_work is Some(previous) {
        assert_eq(work, previous)
      } else {
        expected_work = Some(work)
      }
      for node in 0..<nodes {
        assert_eq(
          union_property_test_wire(
            @storage.node_property(output, node, 0).unwrap(),
          ),
          p,
        )
        assert_eq(
          union_property_test_wire(
            @storage.node_property(output, node, 1).unwrap(),
          ),
          "7",
        )
        assert_eq(
          @storage.node_identity_order_key(output, node),
          @storage.node_identity_order_key(input, 1 - node),
        )
      }
      cleanup_union_fold(active)
      @storage.discard(output)
      assert_true(@storage.available(input))
    }
  }
  @storage.discard(input)
}

///|
test "subtraction fold uses retained Builder nodes for induced endpoint closure and independent parallel edges" {
  let carrier = union_fold_test_carrier()
  let left = union_fold_test_input(carrier)
  let right = subtraction_fold_input(carrier, [1], [])
  let (active, _) = subtraction_fold_prepare(carrier, left, right, "")
  let (output, _) = union_fold_test_finish(active, 1)
  assert_eq(@storage.node_count(output), 1)
  assert_eq(@storage.edge_count(output), 0)
  assert_eq(
    union_property_test_wire(@storage.node_typed_key_at(output, 0, 0).unwrap()),
    "2",
  )
  cleanup_union_fold(active)
  @storage.discard(output)
  @storage.discard(right)
  let right = subtraction_fold_input(carrier, [1, 2], [10])
  let (active, _) = subtraction_fold_prepare(
    carrier, left, right, ",\"merge\":{\"node_properties\":{\"p\":\"exact_equal\"}}",
  )
  let (output, _) = union_fold_test_finish(active, 7)
  assert_eq(@storage.node_count(output), 2)
  assert_eq(@storage.edge_count(output), 1)
  assert_eq(
    union_property_test_wire(@storage.edge_typed_key_at(output, 0, 0).unwrap()),
    "11",
  )
  assert_eq(@storage.edge_endpoints(output, 0), Some((0, 1)))
  cleanup_union_fold(active)
  @storage.discard(output)
  assert_true(@storage.available(left) && @storage.available(right))
  @storage.discard(left)
  @storage.discard(right)
}

///|
test "subtraction fold compares conflicts before endpoint closure without reclaiming borrowed inputs" {
  let carrier = union_fold_test_carrier()
  let left = union_fold_test_input(carrier)
  for endpoint in [false, true] {
    let right = subtraction_fold_input(
      carrier,
      [1, 2],
      [10],
      conflict=endpoint,
      p=if endpoint { "2" } else { "3" },
    )
    let (active, builder) = subtraction_fold_prepare(carrier, left, right, "")
    let mut work = 0
    for _ in 0..<100000 {
      match advance_union_fold(active, 1) {
        UnionFoldContinue(used) => work += used
        UnionFoldFailed(issue, used) => {
          work += used
          if endpoint {
            assert_eq(issue, UnionEndpointConflict)
          } else {
            assert_eq(issue, UnionFoldProperty(UnionPropertyConflict))
          }
          break
        }
        _ => abort("subtraction conflict published output")
      }
    } nobreak {
      abort("subtraction conflict did not terminate")
    }
    assert_true(work > 0)
    assert_true(
      @storage.builder_contains_node_identity_order_key(builder, "absent")
      is Some(false),
    )
    cleanup_union_fold(active)
    cleanup_union_fold(active)
    assert_eq(@storage.builder_node_count(builder), 0)
    assert_eq(
      @storage.builder_contains_node_identity_order_key(builder, "absent"),
      None,
    )
    assert_true(@storage.available(left) && @storage.available(right))
    @storage.discard(right)
  }
  @storage.discard(left)
}

///|
test "empty subtraction fold requires four independent scan units and one Store seal" {
  let carrier = union_fold_test_carrier()
  let input = subtraction_fold_input(carrier, [], [])
  let total = 2 * 2 + 1
  for ceiling in [total, total - 1] {
    let (active, builder) = subtraction_fold_prepare(
      carrier,
      input,
      input,
      "",
      work=ceiling,
    )
    let mut work = 0
    for _ in 0..<(total + 1) {
      match advance_union_fold(active, 1) {
        UnionFoldContinue(used) => work += used
        UnionFoldComplete(output, used) => {
          work += used
          assert_eq(ceiling, total)
          assert_eq(work, total)
          assert_eq(@storage.node_count(output), 0)
          assert_eq(@storage.edge_count(output), 0)
          @storage.discard(output)
          break
        }
        UnionFoldFailed(UnionFoldWorkLimit, used) => {
          work += used
          assert_eq(ceiling, total - 1)
          assert_eq(work, ceiling)
          break
        }
        _ => abort("unexpected subtraction budget result")
      }
    } nobreak {
      abort("finite subtraction budget did not terminate")
    }
    cleanup_union_fold(active)
    assert_eq(@storage.builder_node_count(builder), 0)
    assert_true(@storage.available(input))
  }
  @storage.discard(input)
}

///|
test "subtraction fold keeps one sided NULL but rejects shared NULL numeric operands" {
  let carrier = union_fold_test_carrier()
  let left = subtraction_fold_input(
    carrier,
    [2, 1],
    [11, 10],
    null_node=Some(2),
  )
  let right = subtraction_fold_input(carrier, [1], [])
  let merge = ",\"merge\":{\"node_properties\":{\"p\":\"number_sum\"}}"
  let (active, _) = subtraction_fold_prepare(carrier, left, right, merge)
  let (output, _) = union_fold_test_finish(active, 1)
  assert_eq(@storage.node_count(output), 2)
  assert_eq(@storage.edge_count(output), 2)
  assert_eq(
    union_property_test_wire(@storage.node_property(output, 0, 0).unwrap()),
    "4",
  )
  assert_eq(
    union_property_test_wire(@storage.node_property(output, 1, 0).unwrap()),
    "null",
  )
  cleanup_union_fold(active)
  @storage.discard(output)
  @storage.discard(right)
  let right = subtraction_fold_input(carrier, [2], [], null_node=Some(2))
  let (active, builder) = subtraction_fold_prepare(carrier, left, right, merge)
  for _ in 0..<100000 {
    match advance_union_fold(active, 1) {
      UnionFoldContinue(_) => ()
      UnionFoldFailed(UnionFoldProperty(InvalidUnionProperty), _) => break
      _ =>
        abort("shared NULL numeric operand did not produce its typed refusal")
    }
  } nobreak {
    abort("shared NULL fixture did not terminate")
  }
  cleanup_union_fold(active)
  assert_eq(@storage.builder_node_count(builder), 0)
  assert_true(@storage.available(left) && @storage.available(right))
  @storage.discard(left)
  @storage.discard(right)
}
