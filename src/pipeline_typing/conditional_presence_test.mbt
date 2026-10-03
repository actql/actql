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
  let input = [("rows", @carrier.relation(@carrier.typed_rows(conditional)))]
  assert_true(
    @pipeline_typing.check_carriers(
      cursor("[{\"select\":[\"id\"]}]"),
      input,
      None,
      None,
      limits(),
    )
    is Ok(_),
  )
  for
    (source, expected) in [
      ("[{\"select\":[\"p\"]}]", "presence"),
      ("[{\"filter\":\"p = 7\"}]", "unsupported"),
    ] {
    let result = @pipeline_typing.check_carriers(
      cursor(source),
      input,
      None,
      None,
      limits(),
    )
    if expected == "presence" {
      assert_true(
        result is Err({ kind: Operation(@relation.PresenceRequired("p")), .. }),
      )
    } else {
      assert_true(
        result
        is Err(
          { kind: Operation(@relation.ConditionalInputNotImplemented), .. }
        ),
      )
    }
  }
}
