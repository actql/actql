///|
test "owned preorder annotations reject foreign cursors and obey tree limits" {
  let span : @source.Span = {
    start_byte: 0,
    end_byte: 0,
    start_line: 1,
    start_column: 1,
    end_line: 1,
    end_column: 1,
    source_path: "builder",
  }
  let xs : Array[Node[Int]] = [{ value: String("abc"), span, annotation: 2, }]
  let root : Node[Int] = {
    value: Object([
      {
        key: "x",
        key_span: span,
        value: { value: Array(xs), span, annotation: 1, },
      },
    ]),
    span,
    annotation: 0,
  }
  let limits : @decode.Limits = {
    max_nodes: 3,
    max_depth: 2,
    max_string_bytes: 3,
    max_total_string_bytes: 4,
  }
  let (cursor, sidecar) = admit(root, limits).unwrap()
  assert_eq(node_count(sidecar), 3)
  assert_eq(annotation(sidecar, cursor), Some(0))
  let a = @decode.lookup(@decode.open_object(cursor).unwrap(), "x").unwrap()
  let item = @decode.elements(a).unwrap()[0]
  assert_eq(annotation(sidecar, a), Some(1))
  assert_eq(annotation(sidecar, item), Some(2))
  xs.clear()
  assert_eq(@decode.text(item).unwrap(), "abc")
  assert_eq(annotation(sidecar, admit(root, limits).unwrap().0), None)
  let leaf : Node[Int] = { value: String("abc"), span, annotation: 3, }
  assert_true(
    admit(leaf, { ..limits, max_nodes: 0, })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    admit(leaf, { ..limits, max_nodes: -1, })
    is Err({ kind: InvalidLimits, .. }),
  )
  assert_true(
    admit(leaf, { ..limits, max_string_bytes: 2, })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    admit(root, { ..limits, max_depth: 0, })
    is Err({ kind: BudgetExceeded, .. }),
  )
  // Mutable builder cycles remain bounded and never publish a partial map.
  xs.push(root)
  assert_true(
    admit(root, { ..limits, max_nodes: 100, max_depth: 10, })
    is Err({ kind: BudgetExceeded, .. }),
  )
}
