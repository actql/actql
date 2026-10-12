///|
fn serialize_steps(options : String) -> @decode.Cursor {
  cursor(
    "[{\"from\":\"rows\",\"serialize\":" + options + ",\"as\":\"attachment\"}]",
  )
}

///|
test "serialize key completion remains input evidence not output key evidence" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      (
        #|[{"time_series":{"start":"2000-01-01T00:00:00.000Z","end":"2000-01-01T00:00:00.002Z","step":1},"as":"grid"},{"derive":{"x":{"literal":1}}},{"serialize":{"format":"jsonl","fields":["x"],"order_by":[{"x":"desc"}],"name":"out.jsonl"}}]
      ),
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let order = @pipeline_typing.serialization_order(p, 2).unwrap()
  let completion = @pipeline_typing.serialization_order_completion(order).unwrap()
  assert_true(
    @pipeline_typing.serialization_sort_strategy(order) is Some(CandidateKey(_)),
  )
  assert_eq(@pipeline_typing.sort_completion_count(completion), 1)
  assert_eq(
    @pipeline_typing.sort_completion_field(completion, 0),
    Some(Unqualified("time")),
  )
  assert_true(@pipeline_typing.serialization_order_inherited(order) is None)
  // `time` is an input tie-break. The output has only serialization metadata.
  assert_true(
    @pipeline_typing.order_sort_completion(
      @pipeline_typing.logical_order(p, Step(2)).unwrap(),
    )
    is None,
  )
  assert_true(
    @schema.lookup_reference(@pipeline_typing.output_schema(p).unwrap(), "time")
    is None,
  )
  assert_true(
    @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=3,
      max_work=100,
      max_text_bytes=100,
    )
    is Ok(_),
  )
}

///|
test "serialize retains typed profile and refuses unproved input order" {
  let p = @pipeline_typing.check(
    serialize_steps(
      "{\"format\":\"csv\",\"fields\":[\"id\",\"flag\"],\"preserve_order\":true,\"name\":\"out.csv\",\"header\":true,\"null_marker\":\"\"}",
    ),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  guard @pipeline_typing.step_at(p, 0)
    is Some({ operation: Serialize(checked), .. }) else {
    fail("checked serialize")
  }
  assert_true(@pipeline_typing.serialization_sort(checked) is None)
  assert_eq(@schema.field_count(@pipeline_typing.output_schema(p).unwrap()), 5)
  let count = @pipeline_typing.row_count(p, Step(0)).unwrap()
  assert_eq((count.upper, count.exact), (1L, true))
  assert_true(@pipeline_typing.logical_order(p, Step(0)) is Some(_))
  // Neither the typed schema nor the one-row result licenses provider order.
  assert_true(@pipeline_typing.serialization_order(p, 0) is None)
  assert_eq(
    @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=10,
      max_work=100,
      max_text_bytes=100,
    ).unwrap_err().kind,
    SerializeOrderUnproven,
  )
}

///|
test "serialize empty typed input retains its actual order owner" {
  let source = cursor(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"id\"],\"name\":\"empty.jsonl\",\"preserve_order\":true}}]",
  )
  let p = @pipeline_typing.check(source, [], None, None, limits()).unwrap()
  let order = @pipeline_typing.serialization_order(p, 1).unwrap()
  assert_eq(@pipeline_typing.serialization_order_input(order), Step(0))
  assert_true(
    physical_equal(@pipeline_typing.serialization_order_pipeline(order), p),
  )
  assert_true(
    physical_equal(
      @pipeline_typing.serialization_order_inherited(order).unwrap(),
      @pipeline_typing.logical_order(p, Step(0)).unwrap(),
    ),
  )
  assert_true(@pipeline_typing.serialization_order_completion(order) is None)
  assert_true(@pipeline_typing.serialization_sort_strategy(order) is None)
  let resolved = @pipeline_typing.resolve_contextual_orders(
    p,
    max_steps=2,
    max_work=2,
    max_text_bytes=0,
  ).unwrap()
  assert_eq(@pipeline_typing.contextual_order_count(resolved, 1), Some(1))
  let count = @pipeline_typing.row_count(p, Step(1)).unwrap()
  assert_eq((count.upper, count.exact), (1L, true))
}

