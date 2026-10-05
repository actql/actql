///|
test "conditional Relation presence admits guaranteed projection filter and derive including empty input" {
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
  let distinct = @pipeline_typing.check(
    cursor("[{\"distinct\":[\"id\"]}]"),
    [("rows", schema)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(
    @schema.all_fields_required(
      @pipeline_typing.output_schema(distinct).unwrap(),
    ),
  )
  for
    (body, kind) in [
      ("[{\"distinct\":[\"p\"]}]", @relation.PresenceRequired("p")),
    ] {
    assert_true(
      @pipeline_typing.check(
        cursor(body),
        [("rows", schema)],
        None,
        None,
        limits(),
      )
      is Err({ kind: Operation(actual), .. }) &&
      actual == kind,
    )
  }
  let whole = @pipeline_typing.check(
    cursor("[{\"distinct\":true}]"),
    [("rows", schema)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(
    physical_equal(@pipeline_typing.output_schema(whole).unwrap(), schema),
  )
  for
    body in [
      "[{\"derive\":{}}]", "[{\"derive\":{\"z\":\"id + 1\"}},{\"select\":[\"id\",\"z\"]}]",
      "[{\"derive\":[{\"p\":\"id + 1\"},{\"z\":\"p + 1\"}]},{\"select\":[\"id\",\"p\",\"z\"]}]",
    ] {
    assert_true(
      @pipeline_typing.check(
        cursor(body),
        [("rows", schema)],
        None,
        None,
        limits(),
      )
      is Ok(_),
    )
  }
  for expression in ["p + 1", "if(false, p, id)", "p IS NOT NULL"] {
    assert_true(
      @pipeline_typing.check(
        cursor("[{\"derive\":{\"z\":\"" + expression + "\"}}]"),
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
