///|
test "conditional Relation presence only admits guaranteed projection including empty input" {
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
  assert_true(
    @pipeline_typing.check(
      cursor("[{\"select\":[\"id\"]}]"),
      [("rows", schema)],
      None,
      None,
      limits(),
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.check(
      cursor("[{\"select\":[\"p\"]}]"),
      [("rows", schema)],
      None,
      None,
      limits(),
    )
    is Err({ kind: Operation(PresenceRequired("p")), .. }),
  )
  for body in ["[{\"derive\":{}}]", "[{\"filter\":\"p IS NOT NULL\"}]"] {
    assert_true(
      @pipeline_typing.check(
        cursor(body),
        [("rows", schema)],
        None,
        None,
        limits(),
      )
      is Err({ kind: Operation(ConditionalInputNotImplemented), .. }),
    )
  }
  let dense = @schema.from_fields(
    [(Unqualified("id"), @contract.primitive(NumberType, nullable=false))],
    max_fields=1,
    max_name_bytes=2,
  ).unwrap()
  assert_true(
    @pipeline_typing.check(
      cursor("[{\"cross_join\":{\"with\":\"right\"},\"from\":\"left\"}]"),
      [("left", dense), ("right", schema)],
      None,
      None,
      limits(),
    )
    is Err({ kind: Operation(ConditionalInputNotImplemented), .. }),
  )
}
