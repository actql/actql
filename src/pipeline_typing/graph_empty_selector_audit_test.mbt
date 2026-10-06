///|
// The exact zero bound comes from empty VALUES -> constructor -> MATCH,
// not from an invented JSON VALUES row or an unsupported zero TAKE.
fn empty_identity_selector_prefix() -> String {
  "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"nodes\"},{\"graph\":{\"version\":\"actql-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"nodes\",\"key\":[\"id\"]}],\"edges\":[]},\"as\":\"emptyGraph\"},{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]},\"as\":\"empty\"},"
}

///|
test "empty typed identity selector Relations retain node and path custody and exact zero bounds" {
  let graph = query_graph()
  for direction in ["in", "out", "both"] {
    for emit in ["nodes", "paths"] {
      let source = cursor(
        empty_identity_selector_prefix() +
        "{\"from\":\"g\",\"traverse\":{\"start\":{\"from\":\"empty\",\"id\":\"element\"},\"direction\":\"" +
        direction +
        "\",\"min_hops\":0,\"max_hops\":2,\"path_mode\":\"trail\",\"emit\":\"" +
        emit +
        "\"}},{\"select\":[\"start_id\"]}]",
      )
      let p = @pipeline_typing.check_carriers(
        source,
        [("g", graph)],
        None,
        None,
        limits(),
      ).unwrap()
      let step = @pipeline_typing.step_at(p, 3).unwrap()
      let edges = @pipeline_typing.input_occurrences(step)
      assert_eq(edges.length(), 2)
      assert_eq(edges[0].target, Input(0))
      assert_eq(edges[1].target, Step(2))
      guard step.operation is Traverse(selector=Some(Step(2)), checked~) else {
        fail("current checked TRAIL and selector")
      }
      assert_true(physical_equal(@graph.traverse_input(checked), graph))
      let selector_schema = @pipeline_typing.schema_at(p, Step(2)).unwrap()
      let identity = @schema.field_contract(
        @schema.field_at(selector_schema, 0).unwrap(),
      )
      assert_false(identity.nullable)
      assert_true(identity.shape is @contract.Json)
      assert_true(
        @graph.selector_form(@graph.traverse_start(checked))
        is RelationIds(from="empty", ..),
      )
      assert_eq(
        @schema.field_count(@pipeline_typing.output_schema(p).unwrap()),
        1,
      )
      assert_count(p, 2, 0L, true)
      assert_count(p, 3, 0L, true)
      assert_count(p, 4, 0L, true)
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

///|
test "empty selectors do not enable unsupported shortest-path consumers" {
  for direction in ["in", "out", "both"] {
    for selection in ["each_pair", "nearest_per_source", "nearest_pair"] {
      let issue = @pipeline_typing.check_carriers(
        cursor(
          empty_identity_selector_prefix() +
          "{\"shortest_path\":{\"source\":{\"from\":\"empty\",\"id\":\"element\"},\"target\":{\"from\":\"empty\",\"id\":\"element\"},\"direction\":\"" +
          direction +
          "\",\"max_hops\":2,\"selection\":\"" +
          selection +
          "\"},\"from\":\"g\"}]",
        ),
        [("g", query_graph())],
        None,
        None,
        limits(),
      ).unwrap_err()
      assert_eq(issue.kind, Graph(@graph.UnsupportedGraphOperation))
      assert_eq(issue.path, [Index(3), Key("shortest_path")])
    }
  }
}
