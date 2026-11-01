///|
test "original qualified reference quote preserves actual UTF16 spelling and borrows unqualified names" {
  let q = reference_name_construction_extent(Unqualified("é😀"))
  assert_eq(q.scratch.record_headers, 0L)
  assert_eq(q.scratch_utf16_units, 0L)
  for
    (side, expected) in [
      (@relation_schema.Left, 8L),
      (@relation_schema.Right, 9L),
    ] {
    let name = @relation_schema.Qualified(side, "é😀")
    let q = reference_name_construction_extent(name)
    assert_eq(q.scratch.record_headers, 1L)
    assert_eq(q.scratch_utf16_units, expected)
    assert_eq(reference_name(name).length().to_int64(), expected)
    assert_eq(q.retained.record_headers, 0L)
  }
}
