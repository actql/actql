///|
test "projection name sizing preserves qualifier and surrogate bounds" {
  assert_eq(
    sequence_projection_reference_name_bound(@schema.Unqualified("id")),
    6L,
  )
  assert_eq(
    sequence_projection_reference_name_bound(
      @schema.Qualified(@schema.Left, "é😀"),
    ),
    14L,
  )
  assert_eq(
    sequence_projection_reference_name_bound(
      @schema.Qualified(@schema.Right, "é😀"),
    ),
    15L,
  )
}
