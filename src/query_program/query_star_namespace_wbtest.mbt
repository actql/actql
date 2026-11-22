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

///|
test "computed object layout retains original row order and private SQL names" {
  let fields = [("private", "slot0"), ("f0_", "slot1"), ("n", "slot2")]
  let profiles : Array[ResultColumn] = [
    { label: "private", slot: "slot0", name: None, name_view: None, },
    {
      label: "f0_",
      slot: "slot1",
      name: Some({ value: "f0_", quoted: false, }),
      name_view: None,
    },
  ]
  let original : NamespaceView = Captured(fields, Some(profiles))
  let (layout, _) = namespace_object_columns(
    Some(original),
    ["f0_", "f0__", "n"],
    1000,
  )
  let columns = layout.unwrap()
  assert_eq(columns.map(column => column.label), ["f0__", "f0_", "n"])
  assert_eq(columns.map(column => column.name.map(name => name.value)), [
    None,
    Some("f0_"),
    Some("n"),
  ])
  let nested = Row([
    { name: Some({ value: "row", quoted: false, }), name_view: Some(original), },
  ])
  let (nested_layout, _) = namespace_object_columns(
    Some(Member(nested, { value: "row", quoted: false, })),
    ["n", "f0__", "f0_"],
    1000,
  )
  assert_eq(nested_layout.unwrap().map(column => column.label), [
    "f0__", "f0_", "n",
  ])
  let (joined, _) = namespace_object_columns(
    Some(Joined(original, original)),
    ["n", "f0_", "f0__"],
    1000,
  )
  assert_eq(
    joined.unwrap().map(column => column.name.map(name => name.value)),
    [None, Some("f0_"), Some("n")],
  )
  assert_true(namespace_object_columns(None, [], 0).0 is None)
  try namespace_object_columns(Some(original), ["foreign"], 1000) catch {
    Abort(InvalidContext) => ()
    _ => fail("wrong foreign layout refusal")
  } noraise {
    _ => fail("checked Object keys must match the original layout")
  }
  try namespace_object_columns(Some(original), ["f0_", "f0__", "n"], 0) catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => ()
    _ => fail("wrong layout Work refusal")
  } noraise {
    _ => fail("layout traversal must consume original Work")
  }
}

///|
test "computed object occurrence lookup never accepts a foreign projection" {
  let query = @query.parse_query("SELECT (t).* FROM t", mapping_syntax_limits()).unwrap()
  let projection = selected_projections(query)[0]
  let receiver = projection.expression.unwrap()
  let generated = @query.star_column_projection(
    query,
    projection,
    "f0_",
    object_field=true,
    anonymous=true,
  )
  assert_true(projection_alias(generated) is None)
  let column : ResultColumn = {
    label: "f0_",
    slot: "f0_",
    name: None,
    name_view: None,
  }
  let retained = Some([{ projection: generated, receiver, column, }])
  assert_true(expanded_object_column(generated, retained, 1) is Some(_))
  let foreign = { ..generated, replacements: [], }
  assert_true(expanded_object_column(foreign, retained, 1) is None)
  try expanded_object_column(generated, retained, 0) catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => ()
    _ => fail("wrong occurrence lookup Work refusal")
  } noraise {
    _ => fail("the actual occurrence scan must be bounded")
  }
}

///|
test "shared namespace DAG does not retain one field join per expanded visit" {
  let anonymous : NamespaceView = Row([{ name: None, name_view: None, }])
  let named : NamespaceView = Row([
    { name: Some({ value: "f0_", quoted: false, }), name_view: None, },
  ])
  let a : NamespaceView = Row([
    {
      name: Some({ value: "payload", quoted: false, }),
      name_view: Some(anonymous),
    },
  ])
  let b : NamespaceView = Row([
    {
      name: Some({ value: "payload", quoted: false, }),
      name_view: Some(named),
    },
  ])
  let mut shared : NamespaceView = Joined(a, b)
  for _ in 0..<7 {
    shared = Joined(shared, shared)
  }
  let (layout, _) = namespace_object_columns(Some(shared), ["payload"], 1000000)
  let columns = layout.unwrap()
  assert_eq(columns.length(), 1)
  match columns[0].name_view {
    Some(Joined(left, right)) => {
      assert_true(
        physical_equal(left, anonymous),
        msg="repeated terminal visits retained another join chain",
      )
      assert_true(physical_equal(right, named))
    }
    _ => fail("both original field constraints must survive exactly once")
  }
  let query = @query.parse_query(
    "SELECT payload.f0_ FROM t",
    mapping_syntax_limits(),
  ).unwrap()
  let expression = selected_projections(query)[0].expression.unwrap()
  try
    namespace_member(
      columns[0].name_view,
      { value: "f0_", quoted: false, },
      _ => (),
      expression,
      @query.expression_root(expression),
    )
  catch {
    Abort(Expression({ issue: @expression.UnknownReference, .. })) => ()
    _ => fail("wrong original anonymous constraint refusal")
  } noraise {
    _ => fail("folding repeated originals cannot discard the anonymous branch")
  }
}

///|
test "ordinary SELECT with no computed receiver returns before receiver work" {
  let query = @query.parse_query("SELECT n FROM t", mapping_syntax_limits()).unwrap()
  let original = selected_projections(query)
  let physical = Array::makei(128, index => "slot" + index.to_string())
  let mut calls = 0
  let (result, bindings, derives) = materialize_computed_star_receivers(
    original,
    original,
    physical,
    _ => {
      calls += 1
      raise Abort(InvalidContext)
    },
    _ => false,
    0,
  )
  assert_true(physical_equal(result, original))
  assert_true(bindings.is_empty())
  assert_true(derives.is_empty())
  assert_eq(calls, 0)
  assert_eq(physical.length(), 128)
}

///|
test "original namespace fold preserves foreign links and exact remaining Work" {
  let a : NamespaceView = Row([{ name: None, name_view: None, }])
  let b : NamespaceView = Row([
    { name: Some({ value: "f0_", quoted: false, }), name_view: None, },
  ])
  let original : NamespaceView = Joined(a, b)
  let foreign : NamespaceView = Row([{ name: None, name_view: None, }])
  let mut remaining = 3
  let spend = fn(amount : Int) -> Unit raise Abort {
    if amount > remaining {
      raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, }))
    }
    remaining -= amount
  }
  let folded = merge_namespace_views(Some(original), Some(a), spend).unwrap()
  assert_true(physical_equal(folded, original))
  assert_eq(remaining, 0)
  remaining = 3
  match merge_namespace_views(Some(original), Some(foreign), spend) {
    Some(Joined(left, right)) => {
      assert_true(physical_equal(left, original))
      assert_true(physical_equal(right, foreign))
    }
    _ => fail("structurally equal foreign views cannot replace an original")
  }
  assert_eq(remaining, 0)
  remaining = 2
  try merge_namespace_views(Some(original), Some(a), spend) catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => ()
    _ => fail("wrong one-short original-view scan refusal")
  } noraise {
    _ => fail("one-short Work cannot traverse or issue the folded result")
  }
}
