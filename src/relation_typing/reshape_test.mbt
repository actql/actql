///|
fn reshape_input() -> @contract.Contract {
  schema(
    "{\"payload\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"inner\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"leaf\":{\"type\":\"json\",\"nullable\":false}}}}},\"items\":{\"type\":\"array\",\"nullable\":true,\"items\":{\"type\":\"number\",\"nullable\":false},\"max_items\":0}}",
  )
}

///|
test "deep picks are iterative and unnest preserves deep opaque child contracts" {
  let mut nested = @contract.primitive(NumberType, nullable=false)
  let count = 10000
  for _ in 0..<count {
    nested = @contract.object_contract(
      [("x", nested)],
      nullable=false,
      max_fields=1,
      max_name_bytes=1,
    ).unwrap()
  }
  let row = @contract.object_contract(
    [("p", nested)],
    nullable=false,
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let path = Array::make(count, "\"x\"").join(",")
  let result = check_row(
    JsonPick,
    cursor("{\"column\":\"p\",\"path\":[" + path + "],\"output\":\"v\"}"),
    row,
    None,
    limits(),
  ).unwrap()
  assert_true(field(output_row(result), "v").shape is @contract.Number)
  let array = @contract.array_contract(nested, nullable=true).unwrap()
  let row = @contract.object_contract(
    [("a", array)],
    nullable=false,
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let result = check_row(
    Unnest,
    cursor("{\"column\":\"a\",\"as\":\"v\"}"),
    row,
    None,
    limits(),
  ).unwrap()
  assert_true(
    @contract.type_equal(field(output_row(result), "v"), nested, count + 1),
  )
  assert_true(!field(output_row(result), "v").nullable)
}

///|
test "typed pick retains opaque leaves and propagates nullable ancestors" {
  let body = cursor(
    "{\"column\":\"payload\",\"path\":[\"inner\",\"leaf\"],\"output\":\"picked\"}",
  )
  let result = check_row(
    @relation_typing.JsonPick,
    body,
    reshape_input(),
    None,
    limits(),
  ).unwrap()
  let picked = field(output_row(result), "picked")
  assert_true(picked.shape is @contract.Json)
  assert_true(picked.nullable)
  assert_true(
    @contract.type_equal(
      field(output_row(result), "payload"),
      field(reshape_input(), "payload"),
      100,
    ),
  )
  assert_eq(@relation_typing.form(result), Reshape)
  assert_eq(@relation_typing.tokens_used(result), 0)
  match @relation_typing.reshape(result).unwrap() {
    JsonPick(column~, path~, output~) => {
      assert_eq(column, @schema.Unqualified("payload"))
      assert_eq(path, ["inner", "leaf"])
      assert_eq(output, "picked")
      path[0] = "changed"
    }
    _ => fail("expected pick")
  }
  assert_true(
    @relation_typing.reshape(result)
    is Some(JsonPick(path=["inner", "leaf"], ..)),
  )
  assert_eq(
    indexed_obligation_copy(
      @relation_typing.pending_validations(result),
      @relation_typing.pending_validation_count(result),
      i => @relation_typing.pending_validation_at(result, i),
      (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
    )[0].kind,
    ValidateReshapeRows,
  )
  let failure = check_row(
    JsonPick,
    cursor(
      "{\"column\":\"payload\",\"path\":[\"inner\",\"leaf\",\"x\"],\"output\":\"picked\"}",
    ),
    reshape_input(),
    None,
    limits(),
  ).unwrap_err()
  assert_eq(failure.kind, ShapeEvidenceRequired)
  assert_eq(failure.path, [@source.Key("path"), Index(2)])
  assert_eq(failure.range, None)
}

///|
test "unnest outer and nullable array containers have distinct element contracts" {
  for outer in [false, true] {
    for index in ["", ",\"with_index\":true", ",\"with_index\":\"ix\""] {
      let result = check_row(
        @relation_typing.Unnest,
        cursor(
          "{\"column\":\"items\",\"as\":\"item\",\"outer\":" +
          outer.to_string() +
          index +
          "}",
        ),
        reshape_input(),
        None,
        limits(),
      ).unwrap()
      let row = output_row(result)
      assert_eq(field(row, "item").nullable, outer)
      assert_true(field(row, "items").nullable)
      match @relation_typing.reshape(result).unwrap() {
        Unnest(column~, element~, index~, outer=actual, max_items~) => {
          assert_eq(column, @schema.Unqualified("items"))
          assert_eq(element, "item")
          assert_eq(actual, outer)
          assert_eq(max_items, Some(0L))
          if index is Some(name) {
            assert_eq(field(row, name).nullable, outer)
            assert_true(field(row, name).shape is @contract.Number)
          }
        }
        _ => fail("expected unnest")
      }
      assert_eq(
        indexed_obligation_copy(
          @relation_typing.pending_validations(result),
          @relation_typing.pending_validation_count(result),
          i => @relation_typing.pending_validation_at(result, i),
          (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
        ).map(v => v.kind),
        [ValidateReshapeRows, ExpansionEnvelope],
      )
    }
  }
  let nullable_item = schema(
    "{\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":true}}}",
  )
  let result = check_row(
    @relation_typing.Unnest,
    cursor("{\"column\":\"items\",\"as\":\"item\"}"),
    nullable_item,
    None,
    limits(),
  ).unwrap()
  assert_true(field(output_row(result), "item").nullable)
}

///|
test "reshape rejects invalid shapes and reports the exact option or segment" {
  for
    (op, text, expected, path) in [
      (
        @relation_typing.JsonPick,
        "{\"column\":\"payload\",\"path\":[\"missing\"],\"output\":\"x\"}",
        @relation_typing.UnknownField("missing"),
        [@source.Key("path"), Index(0)],
      ),
      (
        @relation_typing.JsonPick,
        "{\"column\":\"items\",\"path\":[\"0\"],\"output\":\"x\"}",
        ExpectedObject,
        [Key("path"), Index(0)],
      ),
      (
        @relation_typing.Unnest,
        "{\"column\":\"payload\",\"as\":\"x\"}",
        ExpectedArray,
        [Key("column")],
      ),
      (
        @relation_typing.Unnest,
        "{\"column\":\"items\",\"as\":\"items\"}",
        InputCollision("items"),
        [Key("as")],
      ),
      (
        @relation_typing.Unnest,
        "{\"column\":\"items\",\"as\":\"x\",\"with_index\":\"x\"}",
        DuplicateOutput("x"),
        [Key("with_index")],
      ),
      (
        @relation_typing.Unnest,
        "{\"column\":\"items\",\"as\":\"x\",\"with_index\":false}",
        InvalidBody,
        [Key("with_index")],
      ),
      (
        @relation_typing.Unnest,
        "{\"column\":\"items\",\"as\":\"x\",\"outer\":null}",
        InvalidBody,
        [Key("outer")],
      ),
    ] {
    let body = cursor(text)
    let issue = check_row(op, body, reshape_input(), None, limits()).unwrap_err()
    assert_eq(issue.kind, expected)
    assert_eq(issue.path, path)
    assert_eq(issue.range, None)
    assert_true(issue.span.start_byte > 0)
  }
}

///|
test "reshape budgets are exact cumulative charges and include unused contracts" {
  for
    (op, text) in [
      (
        @relation_typing.JsonPick,
        "{\"column\":\"payload\",\"path\":[\"inner\",\"leaf\"],\"output\":\"picked\"}",
      ),
      (
        @relation_typing.Unnest,
        "{\"column\":\"items\",\"as\":\"item\",\"outer\":true,\"with_index\":true}",
      ),
    ] {
    let body = cursor(text)
    let value = check_row(op, body, reshape_input(), None, limits()).unwrap()
    let exact = {
      ..limits(),
      max_work: @relation_typing.work_used(value),
      max_text_bytes: @relation_typing.text_bytes_used(value),
      max_nodes: @relation_typing.nodes_used(value),
      max_tokens: 0,
    }
    assert_true(check_row(op, body, reshape_input(), None, exact) is Ok(_))
    for
      bound in [
        { ..exact, max_work: exact.max_work - 1, },
        { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
        { ..exact, max_nodes: exact.max_nodes - 1, },
        { ..exact, max_depth: 2, },
      ] {
      assert_true(
        check_row(op, body, reshape_input(), None, bound)
        is Err({ kind: BudgetExceeded, .. }),
      )
    }
  }
}
