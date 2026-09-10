///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 30000,
    }).unwrap(),
    {
      max_nodes: 100000,
      max_depth: 30000,
      max_string_bytes: 1000000,
      max_total_string_bytes: 1000000,
    },
  ).unwrap()
}

///|
fn limits() -> @relation_set.Limits {
  {
    max_work: 2000000,
    max_text_bytes: 2000000,
    max_nodes: 100000,
    max_depth: 30000,
  }
}

///|
fn row(contract : @contract.Contract) -> @schema.Schema {
  @schema.from_fields(
    [(Unqualified("value"), contract)],
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
}

///|
test "set operations retain modes operands and joined recursive extents" {
  let a = @contract.array_contract(
    @contract.string_contract(nullable=false, max_utf8_bytes=Some(5L)).unwrap(),
    nullable=false,
    max_items=Some(2L),
  ).unwrap()
  let b = @contract.array_contract(
    @contract.string_contract(nullable=true, max_utf8_bytes=Some(9L)).unwrap(),
    nullable=true,
    max_items=Some(7L),
  ).unwrap()
  let operations : Array[@relation_set.Operation] = [Except, Intersect]
  for operation in operations {
    for
      (text, mode) in [
        ("all", @relation_set.All),
        ("distinct", @relation_set.Distinct),
      ] {
      let checked = @relation_set.check(
        operation,
        cursor("{\"with\":\"right\",\"duplicates\":\"" + text + "\"}"),
        row(a),
        row(b),
        limits(),
      ).unwrap()
      assert_eq(@relation_set.operation(checked), operation)
      assert_eq(@relation_set.duplicates(checked), mode)
      assert_eq(@relation_set.with_name(checked), "right")
      let expected = b
      assert_true(
        @contract.type_equal(
          @schema.field_at(@relation_set.output_schema(checked), 0).unwrap().contract,
          expected,
          100,
        ),
      )
      let detached = @relation_set.alignment(checked)
      assert_eq(detached[0].left_index, 0)
      assert_eq(detached[0].right_index, 0)
      detached.clear()
      assert_eq(@relation_set.alignment(checked).length(), 1)
      assert_eq(@relation_set.pending_validations(checked).length(), 6)
    }
  }
}

///|
test "set body and duplicates mode are closed and required" {
  let schema = row(@contract.primitive(NumberType, nullable=false))
  for
    text in [
      "{}", "{\"with\":\"r\"}", "{\"with\":null,\"duplicates\":\"all\"}", "{\"with\":\"r\",\"duplicates\":\"all\",\"meta\":{}}",
      "[]",
    ] {
    assert_true(
      @relation_set.check(Except, cursor(text), schema, schema, limits())
      is Err({ kind: InvalidBody, .. }),
    )
  }
  for text in ["null", "1", "\"ALL\"", "\"\"", "{\"$param\":\"mode\"}"] {
    let e = @relation_set.check(
      Intersect,
      cursor("{\"with\":\"r\",\"duplicates\":" + text + "}"),
      schema,
      schema,
      limits(),
    ).unwrap_err()
    assert_eq(e.kind, InvalidDuplicates)
    assert_eq(e.path, [Key("duplicates")])
  }
}

///|
test "set schema alignment rejects missing domains and preserves provenance" {
  let number = @contract.primitive(NumberType, nullable=false)
  let text = @contract.primitive(StringType, nullable=false)
  let body = cursor("{\"with\":\"r\",\"duplicates\":\"all\"}")
  assert_true(
    @relation_set.check(Except, body, row(number), row(text), limits())
    is Err({ kind: Schema(IncompatibleContracts(_, _)), .. }),
  )
  let qualified = @schema.from_fields(
    [(Qualified(Left, "value"), number)],
    max_fields=1,
    max_name_bytes=10,
  ).unwrap()
  assert_true(
    @relation_set.check(Except, body, row(number), qualified, limits())
    is Err({ kind: Schema(MissingField(_, _)), .. }),
  )
  let empty = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  let result = @relation_set.check(Intersect, body, empty, empty, limits()).unwrap()
  assert_eq(@schema.field_count(@relation_set.output_schema(result)), 0)
}

///|
test "set work text node and depth bounds are exact" {
  let schema = row(@contract.primitive(NumberType, nullable=false))
  let body = cursor("{\"with\":\"r\",\"duplicates\":\"all\"}")
  let result = @relation_set.check(Except, body, schema, schema, limits()).unwrap()
  let used = @relation_set.usage(result)
  let exact : @relation_set.Limits = {
    max_work: used.work,
    max_text_bytes: used.text_bytes,
    max_nodes: used.nodes,
    max_depth: 1,
  }
  assert_true(@relation_set.check(Except, body, schema, schema, exact) is Ok(_))
  for
    small in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(
      @relation_set.check(Except, body, schema, schema, small)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}
