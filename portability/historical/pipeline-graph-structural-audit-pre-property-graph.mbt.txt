///|
fn structural_audit_producer(n : Int) -> @pipeline_typing.ProducedInput {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[" +
      graph_count_seed(n) +
      ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  @pipeline_typing.produced_input(p, Step(1)).unwrap()
}

///|
test "structural graph consumers keep directional imported bounds through both row bridges" {
  let mut cases = 0
  for left_count in [0, 1, 3] {
    for right_count in [0, 2, 4] {
      let left = structural_audit_producer(left_count)
      let right = structural_audit_producer(right_count)
      for op in ["graft_graph", "union_graphs", "subtract_graphs"] {
        let body = cursor(
          "[{\"from\":\"l\",\"" +
          op +
          "\":{\"with\":\"r\"},\"as\":\"combined\"},{\"node_rows\":true},{\"from\":\"combined\",\"edge_rows\":true}]",
        )
        let inputs = [
          ("l", @pipeline_typing.ProducedInput(left)),
          ("r", @pipeline_typing.ProducedInput(right)),
        ]
        let p = @pipeline_typing.check_with_evidence(
          body,
          inputs,
          None,
          None,
          limits(),
        ).unwrap()
        let n = if op == "subtract_graphs" {
          left_count
        } else {
          left_count + right_count
        }
        let bounds = @pipeline_typing.graph_count(p, Step(0)).unwrap()
        assert_eq(bounds.nodes.unwrap().upper, (n * 2).to_int64())
        assert_eq(bounds.edges.unwrap().upper, n.to_int64())
        assert_eq(bounds.nodes.unwrap().exact, n == 0)
        assert_eq(bounds.edges.unwrap().exact, n == 0)
        assert_count(p, 1, (n * 2).to_int64(), n == 0)
        assert_count(p, 2, n.to_int64(), n == 0)
        let step = @pipeline_typing.step_at(p, 0).unwrap()
        assert_eq(@pipeline_typing.input_occurrences(step).map(e => e.target), [
          Input(0),
          Input(1),
        ])
        assert_true(
          physical_equal(@pipeline_typing.input_producer(p, 0).unwrap(), left),
        )
        assert_true(
          physical_equal(@pipeline_typing.input_producer(p, 1).unwrap(), right),
        )
        guard step.operation is GraphStructural(checked~, ..) else {
          abort("structural")
        }
        if op == "subtract_graphs" {
          assert_true(
            @graph.structural_pending(checked).contains(
              CloseSubtractionEndpoints,
            ),
          )
        }
        let u = @pipeline_typing.usage(p)
        let exact = {
          ..limits(),
          max_work: u.work,
          max_nodes: u.nodes,
          max_text_bytes: u.text_bytes,
        }
        assert_true(
          @pipeline_typing.check_with_evidence(body, inputs, None, None, exact)
          is Ok(_),
        )
        for
          cap in [
            { ..exact, max_work: u.work - 1, },
            { ..exact, max_nodes: u.nodes - 1, },
            { ..exact, max_text_bytes: u.text_bytes - 1, },
          ] {
          assert_true(
            @pipeline_typing.check_with_evidence(body, inputs, None, None, cap)
            is Err(_),
          )
        }
        cases += 1
      }
    }
  }
  assert_eq(cases, 27)
}

///|
fn structural_audit_graph(
  nullable : Bool,
  property_name : String,
  label : String,
) -> @carrier.Carrier {
  let properties = @carrier.rows(
    [
      (
        Unqualified(property_name),
        Some(@contract.primitive(NumberType, nullable~)),
      ),
    ],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  @carrier.graph(
    @contract.decimal_contract(38, 9, nullable=false).unwrap(),
    properties,
    properties,
    labels=Some([label]),
    max_labels=1,
    max_label_bytes=100,
  ).unwrap()
}

///|
test "structural graph contracts join property nullability without losing complete field sets" {
  for left_null in [false, true] {
    for right_null in [false, true] {
      let left = structural_audit_graph(left_null, "weight", "red")
      let right = structural_audit_graph(right_null, "weight", "blue")
      for op in ["graft_graph", "union_graphs", "subtract_graphs"] {
        for reverse in [false, true] {
          let inputs = if reverse {
            [("l", right), ("r", left)]
          } else {
            [("l", left), ("r", right)]
          }
          let p = @pipeline_typing.check_carriers(
            cursor(
              "[{\"from\":\"l\",\"" +
              op +
              "\":{\"with\":\"r\"},\"as\":\"combined\"},{\"node_rows\":true},{\"from\":\"combined\",\"edge_rows\":true}]",
            ),
            inputs,
            None,
            None,
            limits(),
          ).unwrap()
          guard @pipeline_typing.step_at(p, 0).unwrap().output
            is @carrier.GraphValue(g) else {
            abort("Graph")
          }
          assert_eq(@carrier.graph_labels(g), Some(["blue", "red"]))
          for index in [1, 2] {
            let schema = @pipeline_typing.schema_at(p, Step(index)).unwrap()
            let value = @schema.lookup(schema, Unqualified("weight")).unwrap()
            assert_true(value.shape is Number)
            assert_eq(value.nullable, left_null || right_null)
          }
        }
        let incompatible = structural_audit_graph(right_null, "other", "blue")
        assert_true(
          @pipeline_typing.check_carriers(
            cursor("[{\"from\":\"l\",\"" + op + "\":{\"with\":\"r\"}}]"),
            [("l", left), ("r", incompatible)],
            None,
            None,
            limits(),
          )
          is Err(_),
        )
      }
    }
  }
}
