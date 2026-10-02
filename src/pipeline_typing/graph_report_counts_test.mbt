///|
test "unsupported bounds reports remain refused for empty and populated current Graph declarations" {
  for n in [0, 3] {
    for
      body in [
        "{\"max_nodes\":0,\"max_edges\":0,\"max_degree\":0}", "{\"max_nodes\":0,\"max_edges\":0}",
        "{\"max_degree\":0}", "{\"max_nodes\":6,\"max_edges\":3,\"max_degree\":6}",
        "{\"max_degree\":5}",
      ] {
      let issue = @pipeline_typing.check_carriers(
        cursor(
          "[" +
          keyed_graph_count_prefix(n, n) +
          ",{\"graph_bounds\":" +
          body +
          "},{\"select\":[\"kind\"]}]",
        ),
        [],
        None,
        None,
        limits(),
      ).unwrap_err()
      assert_eq(issue.kind, Graph(@graph.UnsupportedGraphOperation))
      assert_eq(issue.path, [Index(3), Key("graph_bounds")])
    }
  }
}

///|
test "current TRAIL retains empty-selector bounds without treating a row guard as a path-count proof" {
  for n in [0, 3] {
    for selected in [0, 2] {
      for patterned in [false, true] {
        let mode = if patterned {
          "\"hops\":[{\"direction\":\"both\"}]"
        } else {
          "\"direction\":\"both\",\"min_hops\":0,\"max_hops\":3"
        }
        let take = if selected == 0 {
          "{\"count\":1,\"offset\":" + n.to_string() + "}"
        } else {
          "{\"count\":2}"
        }
        let source = cursor(
          "[" +
          keyed_graph_count_prefix(n, n) +
          ",{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}},{\"take\":" +
          take +
          ",\"as\":\"selected\"},{\"traverse\":{\"start\":{\"from\":\"selected\",\"id\":\"element\"}," +
          mode +
          ",\"path_mode\":\"trail\",\"emit\":\"paths\",\"max_output_rows\":1},\"from\":\"g\"}]",
        )
        let p = graph_count_checked(
          @pipeline_typing.check_carriers(source, [], None, None, limits()),
        )
        if n == 0 || selected == 0 {
          assert_count(p, 4, 0L, true)
          assert_count(p, 5, 0L, true)
        } else {
          assert_count(p, 4, 2L, false)
          assert_true(@pipeline_typing.row_count(p, Step(5)) is None)
        }
        guard @pipeline_typing.step_at(p, 5).unwrap().operation
          is Traverse(selector=Some(Step(4)), checked~) else {
          fail("current TRAIL selector")
        }
        assert_true(
          @graph.traverse_pending(checked).contains(EnforceTraversalOutputGuard),
        )
        assert_true(
          @graph.traverse_pending(checked).contains(ResolveTraversalResources),
        )
        let u = @pipeline_typing.usage(p)
        let exact = {
          ..limits(),
          max_work: u.work,
          max_nodes: u.nodes,
          max_text_bytes: u.text_bytes,
          max_tokens: u.tokens,
        }
        assert_true(
          @pipeline_typing.check_carriers(source, [], None, None, exact)
          is Ok(_),
        )
        assert_true(
          @pipeline_typing.check_carriers(source, [], None, None, {
            ..exact,
            max_work: u.work - 1,
          })
          is Err(_),
        )
      }
    }
  }
}
