///|
test "star name profile scans are bounded before filtering and keep anonymous slots" {
  let query = @query.parse_query(
    "SELECT * EXCEPT (n) FROM t",
    mapping_syntax_limits(),
  ).unwrap()
  let projection = selected_projections(query)[0]
  let columns = [("private", "slot0"), ("n", "slot1")]
  let profiles : Array[ResultColumn] = [
    { label: "private", slot: "slot0", name: None, name_view: None, },
    {
      label: "n",
      slot: "slot1",
      name: Some({ value: "n", quoted: false, }),
      name_view: None,
    },
  ]
  // Two scans of two columns, each consulting two original profiles: eight.
  assert_eq(
    expanded_star_columns(
      projection,
      columns,
      column_profiles=Some(profiles),
      max_work=8,
    ),
    [("private", "slot0")],
  )
  try
    expanded_star_columns(
      projection,
      columns,
      column_profiles=Some(profiles),
      max_work=7,
    )
  catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => ()
    _ => fail("wrong namespace scan refusal")
  } noraise {
    _ => fail("one-short namespace scan must refuse before filtering")
  }
  assert_eq(
    expanded_star_columns(
      projection,
      columns,
      column_profiles=Some([]),
      max_work=0,
    ),
    [("private", "slot0")],
  )
  // When the first column matches, only three consultations are entered.
  let reordered = [columns[1], columns[0]]
  assert_eq(
    expanded_star_columns(
      projection,
      reordered,
      column_profiles=Some(profiles),
      max_work=6,
    ),
    [columns[0]],
  )
  try
    expanded_star_columns(
      projection,
      reordered,
      column_profiles=Some(profiles),
      max_work=5,
    )
  catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => ()
    _ => fail("wrong one-short short-circuit scan refusal")
  } noraise {
    _ => fail("one-short actual consultations must refuse")
  }
  // Original all-named callers do not acquire the new namespace lookup demand.
  assert_eq(expanded_star_columns(projection, columns, max_work=0), [
    ("private", "slot0"),
  ])
  assert_true(
    physical_equal(
      columns[0].0,
      expanded_star_columns(
        projection,
        columns,
        column_profiles=Some(profiles),
        max_work=8,
      )[0].0,
    ),
  )
}

///|
test "expanded star occurrence is tied to the same projection and still visible slot" {
  let query = @query.parse_query("SELECT * FROM t", mapping_syntax_limits()).unwrap()
  let projection = selected_projections(query)[0]
  let copied = { ..projection, except_columns: [], replacements: [], }
  let columns = [("private", "slot0"), ("n", "slot1")]
  let expanded = Some([{ projection: copied, column: columns[0], }])
  assert_eq(
    expanded_star_columns(copied, columns, expansions=expanded, max_work=3),
    [columns[0]],
  )
  // A structurally equal, separately constructed Projection has no such link.
  let other = { ..projection, except_columns: [], replacements: [], }
  assert_eq(
    expanded_star_columns(other, columns, expansions=expanded, max_work=3),
    columns,
  )
  try
    expanded_star_columns(
      copied,
      [("n", "slot1")],
      expansions=expanded,
      max_work=3,
    )
  catch {
    Abort(UnknownColumn) => ()
    _ => fail("wrong removed-slot refusal")
  } noraise {
    _ => fail("an expanded occurrence cannot restore a removed slot")
  }
  try
    expanded_star_columns(copied, columns, expansions=expanded, max_work=2)
  catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => ()
    _ => fail("wrong one-short expansion scan refusal")
  } noraise {
    _ => fail("one-short expansion scan must refuse")
  }
}
