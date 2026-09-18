///|
fn check_watermark_scale(count : Int) -> Unit raise {
  let owner = watermark_owner(
    "{\"type\":\"number\",\"nullable\":false}", "[{\"id\":0,\"time\":0}]", "\"max_skew\":10",
    "mark",
  )
  let input : Table = {
    owner,
    id: "values_0",
    names: ["id", "time"],
    rows: Array::makei(count, index => {
      [Number(index.to_double()), Number(index.to_double())]
    }),
  }
  let allowance = count * 20 + 1000
  let control = { remaining: allowance, max_frames: 100, }
  let workspace = { limit: count * 7 + 100, live: 0, peak: 0, }
  let result = match
    evaluate_watermark_rows(
      row_kernel(owner, 1),
      input,
      "watermarked",
      count,
      control,
      value_budget({
        max_nodes: count * 20 + 100,
        max_text_bytes: count * 100 + 100,
        max_depth: 10,
        max_work: count * 100 + 100,
      }).unwrap(),
      workspace,
    ) {
    Ok(value) => value
    Err(_) => fail("watermark scale")
  }
  assert_eq(result.rows.length(), count)
  assert_true(
    result.rows[count - 1][2] is Number(value) &&
    value == (count - 11).to_double(),
  )
  let used = allowance - control.remaining
  assert_true(used <= count * 10 + 100)
  assert_true(workspace.peak <= count * 6 + 10)
}

///|
test "watermark uses one prefix scan and linear retained storage" {
  for count in [128, 1024, 8192] {
    check_watermark_scale(count)
  }
}
