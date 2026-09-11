///|
test "unary Graph operations preserve typed identity and distinguish opaque outputs from wrong Carriers" {
  let bodies = [
    ("\"normalize_graph\":true", "", false),
    ("\"degree\":{\"direction\":\"in\"}", "node", false),
    ("\"degree\":{\"direction\":\"out\"}", "node", false),
    ("\"degree\":{\"direction\":\"both\"}", "node", false),
    ("\"components\":{\"kind\":\"weak\"}", "node_id", false),
    ("\"components\":{\"kind\":\"strong\"}", "node_id", false),
    ("\"graph_bounds\":{\"max_nodes\":0}", "node_id", true),
    ("\"graph_bounds\":{\"max_edges\":0}", "node_id", true),
    ("\"graph_bounds\":{\"max_degree\":0}", "node_id", true),
    ("\"graph_bounds\":{\"max_nodes\":0,\"max_edges\":0}", "node_id", true),
    ("\"graph_bounds\":{\"max_nodes\":0,\"max_degree\":0}", "node_id", true),
    ("\"graph_bounds\":{\"max_edges\":0,\"max_degree\":0}", "node_id", true),
    (
      "\"graph_bounds\":{\"max_nodes\":0,\"max_edges\":0,\"max_degree\":0}", "node_id",
      true,
    ),
  ]
  for (body, field, nullable) in bodies {
    let source = cursor("[{" + body + "}]")
    for
      (input, typed) in [
        (graph_input(), true),
        (@carrier.unknown_carrier(GraphKind), false),
        (@carrier.unknown_carrier(RelationKind), false),
        (@carrier.unknown_carrier(EventsKind), false),
        (@carrier.unknown_carrier(VectorsKind), false),
      ] {
      let checked = @pipeline_typing.check_carriers(
        source,
        [("g", input)],
        None,
        None,
        limits(),
      )
      if @carrier.kind(input) != @carrier.GraphKind {
        assert_true(checked is Err(_))
        continue
      }
      let p = checked.unwrap()
      let step = @pipeline_typing.step_at(p, 0).unwrap()
      assert_eq(@pipeline_typing.input_occurrences(step).map(e => e.target), [
        Input(0),
      ])
      guard step.operation is @pipeline_typing.Graph(operation) else {
        abort("Graph operation expected")
      }
      assert_true(physical_equal(@graph.input(operation), input))
      assert_true(
        @graph.pending_validations(operation).contains(ValidateGraphData),
      )
      assert_true(
        @graph.pending_validations(operation).contains(ResolveGraphResources),
      )
      if field == "" {
        assert_true(physical_equal(step.output, input))
      } else {
        assert_eq(@carrier.kind(step.output), @carrier.RelationKind)
        let rows = @carrier.relation_rows(step.output).unwrap()
        guard @carrier.lookup(rows, Unqualified(field)) is Present(found) else {
          abort("identity field missing")
        }
        if typed {
          assert_true(
            @contract.type_equal(
              found.contract.unwrap(),
              @contract.decimal_contract(38, 9, nullable~).unwrap(),
              10,
            ),
          )
          let downstream = @pipeline_typing.check_carriers(
            cursor("[{" + body + "},{\"select\":[\"" + field + "\"]}]"),
            [("g", input)],
            None,
            None,
            limits(),
          ).unwrap()
          assert_eq(
            @schema.field_count(
              @pipeline_typing.output_schema(downstream).unwrap(),
            ),
            1,
          )
        } else {
          assert_true(found.contract is None)
          assert_true(@pipeline_typing.output_schema(p) is None)
          assert_true(
            @pipeline_typing.check_carriers(
              cursor("[{" + body + "},{\"select\":[\"" + field + "\"]}]"),
              [("g", input)],
              None,
              None,
              limits(),
            )
            is Err({ kind: IncompleteSchema, .. }),
          )
        }
      }
      let u = @pipeline_typing.usage(p)
      let exact = {
        ..limits(),
        max_work: u.work,
        max_nodes: u.nodes,
        max_text_bytes: u.text_bytes,
        max_tokens: u.tokens,
      }
      assert_true(
        @pipeline_typing.check_carriers(
          source,
          [("g", input)],
          None,
          None,
          exact,
        )
        is Ok(_),
      )
      for
        cap in [
          { ..exact, max_work: u.work - 1, },
          { ..exact, max_nodes: u.nodes - 1, },
          { ..exact, max_text_bytes: u.text_bytes - 1, },
        ] {
        assert_true(
          @pipeline_typing.check_carriers(
            source,
            [("g", input)],
            None,
            None,
            cap,
          )
          is Err(_),
        )
      }
    }
  }
}
