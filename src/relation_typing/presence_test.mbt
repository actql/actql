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
test "presence group admits guaranteed references and rejects optional references in every lane" {
  let input = presence_schema()
  let checked = @relation_typing.check(
    Group,
    cursor(
      "{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\"},\"m\":{\"fn\":\"max\",\"field\":\"id\"}}}",
    ),
    input,
    None,
    limits(),
  ).unwrap()
  let output = @relation_typing.output_schema(checked)
  assert_true(@schema.all_fields_required(output))
  assert_true(@schema.lookup_reference(output, "p") is None)
  for
    body in [
      "{\"by\":[\"p\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}", "{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\",\"field\":\"p\"}}}",
      "{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\",\"expr\":\"if(false, p, id)\"}}}",
      "{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\",\"filter\":\"false AND p IS NOT NULL\"}}}",
      "{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"first\",\"field\":\"id\",\"order_by\":[{\"p\":\"asc\"}]}}}",
    ] {
    assert_eq(
      @relation_typing.check(Group, cursor(body), input, None, limits()).unwrap_err().kind,
      PresenceRequired("p"),
    )
  }
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

///|
test "presence sort accepts Required keys and take preserves the schema" {
  let input = presence_schema()
  for
    (op, body) in [
      (@relation_typing.Sort, "[{\"id\":\"desc\"}]"),
      (@relation_typing.Take, "{\"count\":3,\"offset\":1}"),
    ] {
    let checked = @relation_typing.check(
      op,
      cursor(body),
      input,
      None,
      limits(),
    ).unwrap()
    assert_eq(
      @schema.lookup_reference(@relation_typing.output_schema(checked), "p").unwrap().presence,
      Conditional,
    )
  }
  assert_eq(
    @relation_typing.check(
      Sort,
      cursor("[{\"p\":\"asc\"}]"),
      input,
      None,
      limits(),
    ).unwrap_err().kind,
    PresenceRequired("p"),
  )
}

///|
test "presence keyed distinct projects guaranteed keys without retaining optional columns" {
  let input = presence_schema()
  let checked = @relation_typing.check(
    Distinct,
    cursor("[\"id\"]"),
    input,
    None,
    limits(),
  ).unwrap()
  let output = @relation_typing.output_schema(checked)
  assert_true(@schema.all_fields_required(output))
  assert_eq(@schema.field_count(output), 1)
  assert_eq(@schema.field_at(output, 0).unwrap().name, Unqualified("id"))
  assert_false(@schema.field_at(output, 0).unwrap().contract.nullable)
  assert_eq(
    @relation_typing.check(Distinct, cursor("[\"p\"]"), input, None, limits()).unwrap_err().kind,
    PresenceRequired("p"),
  )
  assert_eq(
    @relation_typing.check(Distinct, cursor("true"), input, None, limits()).unwrap_err().kind,
    ConditionalInputNotImplemented,
  )
  let nullable = @schema.from_presence_fields(
    [
      (
        Unqualified("id"),
        @contract.primitive(NumberType, nullable=true),
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
  let nullable_output = @relation_typing.output_schema(
    @relation_typing.check(
      Distinct,
      cursor("[\"id\"]"),
      nullable,
      None,
      limits(),
    ).unwrap(),
  )
  assert_true(@schema.field_at(nullable_output, 0).unwrap().contract.nullable)
  for body in ["[]", "[\"id\",\"id\"]", "false"] {
    assert_true(
      @relation_typing.check(Distinct, cursor(body), input, None, limits())
      is Err(_),
    )
  }
}
