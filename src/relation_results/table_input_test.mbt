///|
fn sparse_table_pipeline() -> @pipeline.CheckedPipeline {
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
      (
        Unqualified("tag"),
        @contract.primitive(StringType, nullable=true),
        Required,
      ),
    ],
    max_fields=3,
    max_name_bytes=6,
  ).unwrap()
  @pipeline.check(cursor("[]"), [("rows", schema)], None, None, {
    max_steps: 0,
    max_work: 10000,
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
}

///|
test "private Table input retains declared presence independently of nullable" {
  let pipeline = sparse_table_pipeline()
  let body =
    #|{"material":{"from":"rows","fields":["tag","p","id"]}}
  let declaration = cursor(body)
  let checked = check_table_inputs(pipeline, declaration, limits()).unwrap()
  assert_eq(table_input_count(checked), 1)
  assert_true(physical_equal(table_inputs_pipeline(checked), pipeline))
  let input = lookup_table_input(checked, "material").unwrap()
  assert_eq(table_input_name(input), "material")
  assert_eq(table_input_fields(input), ["tag", "p", "id"])
  assert_eq(table_input_target(input), @pipeline.Input(0))
  let schema = table_input_schema(input)
  let p = @schema.lookup_reference(schema, "p").unwrap()
  let id = @schema.lookup_reference(schema, "id").unwrap()
  let tag = @schema.lookup_reference(schema, "tag").unwrap()
  assert_eq(@schema.field_presence(p), Conditional)
  assert_true(
    @contract.type_equal(
      @schema.field_contract(p),
      @contract.primitive(NumberType, nullable=true),
      100,
    ),
  )
  assert_eq(@schema.field_presence(id), Required)
  assert_true(
    @contract.type_equal(
      @schema.field_contract(id),
      @contract.primitive(NumberType, nullable=false),
      100,
    ),
  )
  assert_eq(@schema.field_presence(tag), Required)
  assert_true(
    @contract.type_equal(
      @schema.field_contract(tag),
      @contract.primitive(StringType, nullable=true),
      100,
    ),
  )
  // The same source and fields remain invalid as an ordinary Named Result.
  assert_true(
    @relation_results.check(pipeline, declaration, limits())
    is Err({ kind: PresenceRequired("p"), .. }),
  )
  let copied = table_input_fields(input)
  copied[0] = "changed"
  assert_eq(table_input_fields(input), ["tag", "p", "id"])
  assert_true(table_input_at(checked, -1) is None)
  assert_true(lookup_table_input(checked, "unknown") is None)
}

///|
test "private Table input closes exact authored bindings and fields" {
  let pipeline = sparse_table_pipeline()
  let cases : Array[(String, @relation_results.IssueKind)] = [
    (
      "{\"material\":{\"from\":\"absent\",\"fields\":[\"id\"]}}",
      UnknownSource("absent"),
    ),
    (
      "{\"material\":{\"from\":\"rows\",\"fields\":[\"absent\"]}}",
      UnknownField("absent"),
    ),
    (
      "{\"material\":{\"from\":\"rows\",\"fields\":[\"p\",\"p\"]}}",
      DuplicateField("p"),
    ),
    ("{\"material\":{\"from\":\"rows\",\"fields\":[]}}", InvalidBody),
  ]
  for (body, expected) in cases {
    assert_eq(
      check_table_inputs(pipeline, cursor(body), limits()).unwrap_err().kind,
      expected,
    )
  }
  for
    body in [
      "{\"material\":{\"from\":\"rows\",\"fields\":[\"id\",\"p\"],\"order_by\":[{\"id\":\"asc\"}]}}",
      "{\"material\":{\"from\":\"rows\",\"fields\":[\"id\",\"p\"],\"presence\":\"required\"}}",
      "{\"material\":{\"from\":\"rows\",\"fields\":[\"id\",\"p\"],\"meta\":{}}}",
    ] {
    assert_true(check_table_inputs(pipeline, cursor(body), limits()) is Err(_))
  }
}

///|
test "private Table input uses bounded common field and source admission" {
  let pipeline = sparse_table_pipeline()
  let body =
    #|{"material":{"from":"rows","fields":["id","p"]}}
  let declaration = cursor(body)
  let used = table_inputs_usage(
    check_table_inputs(pipeline, declaration, limits()).unwrap(),
  )
  let exact = {
    ..limits(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_results: 1,
  }
  assert_true(check_table_inputs(pipeline, declaration, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_results: 0, },
    ] {
    assert_true(
      check_table_inputs(pipeline, declaration, cap)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}
