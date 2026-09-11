///|
test "guard scope determines the field unit and law without caller overrides" {
  let cases : Array[(GuardScope, String, @derivation.BoundUnit, String)] = [
    (JoinOutputRows, "actql.guard.join-output", Rows, "max_output_rows"),
    (CrossJoinOutputRows, "actql.guard.join-output", Rows, "max_output_rows"),
    (IntervalJoinOutputRows, "actql.guard.join-output", Rows, "max_output_rows"),
    (
      NestedArrayItems,
      "actql.guard.nested-array-items",
      ArrayItems,
      "max_items",
    ),
    (
      AggregateArrayItems(0),
      "actql.guard.array-aggregate",
      ArrayItems,
      "max_items",
    ),
    (
      AggregateStringBytes(9),
      "actql.guard.string-aggregate",
      Bytes,
      "max_bytes",
    ),
    (
      SequenceMatchesPerKey,
      "actql.guard.sequence-matches",
      MatchesPerKey,
      "max_matches_per_key",
    ),
    (SequenceOutputRows, "actql.guard.sequence-output", Rows, "max_output_rows"),
    (
      ComponentOutputRows,
      "actql.guard.components-output",
      Rows,
      "max_output_rows",
    ),
    (TraverseOutputRows, "actql.guard.traverse-output", Rows, "max_output_rows"),
    (ShortestOutputRows, "actql.guard.shortest-output", Rows, "max_output_rows"),
  ]
  for (scope, law, unit, field) in cases {
    assert_eq(guard_law(scope), (law, unit, field))
    assert_eq(@law.name(@law.admit(law).unwrap()), law)
  }
}
