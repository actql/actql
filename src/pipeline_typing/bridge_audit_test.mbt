///|
test "all explicit row bridges reject wrong Carriers at the original operation slot" {
  let typed = [
    @carrier.relation(@carrier.typed_rows(schema())),
    key_projection_graph(),
    event_input(),
    vector_input(),
  ]
  for
    (name, expected) in [
      ("events", @carrier.EventsKind),
      ("vectors", @carrier.VectorsKind),
      ("node_rows", @carrier.GraphKind),
      ("edge_rows", @carrier.GraphKind),
    ] {
    for input in typed {
      let kind = @carrier.kind(input)
      for unknown in [false, true] {
        let carrier = if unknown {
          @carrier.unknown_carrier(kind)
        } else {
          input
        }
        let source = cursor("[{\"" + name + "\":true,\"as\":\"projected\"}]")
        let checked = @pipeline_typing.check_carriers(
          source,
          [("input", carrier)],
          None,
          None,
          limits(),
        )
        if kind != expected {
          let error = checked.unwrap_err()
          assert_eq(error.kind, Projection(@projection.WrongCarrier(kind)))
          assert_eq(error.path, [Index(0), Key(name)])
          assert_eq(error.span, @decode.cursor_span(error.source))
          continue
        }
        if kind == @carrier.GraphKind && (unknown || name == "edge_rows") {
          let error = checked.unwrap_err()
          assert_eq(
            error.kind,
            Projection(
              if unknown {
                @projection.IncompleteGraph
              } else {
                @projection.UnsupportedGraphOperation
              },
            ),
          )
          assert_eq(error.path, [Index(0), Key(name)])
          assert_eq(error.span, @decode.cursor_span(error.source))
          continue
        }
        let p = checked.unwrap()
        let step = @pipeline_typing.step_at(p, 0).unwrap()
        assert_eq(@carrier.kind(step.output), RelationKind)
        assert_eq(@pipeline_typing.lookup(p, "projected"), Some(Step(0)))
        let edges = @pipeline_typing.input_occurrences(step)
        assert_eq(edges.length(), 1)
        assert_eq(edges[0].role, Primary)
        assert_eq(edges[0].target, Input(0))
        assert_true(@pipeline_typing.row_count(p, Step(0)) is None)
        if unknown {
          assert_true(@pipeline_typing.output_schema(p) is None)
        }
        let used = @pipeline_typing.usage(p)
        let exact = {
          ..limits(),
          max_work: used.work,
          max_nodes: used.nodes,
          max_text_bytes: used.text_bytes,
        }
        assert_true(
          @pipeline_typing.check_carriers(
            source,
            [("input", carrier)],
            None,
            None,
            exact,
          )
          is Ok(_),
        )
        for
          cap in [
            { ..exact, max_work: used.work - 1, },
            { ..exact, max_nodes: used.nodes - 1, },
            { ..exact, max_text_bytes: used.text_bytes - 1, },
          ] {
          assert_true(
            @pipeline_typing.check_carriers(
              source,
              [("input", carrier)],
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
}

///|
test "all explicit row bridges require true and do not select an implicit source" {
  for
    (name, carrier) in [
      ("events", event_input()),
      ("vectors", vector_input()),
      ("node_rows", key_projection_graph()),
      ("edge_rows", key_projection_graph()),
    ] {
    for body in ["false", "null", "{}", "[]", "1", "\"true\""] {
      let source = cursor("[{\"" + name + "\":" + body + "}]")
      let error = @pipeline_typing.check_carriers(
        source,
        [("input", carrier)],
        None,
        None,
        limits(),
      ).unwrap_err()
      assert_eq(error.kind, Projection(@projection.InvalidBody))
      assert_eq(error.path, [Index(0), Key(name)])
    }
    let source = cursor("[{\"" + name + "\":true}]")
    for inputs in [[], [("a", carrier), ("b", carrier)]] {
      let error = @pipeline_typing.check_carriers(
        source,
        inputs,
        None,
        None,
        limits(),
      ).unwrap_err()
      assert_eq(error.kind, MissingCurrent)
    }
    let checked = @pipeline_typing.check_carriers(
      cursor("[{\"" + name + "\":true,\"from\":\"b\"}]"),
      [("a", carrier), ("b", carrier)],
      None,
      None,
      limits(),
    )
    if name == "edge_rows" {
      let error = checked.unwrap_err()
      assert_eq(error.kind, Projection(@projection.UnsupportedGraphOperation))
      assert_eq(error.path, [Index(0), Key(name)])
      continue
    }
    let p = checked.unwrap()
    assert_eq(
      @pipeline_typing.input_occurrences(
        @pipeline_typing.step_at(p, 0).unwrap(),
      )[0].target,
      Input(1),
    )
  }
}
