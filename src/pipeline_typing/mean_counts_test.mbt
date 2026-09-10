///|
test "graph mean excludes zero-weight contributions but keeps repeated positive samples" {
  let prefix = graph_count_seed(3) +
    ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"}"
  let base = graph_count_checked(
    @pipeline_typing.check_carriers(
      cursor("[" + prefix + "]"),
      [],
      None,
      None,
      limits(),
    ),
  )
  // Supplying only a Carrier intentionally does not import its earlier counts.
  let inputs = [("external", @pipeline_typing.output_carrier(base).unwrap())]
  for weight in [0, 1] {
    let source = cursor(
      "[" +
      prefix +
      ",{\"mean_graphs\":{\"with\":[\"g\",\"g\",\"external\"],\"weights\":[1,2," +
      weight.to_string() +
      "],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":{}}},\"as\":\"mean\"},{\"graph_diff\":{\"with\":\"g\"}}]",
    )
    let p = graph_count_checked(
      @pipeline_typing.check_carriers(source, inputs, None, None, limits()),
    )
    let bounds = @pipeline_typing.graph_count(p, Step(2)).unwrap()
    if weight == 0 {
      assert_eq(bounds.nodes.unwrap().upper, 12L)
      assert_eq(bounds.edges.unwrap().upper, 6L)
      assert_true(!bounds.nodes.unwrap().exact && !bounds.edges.unwrap().exact)
    } else {
      assert_true(bounds.nodes is None && bounds.edges is None)
    }
    assert_count(p, 3, 1L, true)
    let u = @pipeline_typing.usage(p)
    let cap = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, cap) is Ok(_),
    )
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, {
        ..cap,
        max_work: cap.max_work - 1,
      })
      is Err(_),
    )
  }
}

///|
test "mean of empty constructed graphs has exact zero extents" {
  let p = graph_count_checked(
    @pipeline_typing.check_carriers(
      cursor(
        "[" +
        graph_count_seed(0) +
        ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{\"mean_graphs\":{\"with\":[\"g\",\"g\"],\"weights\":[1,1],\"support\":{\"nodes\":0.5,\"edges\":0.5},\"properties\":{\"nodes\":{},\"edges\":{}}},\"as\":\"mean\"},{\"node_rows\":true}]",
      ),
      [],
      None,
      None,
      limits(),
    ),
  )
  let bounds = @pipeline_typing.graph_count(p, Step(2)).unwrap()
  assert_eq(bounds.nodes.unwrap().upper, 0L)
  assert_true(bounds.nodes.unwrap().exact && bounds.edges.unwrap().exact)
  assert_count(p, 3, 0L, true)
}
