///|
fn adopt_layout_selection(
  input : LayoutRelation,
  id : String,
  indices : Array[Int],
  physical : LayoutAllocation,
) -> Result[LayoutRelation, RowIssue] {
  if !reserve_slots(physical.slots, input.names.length()) ||
    !spend_control(physical.work, input.names.length()) {
    return Err(RowLimit)
  }
  match select_layout_rows(input.storage, indices, physical) {
    Ok(storage) => Ok({ ..input, id, names: input.names.copy(), storage, })
    Err(Limit) => Err(RowLimit)
    Err(Shape) => Err(InvalidRows)
  }
}

///|
// Experimental storage adapter to the production dispatcher, not another
// implementation of prefix selection, ownership, or authored operation order.
fn evaluate_layout_kernel(
  kernel : @lower.PreparedKernel,
  input : LayoutRelation,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  physical : LayoutAllocation,
  logical : LogicalBudget?,
) -> Result[LayoutRelation, RowIssue] {
  evaluate_rows_dispatch(
    kernel,
    input,
    {
      release: fn(table) { release_layout_columns(table.storage) },
      sort: fn(kernel, input, id) {
        match
          evaluate_sort_selection(
            kernel, input, max_rows, control, output, workspace,
          ) {
          Ok(indices) => adopt_layout_selection(input, id, indices, physical)
          Err(issue) => Err(issue)
        }
      },
      dedupe: fn(kernel, input, id) {
        match
          evaluate_dedupe_selection(
            kernel, input, max_rows, control, output, workspace,
          ) {
          Ok(indices) => adopt_layout_selection(input, id, indices, physical)
          Err(issue) => Err(issue)
        }
      },
      distinct: fn(input, id) {
        match
          evaluate_distinct_selection(
            input, max_rows, control, output, workspace,
          ) {
          Ok(indices) => adopt_layout_selection(input, id, indices, physical)
          Err(issue) => Err(issue)
        }
      },
      take: fn(input, id, count, offset) {
        match
          evaluate_take_selection(
            input, count, offset, max_rows, control, output, workspace,
          ) {
          Ok((start, count)) => {
            if !reserve_slots(physical.slots, count) ||
              !spend_control(physical.work, count) {
              return Err(RowLimit)
            }
            adopt_layout_selection(
              input,
              id,
              Array::makei(count, i => start + i),
              physical,
            )
          }
          Err(issue) => Err(issue)
        }
      },
      top_k: fn(kernel, input, id, count) {
        match
          evaluate_top_k_selection(
            kernel, input, count, max_rows, control, output, workspace,
          ) {
          Ok(indices) => adopt_layout_selection(input, id, indices, physical)
          Err(issue) => Err(issue)
        }
      },
      // Row expansion materializes a row table in the production completed
      // backend; this experimental layout adapter has no expansion writer.
      unnest: fn(_kernel, _input, _id) { Err(InvalidRows) },
      unpivot: fn(_kernel, _input, _id) { Err(InvalidRows) },
      pivot: fn(_kernel, _input, _id) { Err(InvalidRows) },
      lag: fn(_kernel, _input, _id) { Err(InvalidRows) },
      watermark: fn(_kernel, _input, _id) { Err(InvalidRows) },
      body: fn(body, input, id, logical) {
        evaluate_layout_body(
          kernel,
          input,
          control,
          output,
          workspace,
          physical,
          logical,
          source=Some(body),
          output_id_override=Some(id),
          maximum_rows=Some(max_rows),
        )
      },
    },
    ordered_budget=logical,
  )
}

///|
test "layout dispatcher preserves inherited total order through projection and take" {
  let owner = sort_seed(
    ",{\"sort\":[{\"id\":\"asc\"}]},{\"select\":[\"k\",\"payload\"]},{\"sort\":[{\"k\":\"asc\"}]},{\"take\":1}",
  )
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let mut input = layout_relation(
      capture_values(owner, 0, max_rows=3, run_limits().input_values).unwrap(),
      candidate,
    )
    let control = { remaining: 100000, max_frames: 100, }
    let output = row_output()
    let physical = layout_allocation(100000, 100000, 100000)
    for i = 1; i < 5; i = i + 1 {
      input = evaluate_layout_kernel(
        row_kernel(owner, i),
        input,
        3,
        control,
        output,
        { limit: 100000, live: 0, peak: 0, },
        physical,
        None,
      ).unwrap()
    }
    assert_eq(input.id, "limit_4")
    assert_eq(input.storage.count, 1)
    guard layout_cell(input.storage, 0, 1)
      is Some(Captured(@admitted.Array(payload))) else {
      fail("payload")
    }
    assert_true(@admitted.element_at(payload, 0) is Some(@admitted.Number(10)))
  }
}

///|
test "every scoped row operation composes through one layout sequence loop" {
  let owner = row_owner(
    ",{\"derive\":{\"c\":\"a + 1\"}},{\"filter\":\"c > 0\"},{\"rename\":{\"a\":\"n\"}},{\"drop\":[\"c\"]},{\"sort\":[{\"n\":\"asc\"}]},{\"distinct\":[\"n\",\"b\"]},{\"dedupe_rows\":{\"by\":[],\"order_by\":[{\"n\":\"desc\"}]}},{\"take\":1}",
  )
  let sequence = prepared_sequence(owner)
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let control = { remaining: 100000, max_frames: 100, }
    let wiring = prepare_wiring(owner, ["limit_8"], control, {
      limit: 10000,
      live: 0,
      peak: 0,
    }).unwrap()
    let store = table_store(wiring, { limit: 10000, live: 0, peak: 0, }).unwrap()
    let output = row_output()
    let physical = layout_allocation(100000, 100000, 100000)
    run_sequence_steps(
      sequence,
      store,
      control,
      fn(i) {
        Ok(
          layout_relation(
            capture_values(owner, i, max_rows=2, run_limits().input_values).unwrap(),
            candidate,
          ),
        )
      },
      fn(i, kernel, input) {
        match
          evaluate_layout_kernel(
            kernel,
            input,
            2,
            control,
            output,
            { limit: 100000, live: 0, peak: 0, },
            physical,
            None,
          ) {
          Ok(value) => Ok(value)
          Err(issue) => Err(Rows(i, issue))
        }
      },
    ).unwrap()
    let result = store.tables[8].unwrap().table
    assert_eq(result.names, ["n", "b"])
    assert_eq(result.storage.count, 1)
    assert_true(layout_cell(result.storage, 0, 0) is Some(Number(1)))
    assert_true(layout_cell(result.storage, 0, 1) is Some(Number(0)))
    assert_eq(store.next, 9)
    for i = 0; i < 8; i = i + 1 {
      assert_true(store.tables[i] is None)
    }
  }
}
