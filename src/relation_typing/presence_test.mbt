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
      (@relation_typing.Drop, "[\"p\"]"),
      (Rename, "{\"id\":\"key\"}"),
    ] {
    let issue = @relation_typing.check(op, cursor(body), input, None, limits()).unwrap_err()
    assert_eq(issue.kind, ConditionalInputNotImplemented)
  }
}

///|
test "filter preserves conditional schema and checks every syntactic reference" {
  let input = presence_schema()
  let checked = @relation_typing.check(
    Filter,
    cursor("\"id < 4\""),
    input,
    None,
    limits(),
  ).unwrap()
  assert_false(
    @schema.all_fields_required(@relation_typing.output_schema(checked)),
  )
  assert_eq(
    @schema.lookup_reference(@relation_typing.output_schema(checked), "p").unwrap().presence,
    @schema.Conditional,
  )
  for body in ["p IS NOT NULL", "if(false, p > 0, id < 4)", "true OR p > 0"] {
    assert_eq(
      @relation_typing.check(
        Filter,
        cursor("\"" + body + "\""),
        input,
        None,
        limits(),
      ).unwrap_err().kind,
      PresenceRequired("p"),
    )
  }
}

///|
test "presence derive keeps untouched columns and gives computed bindings Required presence" {
  for body in ["{\"z\":\"id + 1\"}", "[{\"z\":\"id + 1\"}]"] {
    let checked = @relation_typing.check(
      Derive,
      cursor(body),
      presence_schema(),
      None,
      limits(),
    ).unwrap()
    let schema = @relation_typing.output_schema(checked)
    assert_eq(
      @schema.lookup_reference(schema, "p").unwrap().presence,
      @schema.Conditional,
    )
    assert_true(
      @schema.lookup_reference(schema, "p").unwrap().contract.nullable,
    )
    assert_eq(
      @schema.lookup_reference(schema, "z").unwrap().presence,
      @schema.Required,
    )
    assert_false(
      @schema.lookup_reference(schema, "z").unwrap().contract.nullable,
    )
  }
  for expr in ["p", "if(false, p, id)", "if(p IS NOT NULL, id, 0)"] {
    assert_eq(
      @relation_typing.check(
        Derive,
        cursor("{\"z\":\"" + expr + "\"}"),
        presence_schema(),
        None,
        limits(),
      ).unwrap_err().kind,
      PresenceRequired("p"),
    )
  }
  // Explicit ordered replacement creates a new proven binding, not a proof
  // inferred from the old optional column's data or a NULL predicate.
  let checked = @relation_typing.check(
    Derive,
    cursor("[{\"p\":\"id + 1\"},{\"z\":\"p + 1\"}]"),
    presence_schema(),
    None,
    limits(),
  ).unwrap()
  assert_true(
    @schema.all_fields_required(@relation_typing.output_schema(checked)),
  )
  assert_eq(
    @relation_typing.references(
      @relation_typing.binding_at(checked, 1).unwrap(),
    )[0].target,
    PriorSlot(0),
  )
}

///|
test "presence derive regression keeps untouched Conditional fields" {
  let result = @relation_typing.check(
    Derive,
    cursor("{\"z\":\"id + 1\"}"),
    presence_schema(),
    None,
    limits(),
  )
  match result {
    Err(issue) => {
      assert_eq(issue.kind, @relation_typing.ConditionalInputNotImplemented)
      fail(
        "ConditionalInputNotImplemented: Required-only derive was rejected on sparse input",
      )
    }
    Ok(checked) => {
      let schema = @relation_typing.output_schema(checked)
      assert_eq(
        @schema.lookup_reference(schema, "p").unwrap().presence,
        @schema.Conditional,
      )
      assert_eq(
        @schema.lookup_reference(schema, "z").unwrap().presence,
        @schema.Required,
      )
    }
  }
}