///|
test "serialize distinguishes selected CSV presence from JSONL omission" {
  let sparse = @schema.from_presence_fields(
    [
      (
        Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
        Required,
      ),
      (
        Unqualified("p"),
        @contract.primitive(StringType, nullable=true),
        Conditional,
      ),
    ],
    max_fields=2,
    max_name_bytes=10,
  ).unwrap()
  for
    (format, fields, csv, accepted) in [
      ("jsonl", "[\"id\",\"p\"]", "", true),
      ("csv", "[\"id\"]", ",\"header\":true,\"null_marker\":\"\"", true),
      ("csv", "[\"id\",\"p\"]", ",\"header\":true,\"null_marker\":\"\"", false),
    ] {
    let outcome = @pipeline_typing.check(
      serialize_steps(
        "{\"format\":\"" +
        format +
        "\",\"fields\":" +
        fields +
        ",\"name\":\"out\",\"preserve_order\":true" +
        csv +
        "}",
      ),
      [("rows", sparse)],
      None,
      None,
      limits(),
    )
    assert_eq(outcome is Ok(_), accepted)
    if outcome is Err(issue) {
      assert_eq(issue.kind, Serialize(@content.ContentConditionalCsv("p")))
    }
  }
}

///|
test "serialize ORDER BY retains authored keys without claiming they are unique" {
  let p = @pipeline_typing.check(
    serialize_steps(
      "{\"format\":\"jsonl\",\"fields\":[\"id\"],\"name\":\"out\",\"order_by\":[{\"id\":\"desc\"}]}",
    ),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  guard @pipeline_typing.step_at(p, 0).unwrap().operation is Serialize(checked) else {
    fail("serialize")
  }
  let sort = @pipeline_typing.serialization_sort(checked).unwrap()
  assert_eq(@relation.sort_term_at(sort, 0).unwrap().direction, Desc)
  assert_true(@pipeline_typing.serialization_order(p, 0) is None)
  assert_eq(
    @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=1,
      max_work=10,
      max_text_bytes=10,
    ).unwrap_err().kind,
    SerializeOrderUnproven,
  )
}

///|
test "serialize closed options and order intent are checked for every branch" {
  for
    body in [
      "{\"format\":\"jsonl\",\"fields\":[\"id\"],\"preserve_order\":true,\"name\":\"out\",\"bounds\":{}}",
      "{\"format\":\"jsonl\",\"fields\":[\"id\"],\"preserve_order\":true,\"name\":\"out\",\"bounds\":{\"max_rows\":0}}",
      "{\"format\":\"jsonl\",\"fields\":[\"id\"],\"preserve_order\":true,\"name\":\"out\",\"bounds\":{\"max_bytes\":1,\"other\":1}}",
      "{\"format\":\"jsonl\",\"fields\":[\"id\"],\"preserve_order\":true,\"name\":\"out\",\"max_rows\":1}",
      "{\"format\":\"csv\",\"fields\":[\"id\"],\"name\":\"out.csv\",\"header\":true,\"null_marker\":\"\"}",
      "{\"format\":\"csv\",\"fields\":[\"id\"],\"order_by\":[],\"name\":\"out.csv\",\"header\":true,\"null_marker\":\"\"}",
      "{\"format\":\"csv\",\"fields\":[\"id\"],\"preserve_order\":false,\"name\":\"out.csv\",\"header\":true,\"null_marker\":\"\"}",
      "{\"format\":\"csv\",\"fields\":[\"id\"],\"order_by\":[{\"id\":\"asc\"}],\"preserve_order\":true,\"name\":\"out.csv\",\"header\":true,\"null_marker\":\"\"}",
      "{\"format\":\"jsonl\",\"fields\":[\"id\"],\"preserve_order\":true,\"name\":\"out.jsonl\",\"header\":false}",
      "{\"format\":\"csv\",\"fields\":[\"id\"],\"preserve_order\":true,\"name\":\"out.csv\",\"csv\":{\"header\":true,\"null\":\"\"}}",
    ] {
    assert_true(
      @pipeline_typing.check(
        serialize_steps(body),
        [("rows", schema())],
        None,
        None,
        limits(),
      )
      is Err(_),
    )
  }
}
