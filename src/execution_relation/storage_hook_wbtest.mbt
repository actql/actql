///|
test "absent physical reservation hook preserves row accounting and explicit hooks still run" {
  let owner = row_owner("")
  let control = { remaining: 10000, max_frames: 100, }
  let wiring = prepare_wiring(owner, ["values_0"], control, {
    limit: 1000,
    live: 0,
    peak: 0,
  }).unwrap()
  let source = row_capture(owner)
  let plain = table_store(wiring, { limit: 1000, live: 0, peak: 0, }).unwrap()
  assert_true(plain.reserve_storage is None)
  let calls = [0]
  let explicit = table_store(
    wiring,
    { limit: 1000, live: 0, peak: 0, },
    reserve_storage=Some(fn(_, _, _) {
      calls[0] += 1
      true
    }),
  ).unwrap()
  let a = { remaining: 10000, max_frames: 100, }
  let b = { remaining: 10000, max_frames: 100, }
  commit_table(plain, 0, source, a).unwrap()
  commit_table(explicit, 0, source, b).unwrap()
  assert_eq(calls[0], 1)
  assert_eq(a.remaining, b.remaining)
  assert_eq(plain.workspace.live, explicit.workspace.live)
  assert_eq(plain.workspace.peak, explicit.workspace.peak)
  let rejected = table_store(
    wiring,
    { limit: 1000, live: 0, peak: 0, },
    reserve_storage=Some(fn(_, _, _) { false }),
  ).unwrap()
  assert_true(commit_table(rejected, 0, source, b) is Err(Limit))
  assert_eq(rejected.next, 0)
  assert_true(rejected.tables.all(table => table is None))
}
