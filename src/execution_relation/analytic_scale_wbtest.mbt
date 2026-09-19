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

///|
fn analytic_numeric_scale_sample(
  count : Int,
  frame : String,
  workspace_limit : Int,
  expression? : Bool = false,
) -> (Result[Unit, RowIssue], Int, Int, Int) raise {
  let argument = if expression {
    "\"expr\":\"amount + 1\""
  } else {
    "\"field\":\"amount\""
  }
  let owner = analytic_execution_owner(
    "\"analytic\":{\"partition_by\":[\"group\"]," +
    "\"order_by\":[{\"id\":\"asc\"}]," +
    "\"frame\":" +
    frame +
    ",\"functions\":{" +
    "\"mean\":{\"fn\":\"avg\"," +
    argument +
    "}," +
    "\"total\":{\"fn\":\"sum\"," +
    argument +
    "}}}",
  )
  let template = analytic_execution_input(owner)
  let input : Table = {
    ..template,
    rows: Array::makei(count, index => {
      template.names.map(name => {
        match name {
          "amount" | "id" => Number(index.to_double())
          "group" => Text("g")
          _ => abort("unexpected numeric analytic scale field")
        }
      })
    }),
  }
  let profile = @numeric.builtin_profile()
  let reduction = @numeric.select(
    profile,
    @numeric.member_cid_at(profile, 0).unwrap(),
  ).unwrap()
  let mut memberships = 0
  let numeric = numeric_aggregate_execution((
    _step,
    name,
    _occurrence,
    contributors,
    expected_count,
    max_work,
  ) => {
    memberships += contributors.length()
    Some(
      @numeric.execute(
        reduction,
        if name == "mean" {
          @numeric.Average
        } else {
          @numeric.Sum
        },
        contributors,
        expected_count,
        max_work,
      ),
    )
  })
  let maximum = 100000000
  let control = { remaining: maximum, max_frames: 100, }
  let workspace = { limit: workspace_limit, live: 0, peak: 0, }
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
    numeric=Some(numeric),
  )
  let outcome = match result {
    Ok(table) => {
      assert_eq(table.rows.length(), count)
      Ok(())
    }
    Err(issue) => Err(issue)
  }
  (outcome, maximum - control.remaining, workspace.peak, memberships)
}

///|
test "analytic numeric frame classes retain bounded scaling" {
  for count in [128, 512, 2048] {
    let mut levels = 0
    let mut width = 1
    while width < count {
      width *= 2
      levels += 1
    }
    let frames = [
      ("one-row", "{\"start\":\"current_row\",\"end\":\"current_row\"}", count),
      (
        "cumulative",
        "{\"start\":\"unbounded_preceding\"," + "\"end\":\"current_row\"}",
        count * (count + 1) / 2,
      ),
      (
        "fixed-width",
        "{\"start\":{\"preceding\":2}," + "\"end\":\"current_row\"}",
        count * 3 - 3,
      ),
      (
        "full-partition",
        "{\"start\":\"unbounded_preceding\"," +
        "\"end\":\"unbounded_following\"}",
        count * count,
      ),
      (
        "empty",
        "{\"start\":{\"following\":" +
        count.to_string() +
        "}," +
        "\"end\":{\"following\":" +
        (count + 1).to_string() +
        "}}",
        0,
      ),
    ]
    for (_name, frame, membership_per_call) in frames {
      let (outcome, work, peak, memberships) = analytic_numeric_scale_sample(
        count,
        frame,
        count * 100 + 1000,
      )
      assert_true(outcome is Ok(_))
      let calls = 2
      let b = membership_per_call * calls
      let e = if membership_per_call == 0 { 0 } else { count * calls }
      let r = count
      // Sorting is O(N log N). Frame traversal and numeric reduction are
      // O(B), demanded input evaluation is O(E), and output is O(R).
      let bound = count * levels * 40 + b * 20 + e * 100 + r * 400 + 1000
      assert_eq(memberships, b)
      assert_true(work < bound)
      // Workspace holds O(N * calls) indexes and evaluated inputs. Frame
      // members are temporary, so peak storage depends on the widest frame,
      // not the total membership count B.
      assert_true(peak < count * (calls * 20 + 80) + 1000)
    }
  }
}

///|
test "analytic numeric temporary arrays respect the exact workspace boundary" {
  let count = 32
  let frame = "{\"start\":\"unbounded_preceding\"," + "\"end\":\"current_row\"}"
  let (generous, _, peak, _) = analytic_numeric_scale_sample(
    count,
    frame,
    count * 100 + 1000,
  )
  assert_true(generous is Ok(_))
  let (exact, _, exact_peak, _) = analytic_numeric_scale_sample(
    count, frame, peak,
  )
  assert_true(exact is Ok(_))
  assert_eq(exact_peak, peak)
  let (short, _, short_peak, _) = analytic_numeric_scale_sample(
    count,
    frame,
    peak - 1,
  )
  assert_true(short is Err(RowLimit))
  assert_true(short_peak <= peak - 1)
}

///|
test "analytic evaluates overlapping frame expressions once per source and call" {
  let frame = "{\"start\":\"unbounded_preceding\"," +
    "\"end\":\"unbounded_following\"}"
  for count in [128, 512, 2048] {
    let (field, field_work, _, field_memberships) = analytic_numeric_scale_sample(
      count,
      frame,
      count * 100 + 1000,
    )
    let (expression, expression_work, _, expression_memberships) = analytic_numeric_scale_sample(
      count,
      frame,
      count * 100 + 1000,
      expression=true,
    )
    assert_true(field is Ok(_))
    assert_true(expression is Ok(_))
    assert_eq(expression_memberships, field_memberships)
    // Both calls demand each source exactly once. Expression overhead is
    // therefore O(E) with E = N * calls, not O(B) for N-wide frames.
    assert_true(expression_work - field_work < count * 80)
  }
}
