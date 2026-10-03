///|
test "unadapted Relation consumers reject conditional rows before execution" {
  let number = @contract.primitive(NumberType, nullable=false)
  let nullable = @contract.primitive(NumberType, nullable=true)
  let conditional = @schema.from_presence_fields(
    [
      (Unqualified("id"), number, @schema.Required),
      (Unqualified("p"), nullable, @schema.Conditional),
    ],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  let input = [
    ("rows", @carrier.relation(@carrier.conditional_rows(conditional))),
  ]
  for source in ["[{\"select\":[\"p\"]}]", "[{\"filter\":\"p = 7\"}]"] {
    let result = @pipeline_typing.check_carriers(
      cursor(source),
      input,
      None,
      None,
      limits(),
    )
    assert_true(result is Err({ kind: IncompleteSchema, .. }))
  }
}
