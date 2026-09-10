///|
test "window counts retain parameter obligations and reject multiplication overflow" {
  let parameters = @parameter.read_declarations(
    Some(cursor("{\"step\":{\"type\":\"number\",\"default\":2}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for kind in ["fixed", "sliding"] {
    for n in [0, 3] {
      let p = @pipeline_typing.check_carriers(
        cursor(
          "[" +
          count_values(n, "seed") +
          ",{\"row_window\":{\"kind\":\"" +
          kind +
          "\",\"time\":\"id\",\"size\":10,\"step\":{\"$param\":\"step\"}}}]",
        ),
        [],
        Some(parameters),
        None,
        limits(),
      ).unwrap()
      if kind == "fixed" || n == 0 {
        assert_count(p, 1, n.to_int64(), true)
      } else {
        assert_true(@pipeline_typing.row_count(p, Step(1)) is None)
      }
      guard @pipeline_typing.step_at(p, 1).unwrap().operation is Window(w) else {
        abort("window")
      }
      assert_true(
        @window.pending_validations(w).contains(
          BindMilliseconds("step", PositiveMilliseconds),
        ),
      )
    }
  }
  let bad = @pipeline_typing.check_carriers(
    cursor(
      "[" +
      count_values(3, "seed") +
      ",{\"row_window\":{\"kind\":\"sliding\",\"time\":\"id\",\"size\":9007199254740991,\"step\":1}}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(bad.kind, RowBoundOverflow)
  assert_eq(bad.path, [@source.Index(1)])
}

///|
test "event labels preserve counts while dropping and dedupe only preserve bounds" {
  for n in [0, 3] {
    for policy in ["mark", "drop"] {
      let p = @pipeline_typing.check_carriers(
        cursor(
          "[" +
          count_values(n, "seed") +
          ",{\"to_events\":{\"id\":\"id\",\"time\":\"id\"}},{\"session\":{\"by\":[],\"gap\":10}},{\"watermark_events\":{\"watermark_ms\":1,\"policy\":\"" +
          policy +
          "\"}},{\"dedupe_events\":{\"by\":[\"id\"],\"order_by\":[{\"id\":\"asc\"}]}},{\"events\":true}]",
        ),
        [],
        None,
        None,
        limits(),
      ).unwrap()
      for i in 0..<3 {
        assert_count(p, i, n.to_int64(), true)
      }
      assert_count(p, 3, n.to_int64(), policy == "mark" || n == 0)
      assert_count(p, 4, n.to_int64(), n == 0)
      assert_count(p, 5, n.to_int64(), n == 0)
    }
  }
}

///|
test "vector bridge normalization score and projection preserve exact counts" {
  let checked = @pipeline_typing.check_carriers(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}},\"rows\":[{\"id\":1,\"embedding\":[1,2]},{\"id\":2,\"embedding\":[3,4]}]},\"as\":\"seed\"},{\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"}},{\"normalize_vectors\":true},{\"score_vectors\":{\"query\":[1,2],\"metric\":\"dot\"}},{\"vectors\":true}]",
    ),
    [],
    None,
    None,
    limits(),
  )
  let p = match checked {
    Ok(p) => p
    Err(e) => fail(@debug.to_string(e.kind) + " at " + @debug.to_string(e.path))
  }
  for i in 0..<5 {
    assert_count(p, i, 2L, true)
  }
}

///|
test "sliding count bound agrees with independent membership enumeration" {
  for size in 1..<8 {
    for stride in 1..<8 {
      // Enumerate the closed-open lattice directly, without ceil/division.
      let mut maximum = 0
      let mut minimum = 100
      for t in 0..<stride {
        let mut memberships = 0
        for lattice in -10..<11 {
          let start = lattice * stride
          if start <= t && t < start + size {
            memberships += 1
          }
        }
        maximum = if memberships > maximum { memberships } else { maximum }
        minimum = if memberships < minimum { memberships } else { minimum }
      }
      for event in [false, true] {
        let window = if event { "window_events" } else { "row_window" }
        let prefix = if event {
          ",{\"to_events\":{\"id\":\"id\",\"time\":\"id\"}}"
        } else {
          ""
        }
        let time = if event { "" } else { ",\"time\":\"id\"" }
        let p = @pipeline_typing.check_carriers(
          cursor(
            "[" +
            count_values(3, "seed") +
            prefix +
            ",{\"" +
            window +
            "\":{\"kind\":\"sliding\",\"size\":" +
            size.to_string() +
            ",\"step\":" +
            stride.to_string() +
            ",\"offset\":-13" +
            time +
            "}}]",
          ),
          [],
          None,
          None,
          limits(),
        ).unwrap()
        assert_count(
          p,
          if event {
            2
          } else {
            1
          },
          (3 * maximum).to_int64(),
          minimum == maximum,
        )
      }
    }
  }
}
