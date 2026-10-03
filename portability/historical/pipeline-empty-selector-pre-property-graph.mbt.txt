///|
test "empty typed selector Relations remain valid operands for traversal and shortest paths" {
  let graph = mean_audit_graph(@contract.primitive(NumberType, nullable=false))
  for direction in ["in", "out", "both"] {
    let operations = []
    for emit in ["nodes", "paths"] {
      operations.push(
        (
          "\"traverse\":{\"start\":{\"from\":\"empty\",\"id\":\"id\"},\"direction\":\"" +
          direction +
          "\",\"min_hops\":0,\"max_hops\":2,\"emit\":\"" +
          emit +
          "\"}",
          2,
          "start_id",
        ),
      )
    }
    for selection in ["each_pair", "nearest_per_source", "nearest_pair"] {
      operations.push(
        (
          "\"shortest_path\":{\"source\":{\"from\":\"empty\",\"id\":\"id\"},\"target\":{\"from\":\"empty\",\"id\":\"id\"},\"direction\":\"" +
          direction +
          "\",\"max_hops\":2,\"selection\":\"" +
          selection +
          "\"}",
          3,
          "source_id",
        ),
      )
    }
    for (operation, edge_count, field) in operations {
      let source = cursor(
        "[" +
        count_values(0, "empty") +
        ",{\"from\":\"g\"," +
        operation +
        "},{\"select\":[\"" +
        field +
        "\"]}]",
      )
      let p = @pipeline_typing.check_carriers(
        source,
        [("g", graph)],
        None,
        None,
        limits(),
      ).unwrap()
      let step = @pipeline_typing.step_at(p, 1).unwrap()
      let edges = @pipeline_typing.input_occurrences(step)
      assert_eq(edges.length(), edge_count)
      assert_eq(edges[0].target, Input(0))
      for i in 1..<edges.length() {
        assert_eq(edges[i].target, Step(0))
      }
      if edge_count == 3 {
        assert_eq(edges[1].role, Left)
        assert_eq(edges[2].role, Right)
      }
      assert_eq(
        @schema.field_count(@pipeline_typing.output_schema(p).unwrap()),
        1,
      )
      assert_count(p, 1, 0L, true)
      assert_count(p, 2, 0L, true)
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
          [("g", graph)],
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
            [("g", graph)],
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
