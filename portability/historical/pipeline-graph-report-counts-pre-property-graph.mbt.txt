///|
test "graph diagnostic row bounds count violations rather than execution thresholds" {
  for n in [0, 3] {
    for
      (body, upper) in [
        (
          "{\"max_nodes\":0,\"max_edges\":0,\"max_degree\":0}",
          if n == 0 {
            0L
          } else {
            8L
          },
        ),
        ("{\"max_nodes\":0,\"max_edges\":0}", if n == 0 { 0L } else { 2L }),
        ("{\"max_degree\":0}", (2 * n).to_int64()),
        ("{\"max_nodes\":6,\"max_edges\":3,\"max_degree\":6}", 0L),
        ("{\"max_degree\":5}", (2 * n).to_int64()),
      ] {
      let source = cursor(
        "[" +
        graph_count_seed(n) +
        ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{\"graph_bounds\":" +
        body +
        "},{\"select\":[\"kind\"]}]",
      )
      let p = graph_count_checked(
        @pipeline_typing.check_carriers(source, [], None, None, limits()),
      )
      assert_count(p, 2, upper, upper == 0L)
      assert_count(p, 3, upper, upper == 0L)
      guard @pipeline_typing.step_at(p, 2).unwrap().operation is Graph(op) else {
        abort("graph bounds")
      }
      assert_true(@graph.pending_validations(op).contains(BoundsReportOrder))
      let u = @pipeline_typing.usage(p)
      let exact = {
        ..limits(),
        max_work: u.work,
        max_text_bytes: u.text_bytes,
        max_nodes: u.nodes,
      }
      assert_true(
        @pipeline_typing.check_carriers(source, [], None, None, exact) is Ok(_),
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
  let input = [("g", @carrier.unknown_carrier(GraphKind))]
  let known = @pipeline_typing.check_carriers(
    cursor("[{\"graph_bounds\":{\"max_nodes\":100,\"max_edges\":200}}]"),
    input,
    None,
    None,
    limits(),
  ).unwrap()
  assert_count(known, 0, 2L, false)
  let unknown = @pipeline_typing.check_carriers(
    cursor("[{\"graph_bounds\":{\"max_degree\":0}}]"),
    input,
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.row_count(unknown, Step(0)) is None)
}

///|
test "traversed node bounds retain selector occurrences and do not count paths as nodes" {
  for n in [0, 3] {
    for selected in [0, 2] {
      for emit in ["nodes", "paths"] {
        for patterned in [false, true] {
          let mode = if patterned {
            "\"hops\":[{\"direction\":\"both\"}]"
          } else {
            "\"direction\":\"both\",\"min_hops\":0,\"max_hops\":3"
          }
          let source = cursor(
            "[" +
            graph_count_seed(n) +
            ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"}," +
            count_values(selected, "selected") +
            ",{\"traverse\":{\"start\":{\"from\":\"selected\",\"id\":\"id\"}," +
            mode +
            ",\"emit\":\"" +
            emit +
            "\",\"max_output_rows\":1},\"from\":\"g\"}]",
          )
          let p = graph_count_checked(
            @pipeline_typing.check_carriers(source, [], None, None, limits()),
          )
          if n == 0 || selected == 0 {
            assert_count(p, 3, 0L, true)
          } else if emit == "nodes" {
            assert_count(p, 3, 12L, false)
          } else {
            assert_true(@pipeline_typing.row_count(p, Step(3)) is None)
          }
          guard @pipeline_typing.step_at(p, 3).unwrap().operation
            is Traverse(checked~, ..) else {
            abort("traverse")
          }
          assert_true(
            @graph.traverse_pending(checked).contains(
              EnforceTraversalOutputGuard,
            ),
          )
          assert_true(
            @graph.traverse_pending(checked).contains(ResolveTraversalResources),
          )
        }
      }
    }
  }
  let p = graph_count_checked(
    @pipeline_typing.check_carriers(
      cursor(
        "[" +
        graph_count_seed(3) +
        ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{\"traverse\":{\"start\":{\"ids\":[1,1]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":1,\"emit\":\"nodes\"}}]",
      ),
      [],
      None,
      None,
      limits(),
    ),
  )
  assert_count(p, 2, 12L, false)
}
