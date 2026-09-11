///|
fn mean_audit_graph(identity : @contract.Contract) -> @carrier.Carrier {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  @carrier.graph(
    identity,
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
}

///|
test "zero-weight graph samples remain explicit validated input occurrences" {
  let g = mean_audit_graph(@contract.primitive(NumberType, nullable=false))
  let invalid = [
    @carrier.unknown_carrier(GraphKind),
    @carrier.unknown_carrier(RelationKind),
    @carrier.unknown_carrier(EventsKind),
    @carrier.unknown_carrier(VectorsKind),
    mean_audit_graph(@contract.primitive(StringType, nullable=false)),
    graph_input(),
  ]
  for zero_first in [false, true] {
    let weights = if zero_first { "[0,1]" } else { "[1,0]" }
    let source = cursor(
      "[{\"mean_graphs\":{\"with\":[\"a\",\"b\"],\"weights\":" +
      weights +
      ",\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":{}}},\"as\":\"m\"},{\"node_rows\":true}]",
    )
    let inputs = [
      ("a", g),
      ("b", g),
      ("unrelated", @carrier.unknown_carrier(VectorsKind)),
    ]
    let p = @pipeline_typing.check_carriers(
      source,
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    let step = @pipeline_typing.step_at(p, 0).unwrap()
    assert_true(step.input is None)
    assert_eq(
      @pipeline_typing.input_occurrences(step).map(e => (e.role, e.target)),
      [
        (@pipeline_typing.Sample(0), @pipeline_typing.Input(0)),
        (@pipeline_typing.Sample(1), @pipeline_typing.Input(1)),
      ],
    )
    guard step.operation is @pipeline_typing.GraphMean(checked) else {
      abort("mean expected")
    }
    assert_eq(
      @graph.mean_weights(@graph.mean_options(checked)),
      if zero_first {
        [0.0, 1.0]
      } else {
        [1.0, 0.0]
      },
    )
    assert_eq(@graph.mean_input_names(@graph.mean_options(checked)), ["a", "b"])
    assert_true(@pipeline_typing.output_schema(p) is Some(_))
    let u = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
      max_tokens: u.tokens,
    }
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, exact)
      is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_nodes: u.nodes - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
      ] {
      assert_true(
        @pipeline_typing.check_carriers(source, inputs, None, None, cap)
        is Err(_),
      )
    }
    for bad in invalid {
      let inputs = if zero_first {
        [("a", bad), ("b", g)]
      } else {
        [("a", g), ("b", bad)]
      }
      assert_true(
        @pipeline_typing.check_carriers(source, inputs, None, None, limits())
        is Err(_),
      )
    }
  }
}
