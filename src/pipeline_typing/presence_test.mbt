///|
test "conditional Relation presence admits guaranteed projection and filter including empty input" {
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
  for body in ["[{\"derive\":{}}]"] {
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
  assert_true(
    @pipeline_typing.check(
      cursor("[{\"filter\":\"id < 4\"},{\"select\":[\"id\"]}]"),
      [("rows", schema)],
      None,
      None,
      limits(),
    )
    is Ok(_),
  )
  for body in ["p IS NOT NULL", "if(false, p > 0, true)"] {
    assert_true(
      @pipeline_typing.check(
        cursor("[{\"filter\":\"" + body + "\"}]"),
        [("rows", schema)],
        None,
        None,
        limits(),
      )
      is Err({ kind: Operation(PresenceRequired("p")), .. }),
    )
  }
  assert_true(
    @pipeline_typing.check(
      cursor(
        "[{\"filter\":\"id < 4\"},{\"sort\":[{\"id\":\"desc\"}]},{\"take\":1},{\"select\":[\"id\"]}]",
      ),
      [("rows", schema)],
      None,
      None,
      limits(),
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.check(
      cursor("[{\"sort\":[{\"p\":\"asc\"}]}]"),
      [("rows", schema)],
      None,
      None,
      limits(),
    )
    is Err({ kind: Operation(PresenceRequired("p")), .. }),
  )
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
