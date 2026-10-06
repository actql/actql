///|
test "UNNEST source preserves array value alias and zero-based offset names" {
  for
    text in [
      "SELECT element, position FROM UNNEST(@items) AS element WITH OFFSET AS position ORDER BY position",
      "FROM UNNEST(@items) AS element WITH OFFSET AS position |> SELECT element, position |> ORDER BY position",
    ] {
    let query = parse_query(text, query_limits()).unwrap()
    assert_true(relation(query).is_empty())
    guard operation_at(query, 0)
      is Some(UnnestSource(expression, element, Some(position))) else {
      fail("the source is a value-table expansion, not a Relation name")
    }
    assert_eq(element.value, "element")
    assert_eq(position.value, "position")
    assert_true(
      expression_node(expression, expression_root(expression)).unwrap().kind
      is ParameterReference("items"),
    )
  }
}
