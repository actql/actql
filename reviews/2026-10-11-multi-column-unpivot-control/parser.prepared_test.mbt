///|
// Prepared positive regression for the next unit, not a permanent refusal.
test "multi-column UNPIVOT retains grouped input and output positions" {
  for modifier in ["", "INCLUDE NULLS ", "EXCLUDE NULLS "] {
    let query = parse_query(
      "FROM wide |> UNPIVOT " + modifier +
      "((amount,note) FOR month IN ((jan_amount,jan_note) AS 'Jan',(feb_amount,`feb note`) AS 'Feb'))",
      query_limits(),
    ).unwrap()
    guard operation_at(query, 0) is Some(Unpivot(clause)) else {
      fail("the tuple must remain one authored UNPIVOT")
    }
    assert_eq(clause.value_columns.map(column => column.value), ["amount", "note"])
    assert_eq(clause.column_sets.map(columns => columns.map(column => column.value)), [
      ["jan_amount", "jan_note"], ["feb_amount", "feb note"],
    ])
    assert_true(clause.column_sets[1][1].quoted)
    assert_eq(clause.row_labels, [Some(TextLabel("Jan")), Some(TextLabel("Feb"))])
    assert_eq(clause.include_nulls, modifier == "INCLUDE NULLS ")
  }
}

///|
test "multi-column UNPIVOT refuses unequal tuple arity" {
  for text in [
    "FROM wide |> UNPIVOT((amount,note) FOR month IN ((jan_amount,jan_note),feb_amount))",
    "FROM wide |> UNPIVOT(amount FOR month IN ((jan_amount,jan_note)))",
  ] {
    assert_true(parse_query(text, query_limits()) is Err({ issue: Syntax(_), .. }), msg=text)
  }
}
