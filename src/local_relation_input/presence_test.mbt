///|
test "snapshot schema agreement retains conditional presence without weakening author assertions" {
  let schema = @schema.from_presence_fields(
    [
      (
        Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
        Required,
      ),
      (
        Unqualified("p"),
        @contract.primitive(NumberType, nullable=true),
        Conditional,
      ),
    ],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  let unknown = read(cursor("{\"carrier\":\"relation\"}"), caps()).unwrap()
  let agreement = check_schema(unknown, schema, caps()).unwrap()
  assert_true(physical_equal(supplied_schema(agreement), schema))
  assert_eq(
    @schema.lookup_reference(supplied_schema(agreement), "p").unwrap().presence,
    Conditional,
  )
  let required = read(
    cursor(
      "{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"p\":{\"type\":\"number\",\"nullable\":true}}}",
    ),
    caps(),
  ).unwrap()
  assert_true(check_schema(required, schema, caps()) is Err(TypeMismatch))
  let ordered = read(
    cursor(
      "{\"carrier\":\"relation\",\"duplicates\":{\"first_by_order\":{\"order_by\":[{\"p\":\"asc\"}]}}}",
    ),
    caps(),
  ).unwrap()
  assert_true(
    check_schema(ordered, schema, caps()) is Err(InvalidOrderField("p")),
  )
  assert_true(
    check_schema(unknown, schema, { ..caps(), max_nodes: 1, })
    is Err(BudgetExceeded),
  )
}
