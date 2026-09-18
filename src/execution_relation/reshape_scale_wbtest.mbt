///|
fn reshape_scale_budget(maximum : Int) -> ValueBudget {
  value_budget({
    max_nodes: maximum,
    max_text_bytes: maximum,
    max_depth: 10,
    max_work: maximum,
  }).unwrap()
}

///|
fn reshape_scale_levels(count : Int) -> Int {
  let mut size = 1
  let mut levels = 0
  while size < count {
    size *= 2
    levels += 1
  }
  levels
}

///|
fn unnest_scale_sample(count : Int) -> (Int, Int) raise {
  let owner = unnest_sequence_owner(
    "{\"column\":\"items\",\"as\":\"item\",\"with_index\":\"position\"}",
  )
  let template = table_from_capture(
    capture_input(
      owner,
      0,
      [input_cursor("{\"id\":0,\"items\":[1,2]}")],
      max_rows=1,
      run_limits().input_values,
    ).unwrap(),
  )
  let items = template.rows[0][1]
  let input = {
    ..template,
    rows: Array::makei(count, index => [Number(index.to_double()), items]),
  }
  let maximum = 100000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace : RowWorkspace = { limit: maximum, live: 0, peak: 0, }
  let result = evaluate_unnest_rows(
    row_kernel(owner, 0),
    input,
    "unnested",
    count * 2,
    control,
    reshape_scale_budget(maximum),
    workspace,
  ).unwrap()
  assert_eq(result.rows.length(), count * 2)
  assert_true(result.rows[0][0] is Number(0))
  assert_true(result.rows[0][1] is Number(1))
  assert_true(result.rows[1][1] is Number(2))
  assert_true(result.rows[1][3] is Number(1))
  (maximum - control.remaining, workspace.peak)
}

///|
fn unpivot_scale_sample(count : Int) -> (Int, Int) raise {
  let owner = unpivot_sequence_owner()
  let input : Table = {
    owner,
    id: "source",
    names: ["id", "jan", "feb"],
    rows: Array::makei(count, index => {
      [
        Number(index.to_double()),
        Number((index * 2).to_double()),
        if index % 2 == 0 {
          Null
        } else {
          Number(index.to_double())
        },
      ]
    }),
  }
  let maximum = 100000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace : RowWorkspace = { limit: maximum, live: 0, peak: 0, }
  let result = evaluate_unpivot_rows(
    row_kernel(owner, 0),
    input,
    "unpivoted",
    count * 3,
    control,
    reshape_scale_budget(maximum),
    workspace,
  ).unwrap()
  assert_eq(result.rows.length(), count * 3)
  assert_true(result.rows[0][3] is Text("jan"))
  assert_true(result.rows[1][3] is Text("feb"))
  assert_true(result.rows[2][3] is Text("jan"))
  (maximum - control.remaining, workspace.peak)
}

///|
fn pivot_scale_sample(count : Int) -> (Int, Int) raise {
  let owner = pivot_sequence_owner(
    "{\"index\":[\"id\"],\"column\":\"status\",\"values\":[\"open\",\"won\"],\"value\":\"amount\",\"aggregate\":\"count\"}",
  )
  let input : Table = {
    owner,
    id: "source",
    names: ["id", "status", "amount"],
    rows: Array::makei(count, index => {
      [
        Number((index / 4).to_double()),
        Text(if index % 2 == 0 { "open" } else { "won" }),
        Number(index.to_double()),
      ]
    }),
  }
  let maximum = 100000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace : RowWorkspace = { limit: maximum, live: 0, peak: 0, }
  let result = evaluate_pivot_rows(
    row_kernel(owner, 0),
    input,
    "pivoted",
    count,
    control,
    reshape_scale_budget(maximum),
    workspace,
  ).unwrap()
  let groups = (count + 3) / 4
  assert_eq(result.rows.length(), groups)
  assert_true(result.rows[0][0] is Number(0))
  assert_true(result.rows[0][1] is Number(2))
  assert_true(result.rows[0][2] is Number(2))
  (maximum - control.remaining, workspace.peak)
}

///|
test "reshape kernels stay within their declared scaling floors" {
  for count in [128, 1024, 8192] {
    let unnest = unnest_scale_sample(count)
    assert_true(unnest.0 <= count * 4 + 100)
    assert_true(unnest.1 <= count * 12 + 100)

    let unpivot = unpivot_scale_sample(count)
    assert_true(unpivot.0 <= count * 5 + 100)
    assert_true(unpivot.1 <= count * 17 + 100)

    let pivot = pivot_scale_sample(count)
    let levels = reshape_scale_levels(count)
    assert_true(pivot.0 <= count * (levels * 3 + 10) + 500)
    assert_true(pivot.1 <= count * 4 + 500)
  }
}
