///|
test "shortest selection bounds use distinct endpoint sets and keep empty selectors empty" {
  for n in [0, 2] {
    for mode in ["each_pair", "nearest_per_source", "nearest_pair"] {
      let source = cursor(
        "[" +
        graph_count_seed(3) +
        ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"}," +
        count_values(n, "selected") +
        ",{\"shortest_path\":{\"source\":{\"from\":\"selected\",\"id\":\"id\"},\"target\":{\"ids\":[1,2,2]},\"selection\":\"" +
        mode +
        "\",\"direction\":\"both\",\"max_hops\":3},\"from\":\"g\"}]",
      )
      let p = graph_count_checked(
        @pipeline_typing.check_carriers(source, [], None, None, limits()),
      )
      let upper = if n == 0 {
        0L
      } else if mode == "each_pair" {
        6L
      } else if mode == "nearest_per_source" {
        2L
      } else {
        1L
      }
      assert_count(p, 3, upper, n == 0)
      let u = @pipeline_typing.usage(p)
      let cap = {
        ..limits(),
        max_work: u.work,
        max_nodes: u.nodes,
        max_text_bytes: u.text_bytes,
      }
      assert_true(
        @pipeline_typing.check_carriers(source, [], None, None, cap) is Ok(_),
      )
      assert_true(
        @pipeline_typing.check_carriers(source, [], None, None, {
          ..cap,
          max_work: cap.max_work - 1,
        })
        is Err(_),
      )
    }
  }
}

///|
test "reach and single-pair shortest retain different output bounds" {
  let p = graph_count_checked(
    @pipeline_typing.check_carriers(
      cursor(
        "[" +
        graph_count_seed(3) +
        ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{\"reach\":{\"start\":1,\"direction\":\"out\",\"max_depth\":3}},{\"shortest_path\":{\"source\":1,\"target\":2,\"direction\":\"out\",\"max_hops\":3},\"from\":\"g\"}]",
      ),
      [],
      None,
      None,
      limits(),
    ),
  )
  assert_count(p, 2, 6L, false)
  assert_count(p, 3, 1L, false)
}
