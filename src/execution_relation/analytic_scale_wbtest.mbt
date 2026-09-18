///|
fn analytic_scale_sample(count : Int, aggregate : Bool) -> (Int, Int) raise {
  let functions = if aggregate {
    "{\"n\":{\"fn\":\"count\",\"field\":\"amount\"}}"
  } else {
    "{\"position\":{\"fn\":\"row_number\"}," +
    "\"previous\":{\"fn\":\"lag\",\"expr\":\"amount\"}}"
  }
  let body = "\"analytic\":{\"partition_by\":[\"group\"]," +
    "\"order_by\":[{\"id\":\"asc\"}]," +
    (if aggregate {
      "\"frame\":{\"start\":\"unbounded_preceding\"," +
      "\"end\":\"current_row\"},"
    } else {
      ""
    }) +
    "\"functions\":" +
    functions +
    "}"
  let owner = analytic_execution_owner(body)
  let template = analytic_execution_input(owner)
  let input : Table = {
    ..template,
    rows: Array::makei(count, index => {
      template.names.map(name => {
        match name {
          "amount" | "id" => Number(index.to_double())
          "group" => Text("g")
          _ => abort("unexpected analytic scale field")
        }
      })
    }),
  }
  let maximum = 100000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace = { limit: count * 100 + 1000, live: 0, peak: 0, }
  let result = evaluate_rows_with_workspace(
    row_kernel(owner, 0),
    input,
    count,
    control,
    value_budget({
      max_nodes: maximum,
      max_text_bytes: maximum,
      max_depth: 100,
      max_work: maximum,
    }).unwrap(),
    workspace,
  )
  let table = match result {
    Ok(value) => value
    Err(RowLimit) => abort("analytic scale row limit")
    Err(InvalidRows) => abort("analytic scale invalid rows")
    Err(Comparison(_)) => abort("analytic scale comparison")
    Err(Evaluation(_, _, _)) => abort("analytic scale evaluation")
    Err(MissingOrderedResourceContext) => abort("analytic scale order")
    Err(_) => abort("analytic scale other failure")
  }
  assert_eq(table.rows.length(), count)
  (maximum - control.remaining, workspace.peak)
}

///|
test "analytic ranking navigation and count retain indexed scaling" {
  for count in [128, 512, 2048] {
    let mut levels = 0
    let mut width = 1
    while width < count {
      width *= 2
      levels += 1
    }
    for aggregate in [false, true] {
      let (work, peak) = analytic_scale_sample(count, aggregate)
      assert_true(work < count * (levels * 30 + 300))
      assert_true(peak < count * 100 + 1000)
    }
  }
}
