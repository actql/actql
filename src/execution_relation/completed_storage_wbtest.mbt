///|
// Legacy row-layout assertions must explicitly select that representation.
// These helpers never materialize typed storage and are not product adapters.
fn test_row_store(completion : CompletedSequence) -> TableStore[Table] {
  guard completion.store is RowStore(store) else { abort("expected row store") }
  store
}

///|
fn test_row_output(output : CompletedOutput) -> Table {
  guard output.table is RowTable(table) else { abort("expected row output") }
  table
}

///|
test "typed selection charges entire backing capacity not just visible rows" {
  let owner = row_owner("")
  let table = NumberTable({
    owner,
    id: "view",
    names: ["a"],
    count: 1,
    selection: Some([3]),
    columns: [
      {
        values: FixedArray::makei(4, i => i.to_double()),
        valid: FixedArray::make(4, b'\x01'),
      },
    ],
  })
  // One column handle + four doubles + four validity elements + one index.
  // This is a container/element ceiling, not an allocator-byte or RSS claim.
  for limit in [9, 10] {
    let workspace = { limit, live: 0, peak: 0, }
    assert_eq(
      reserve_completed_storage(table, workspace, {
        remaining: 1,
        max_frames: 0,
      }),
      limit == 10,
    )
    if limit == 10 {
      assert_eq(workspace.live, 10)
    }
  }
  assert_eq(IndexedRows::row_count(table), 1)
  assert_true(IndexedRows::read_cell(table, 0, 0) is Number(3))
}
