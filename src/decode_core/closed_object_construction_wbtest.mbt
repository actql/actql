///|
test "closed-object construction owns actual wide key path and complete original refusal location" {
  let narrow = admit(
    node(@source.Object([entry("x", node(@source.Number(7.0)))])),
    budget(),
  ).unwrap()
  let n = closed_object_construction_extent(narrow, 1, 0).unwrap()
  assert_eq(
    (n.record_headers, n.reference_slots, n.scalar_words),
    (31L, 88L, 49L),
  )
  assert_true(closed_object(narrow, ["x"]) is Ok(_))
  let wide = admit(
    node(
      @source.Object(
        Array::makei(9, i => entry("k" + i.to_string(), node(@source.Null))),
      ),
    ),
    budget(),
  ).unwrap()
  let n = closed_object_construction_extent(wide, 1, 0).unwrap()
  assert_eq(
    (n.record_headers, n.reference_slots, n.scalar_words),
    (176L, 529L, 477L),
  )
  let issue = match closed_object(wide, ["x"]) {
    Err(issue) => issue
    Ok(_) => abort("original wide unknown field")
  }
  assert_eq(issue.kind, UnknownField)
  assert_eq(issue.path, [@source.Key("k0")])
  let nested = closed_object_construction_extent(wide, 1, 3).unwrap()
  // Three actual path segments add3H12R6W, not an adjacent tree's full usage.
  assert_eq(
    (nested.record_headers, nested.reference_slots, nested.scalar_words),
    (179L, 541L, 483L),
  )
}

///|
test "closed-object constructor wrong-kind and invalid quantity inputs do not run key checks" {
  let scalar = admit(node(@source.Null), budget()).unwrap()
  let n = closed_object_construction_extent(scalar, 1000, 0).unwrap()
  assert_eq(
    (n.record_headers, n.reference_slots, n.scalar_words),
    (13L, 26L, 9L),
  )
  assert_true(closed_object(scalar, ["x"]) is Err({ kind: WrongType, .. }))
  assert_true(closed_object_construction_extent(scalar, -1, 0) is None)
  assert_true(closed_object_construction_extent(scalar, 1, -1) is None)
}
