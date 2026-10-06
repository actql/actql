///|
test "constructor key columns retain component order types and detached names" {
  let number = @value.primitive(NumberType, nullable=true)
  let text = @value.primitive(StringType, nullable=false)
  let columns = ["person_key", "tenant_key"]
  let definition = graph_node_definition(
    "Person",
    [number, text],
    rows([], field_set=Closed, max_fields=0, max_name_bytes=0).unwrap(),
    [],
    key_columns=columns,
    max_fields=4,
    max_name_bytes=100,
  ).unwrap()
  columns.clear()
  assert_eq(
    graph_element_definition_key_column_at(definition, 0),
    Some("person_key"),
  )
  assert_eq(
    graph_element_definition_key_column_at(definition, 1),
    Some("tenant_key"),
  )
  assert_true(graph_element_definition_key_column_at(definition, 2) is None)
  assert_true(
    graph_element_definition_key_at(definition, 0).unwrap().shape
    is @value.Number,
  )
  assert_true(
    graph_element_definition_key_at(definition, 1).unwrap().shape
    is @value.Text(_),
  )
  assert_false(graph_element_definition_key_at(definition, 0).unwrap().nullable)
}

///|
test "key column correspondence rejects missing components duplicate names and limits" {
  let number = @value.primitive(NumberType, nullable=false)
  let properties = rows([], field_set=Closed, max_fields=0, max_name_bytes=0).unwrap()
  for columns in [["one"], ["one", "ONE"], ["one", "e\u0301"]] {
    assert_true(
      graph_node_definition(
        "N",
        [number, number],
        properties,
        [],
        key_columns=columns,
        max_fields=4,
        max_name_bytes=100,
      )
      is Err(InvalidKey),
    )
  }
  assert_true(
    graph_node_definition(
      "N",
      [number],
      properties,
      [],
      key_columns=["original_key"],
      max_fields=4,
      max_name_bytes=3,
    )
    is Err(LimitExceeded),
  )
  let (_, work) = graph_node_definition_usage(
    "N",
    [number],
    properties,
    [],
    key_columns=["original_key"],
    max_fields=4,
    max_name_bytes=100,
  ).unwrap()
  assert_true(
    graph_node_definition_usage(
      "N",
      [number],
      properties,
      [],
      key_columns=["original_key"],
      max_fields=4,
      max_name_bytes=100,
      max_contract_work=work - 1,
    )
    is Err(LimitExceeded),
  )
}
