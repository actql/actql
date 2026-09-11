///|
test "store releases successful intermediate tables at the final branch consumer" {
  let owner = row_owner(
    ",{\"derive\":{\"c\":\"a + 1\"},\"as\":\"augmented\"},{\"filter\":\"a > 10\"},{\"from\":\"augmented\",\"select\":[\"c\"]}",
  )
  let control = { remaining: 10000, max_frames: 100, }
  let wiring = prepare_wiring(owner, ["select_3"], control, {
    limit: 1000,
    live: 0,
    peak: 0,
  }).unwrap()
  let workspace = { limit: 23, live: 0, peak: 0, }
  let store = table_store(wiring, workspace).unwrap()
  let source = row_capture(owner)
  commit_table(store, 0, source, control).unwrap()
  assert_eq(workspace.live, 12) // four slots + eight table entries
  let derived = evaluate_rows(
    row_kernel(owner, 1),
    source,
    2,
    control,
    row_output(),
  ).unwrap()
  commit_table(store, 1, derived, control).unwrap()
  assert_true(store.tables[0] is None)
  assert_eq(workspace.live, 15) // four slots + eleven derived entries
  assert_eq(workspace.peak, 23) // source and output coexist at adoption
  let empty = evaluate_rows(
    row_kernel(owner, 2),
    derived,
    2,
    control,
    row_output(),
  ).unwrap()
  commit_table(store, 2, empty, control).unwrap()
  assert_true(store.tables[1] is Some(_))
  assert_true(store.tables[2] is None)
  assert_eq(workspace.live, 15)
  let selected = evaluate_rows(
    row_kernel(owner, 3),
    derived,
    2,
    control,
    row_output(),
  ).unwrap()
  commit_table(store, 3, selected, control).unwrap()
  assert_true(store.tables[1] is None)
  assert_true(store.tables[3] is Some(_))
  assert_eq(workspace.live, 9) // four slots + one name/two rows/two cells
  assert_eq(store.next, 4)
  assert_true(commit_table(store, 3, selected, control) is Err(InvalidState))
}

///|
test "failed table adoption preserves existing input and cannot skip operations" {
  let owner = row_owner(",{\"derive\":{\"c\":\"a + 1\"}}")
  let control = { remaining: 10000, max_frames: 100, }
  let wiring = prepare_wiring(owner, ["derive_1"], control, {
    limit: 1000,
    live: 0,
    peak: 0,
  }).unwrap()
  let store = table_store(wiring, { limit: 20, live: 0, peak: 0, }).unwrap()
  let source = row_capture(owner)
  let derived = evaluate_rows(
    row_kernel(owner, 1),
    source,
    2,
    control,
    row_output(),
  ).unwrap()
  assert_true(commit_table(store, 1, derived, control) is Err(InvalidState))
  assert_eq(store.next, 0)
  commit_table(store, 0, source, control).unwrap()
  // Two slots + eight input + eleven output needs 21 entries, not 20.
  assert_true(commit_table(store, 1, derived, control) is Err(Limit))
  assert_eq(store.next, 1)
  assert_true(store.tables[0] is Some(_))
  assert_true(store.tables[1] is None)
  let foreign = row_capture(row_owner(""))
  assert_true(commit_table(store, 1, foreign, control) is Err(OwnerMismatch))
}
