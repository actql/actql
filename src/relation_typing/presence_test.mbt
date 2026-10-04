///|
fn presence_schema() -> @schema.Schema {
  @schema.from_presence_fields(
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
}

///|
test "only guaranteed columns project from a conditional Relation schema" {
  let input = presence_schema()
  let projection = @relation_typing.check(
    Select,
    cursor("[\"id\"]"),
    input,
    None,
    limits(),
  ).unwrap()
  let output = @relation_typing.output_schema(projection)
  assert_true(@schema.all_fields_required(output))
  assert_true(@schema.as_object(output) is Some(_))
  assert_eq(@schema.field_count(output), 1)
  for body in ["[\"p\"]", "[{\"copy\":\"p\"}]"] {
    let issue = @relation_typing.check(
      Select,
      cursor(body),
      input,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, PresenceRequired("p"))
  }
  let issue = @relation_typing.check(
    Select,
    cursor("[\"unknown\"]"),
    input,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, UnknownField("unknown"))
}

///|
test "row-preserving consumers cannot silently erase conditional presence" {
  let input = presence_schema()
  for
    (op, body) in [
      (@relation_typing.Filter, "{\"is_not_null\":\"p\"}"),
      (Drop, "[\"p\"]"),
      (Rename, "{\"id\":\"key\"}"),
    ] {
    let issue = @relation_typing.check(op, cursor(body), input, None, limits()).unwrap_err()
    assert_eq(issue.kind, ConditionalInputNotImplemented)
  }
}
