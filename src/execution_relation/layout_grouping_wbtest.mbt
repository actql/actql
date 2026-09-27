///|
test "all layouts share distinct and dedupe indices budgets and occurrence order" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":false},\"b\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"a\":2,\"b\":0},{\"a\":1,\"b\":1},{\"a\":2,\"b\":2},{\"a\":1,\"b\":3}]},\"as\":\"seed\"}]",
  )
  let captured = capture_values(owner, 0, max_rows=4, run_limits().input_values).unwrap()
  let by = [{ column: 0, descending: false, nulls_first: false, }]
  let order = [{ column: 1, descending: true, nulls_first: false, }]
  let mut baseline : (Int, Int, Int, Int)? = None
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let input = layout_relation(captured, candidate).storage
    let dc = { remaining: 100000, max_frames: 0, }
    let dw = { limit: 10000, live: 5, peak: 5, }
    assert_eq(distinct_indices(input, [0], dc, dw).unwrap(), [0, 1])
    assert_eq(dw.live, 7)
    let gc = { remaining: 100000, max_frames: 0, }
    let gw = { limit: 10000, live: 5, peak: 5, }
    // Typed numeric key 1 precedes key 2, regardless of their CIDs.
    assert_eq(dedupe_indices(input, by, order, gc, gw).unwrap(), [3, 2])
    assert_eq(gw.live, 7)
    let counters = (dc.remaining, dw.peak, gc.remaining, gw.peak)
    match baseline {
      None => baseline = Some(counters)
      Some(expected) => assert_eq(counters, expected)
    }
    for
      (work, slots, good) in [
        (100000 - gc.remaining, gw.peak, true),
        (99999 - gc.remaining, gw.peak, false),
        (100000 - gc.remaining, gw.peak - 1, false),
      ] {
      let workspace = { limit: slots, live: 5, peak: 5, }
      let result = dedupe_indices(
        input,
        by,
        order,
        { remaining: work, max_frames: 0, },
        workspace,
      )
      if good {
        assert_eq(result.unwrap(), [3, 2])
        assert_eq(workspace.live, 7)
      } else {
        assert_true(result is Err(Ordering(Limit)))
        assert_eq(workspace.live, 5)
      }
    }
    let failed = { limit: 10000, live: 5, peak: 5, }
    assert_true(
      dedupe_indices(
        input,
        by,
        by,
        { remaining: 100000, max_frames: 0, },
        failed,
      )
      is Err(TopTie(1, 3)),
    )
    assert_eq(failed.live, 5)
    let reversed = select_layout_rows(
      input,
      [3, 2, 1, 0],
      layout_allocation(10000, 10000, 10000),
    ).unwrap()
    assert_eq(
      distinct_indices(reversed, [0], { remaining: 100000, max_frames: 0, }, {
        limit: 10000,
        live: 0,
        peak: 0,
      }).unwrap(),
      [0, 1],
    )
    assert_eq(
      dedupe_indices(
        reversed,
        by,
        order,
        { remaining: 100000, max_frames: 0, },
        { limit: 10000, live: 0, peak: 0, },
      ).unwrap(),
      [0, 1],
    )
    assert_true(layout_cell(input, 0, 0) is Some(Number(2)))
  }
}
