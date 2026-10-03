///|
fn property_node_rows_fixture(
  first : Array[(@row.FieldName, @contract.Contract?)],
  second : Array[(@row.FieldName, @contract.Contract?)],
) -> @carrier.Carrier {
  let id = @contract.primitive(NumberType, nullable=false)
  let a = @carrier.property_node_definition(
    "A",
    [id],
    @carrier.rows(first, field_set=Closed, max_fields=4, max_name_bytes=32).unwrap(),
    [],
    max_fields=4,
    max_name_bytes=32,
  ).unwrap()
  let b = @carrier.property_node_definition(
    "B",
    [id],
    @carrier.rows(second, field_set=Closed, max_fields=4, max_name_bytes=32).unwrap(),
    [],
    max_fields=4,
    max_name_bytes=32,
  ).unwrap()
  @carrier.property_graph(
    "sha256:" + "1".repeat(64),
    [a, b],
    [],
    max_definitions=2,
    max_contract_work=32,
  ).unwrap()
}

///|
test "property node rows derive required and conditional fields before execution" {
  let nullable = @contract.primitive(NumberType, nullable=true)
  let input = property_node_rows_fixture([(Unqualified("p"), Some(nullable))], [])
  let checked = @carrier_projection.check_property_node_rows(
    cursor("true"),
    input,
    { ..limits(), max_work: 13, },
  ).unwrap()
  assert_eq(@carrier_projection.property_node_rows_usage(checked).work, 13)
  assert_eq(@carrier_projection.property_node_rows_id_column(checked), 0)
  assert_eq(
    @carrier_projection.property_node_rows_property_column(checked, 0, 0),
    Some(1),
  )
  assert_eq(
    @carrier_projection.property_node_rows_source_property(checked, 0, 1),
    Some(0),
  )
  assert_true(
    @carrier_projection.property_node_rows_source_property(checked, 1, 1)
    is None,
  )
  assert_true(
    @carrier_projection.property_node_rows_source_property(checked, 0, 0)
    is None,
  )
  assert_true(
    @carrier_projection.property_node_rows_property_column(checked, 1, 0)
    is None,
  )
  let output = @carrier_projection.property_node_rows_output(checked)
  let rows = @carrier.relation_rows(output).unwrap()
  let shared = @carrier.complete_schema(rows).unwrap()
  assert_true(!@row.all_fields_required(shared))
  assert_eq(@row.field_at(shared, 0).unwrap().presence, @row.Presence::Required)
  assert_eq(
    @row.field_at(shared, 1).unwrap().presence,
    @row.Presence::Conditional,
  )
  assert_true(@carrier.lookup(rows, Unqualified("p")) is Unknown)
  let schema = @carrier_projection.property_node_rows_schema(checked)
  assert_true(
    @row.presence_lookup(schema, Unqualified("id")) is AlwaysPresent(_),
  )
  assert_true(
    @row.presence_lookup(schema, Unqualified("p")) is ConditionallyPresent(_),
  )
  assert_true(
    @carrier_projection.check_property_node_rows(cursor("true"), input, {
      ..limits(),
      max_work: 12,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    @carrier_projection.check_property_node_rows(cursor("true"), input, {
      ..limits(),
      max_nodes: 3,
    })
    is Ok(_),
  )
  assert_true(
    @carrier_projection.check_property_node_rows(cursor("true"), input, {
      ..limits(),
      max_nodes: 2,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
}

///|
test "property node rows collapse compatible case spellings and reject role collisions" {
  let number = @contract.primitive(NumberType, nullable=false)
  let input = property_node_rows_fixture([(Unqualified("P"), Some(number))], [
    (Unqualified("p"), Some(number)),
  ])
  let checked = @carrier_projection.check_property_node_rows(
    cursor("true"),
    input,
    limits(),
  ).unwrap()
  let schema = @carrier_projection.property_node_rows_schema(checked)
  assert_eq(
    @carrier_projection.property_node_rows_property_column(checked, 0, 0),
    @carrier_projection.property_node_rows_property_column(checked, 1, 0),
  )
  let shared_column = @carrier_projection.property_node_rows_property_column(
    checked, 0, 0,
  ).unwrap()
  assert_eq(
    @carrier_projection.property_node_rows_source_property(
      checked, 0, shared_column,
    ),
    Some(0),
  )
  assert_eq(
    @carrier_projection.property_node_rows_source_property(
      checked, 1, shared_column,
    ),
    Some(0),
  )
  assert_true(
    @row.presence_lookup(schema, Unqualified("P")) is AlwaysPresent(_),
  )
  assert_true(@row.presence_lookup(schema, Unqualified("p")) is AbsentField)
  let colliding = property_node_rows_fixture(
    [(Unqualified("ID"), Some(number))],
    [],
  )
  assert_true(
    @carrier_projection.check_property_node_rows(
      cursor("true"),
      colliding,
      limits(),
    )
    is Err({ kind: OutputCollision(Unqualified("ID")), .. }),
  )
}
