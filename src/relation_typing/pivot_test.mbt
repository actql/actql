///|
fn pivot_row() -> @contract.Contract {
  schema(
    "{\"id\":{\"type\":\"string\",\"nullable\":false},\"status\":{\"type\":\"string\",\"nullable\":true},\"amount\":{\"type\":\"number\",\"nullable\":true},\"decimal\":{\"type\":\"decimal\",\"precision\":6,\"scale\":2,\"nullable\":false},\"data\":{\"type\":\"json\",\"nullable\":true}}",
  )
}

///|
fn pivot_check(
  body : String,
  params? : @parameter.Declarations? = None,
) -> Result[@relation_typing.CheckedOperation, @relation_typing.Issue] {
  check_row(Pivot, cursor(body), pivot_row(), params, limits())
}

///|
test "pivot keeps source value order separate from canonical generated columns" {
  let v = pivot_check(
    "{\"index\":[\"id\",\"id\"],\"column\":\"status\",\"values\":[\"z\",\"a\",\"😀\",\"\u{e000}\"],\"value\":\"amount\",\"aggregate\":\"sum\"}",
  ).unwrap()
  let p = @relation_typing.pivot(v).unwrap()
  assert_eq(@relation_typing.pivot_values(p), ["z", "a", "😀", "\u{e000}"])
  assert_eq(@relation_typing.pivot_columns(p), ["a", "z", "😀", "\u{e000}"])
  assert_eq(@relation_typing.pivot_index(p).length(), 2)
  assert_eq(@relation_typing.pivot_index_count(p), 2)
  assert_true(
    physical_equal(
      @relation_typing.pivot_index_at(p, 0).unwrap(),
      @relation_typing.pivot_index_at(p, 0).unwrap(),
    ),
  )
  assert_eq(
    @relation_typing.pivot_index_at(p, 0).unwrap().field,
    @relation_typing.pivot_index_at(p, 1).unwrap().field,
  )
  for invalid in [-1, 2147483647] {
    assert_true(@relation_typing.pivot_index_at(p, invalid) is None)
    assert_eq(@relation_typing.pivot_value_at(p, invalid), None)
    assert_eq(@relation_typing.pivot_column_at(p, invalid), None)
  }
  for i in 0..<@relation_typing.pivot_value_count(p) {
    assert_eq(
      @relation_typing.pivot_value_at(p, i),
      Some(@relation_typing.pivot_values(p)[i]),
    )
    assert_eq(
      @relation_typing.pivot_column_at(p, i),
      Some(@relation_typing.pivot_columns(p)[i]),
    )
  }
  let columns = @relation_typing.pivot_columns(p)
  columns.clear()
  assert_eq(@relation_typing.pivot_columns(p).length(), 4)
  assert_eq(@relation_typing.pivot_column_count(p), 4)
  assert_eq(@schema.field_count(@relation_typing.output_schema(v)), 5)
  assert_true(field(output_row(v), "a").nullable)
  assert_true(
    indexed_obligation_copy(
      @relation_typing.pending_validations(v),
      @relation_typing.pending_validation_count(v),
      i => @relation_typing.pending_validation_at(v, i),
      (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
    ).any(p => p.kind is NumericAggregateObservation),
  )
}

///|
test "empty pivot axes preserve validation and index-only schema" {
  for index in ["[]", "[\"id\",\"id\"]"] {
    let v = pivot_check(
      "{\"index\":" +
      index +
      ",\"column\":\"status\",\"values\":[],\"value\":\"amount\",\"aggregate\":\"sum\"}",
    ).unwrap()
    assert_eq(
      @schema.field_count(@relation_typing.output_schema(v)),
      if index == "[]" {
        0
      } else {
        1
      },
    )
    assert_true(
      indexed_obligation_copy(
        @relation_typing.pending_validations(v),
        @relation_typing.pending_validation_count(v),
        i => @relation_typing.pending_validation_at(v, i),
        (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
      ).any(p => p.kind is PivotPartitioning),
    )
  }
  for
    body in [
      "{\"index\":[],\"column\":\"amount\",\"values\":[],\"value\":\"amount\",\"aggregate\":\"sum\"}",
      "{\"index\":[],\"column\":\"status\",\"values\":[],\"value\":\"missing\",\"aggregate\":\"sum\"}",
      "{\"index\":[\"id\"],\"column\":\"status\",\"values\":[\"id\"],\"value\":\"amount\",\"aggregate\":\"sum\"}",
      "{\"index\":[],\"column\":\"status\",\"values\":[\"a\",\"a\"],\"value\":\"amount\",\"aggregate\":\"sum\"}",
    ] {
    assert_true(pivot_check(body) is Err(_))
  }
}

///|
test "pivot fill is typed against the aggregate result including decimal wire values" {
  for
    (fn_name, column, fill, nullable) in [
      ("sum", "amount", "0", false),
      ("avg", "amount", "null", true),
      ("count", "amount", "0", false),
      ("sum", "decimal", "\"12.30\"", false),
      ("first", "id", "\"unknown\"", false),
    ] {
    let v = pivot_check(
      "{\"index\":[],\"column\":\"status\",\"values\":[\"a\"],\"value\":\"" +
      column +
      "\",\"aggregate\":\"" +
      fn_name +
      "\",\"fill\":" +
      fill +
      "}",
    ).unwrap()
    assert_eq(field(output_row(v), "a").nullable, nullable)
    if fn_name == "sum" && column == "decimal" {
      assert_true(
        field(output_row(v), "a").shape
        is @contract.Decimal(precision=38, scale=2),
      )
    }
    if fn_name == "first" {
      assert_true(
        indexed_obligation_copy(
          @relation_typing.pending_validations(v),
          @relation_typing.pending_validation_count(v),
          i => @relation_typing.pending_validation_at(v, i),
          (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
        ).any(p => p.kind is StableInputOrder),
      )
    }
  }
  for
    (fn_name, column, fill) in [
      ("sum", "amount", "\"0\""),
      ("count", "amount", "null"),
      ("sum", "decimal", "12.3"),
      ("sum", "decimal", "\"12.3\""),
      ("avg", "decimal", "null"),
      ("array_agg", "amount", "null"),
    ] {
    assert_true(
      pivot_check(
        "{\"index\":[],\"column\":\"status\",\"values\":[\"a\"],\"value\":\"" +
        column +
        "\",\"aggregate\":\"" +
        fn_name +
        "\",\"fill\":" +
        fill +
        "}",
      )
      is Err(_),
    )
  }
}

///|
test "pivot fill quotes reserved shapes and never recursively expands parameter holes" {
  for
    fill in [
      "{\"literal\":{\"$param\":\"absent\"}}", "{\"nested\":{\"$param\":\"absent\"}}",
      "{\"add\":[1,2]}",
    ] {
    let v = pivot_check(
      "{\"index\":[],\"column\":\"status\",\"values\":[\"a\"],\"value\":\"data\",\"aggregate\":\"first\",\"fill\":" +
      fill +
      "}",
    ).unwrap()
    assert_true(
      @relation_typing.pivot_fill(@relation_typing.pivot(v).unwrap())
      is Some(Literal(_, ..)),
    )
    assert_true(!field(output_row(v), "a").nullable)
  }
  for fill in ["{\"$param\":\"absent\"}", "{\"$param\":0}", "{\"$param\":null}"] {
    assert_true(
      pivot_check(
        "{\"index\":[],\"column\":\"status\",\"values\":[\"a\"],\"value\":\"data\",\"aggregate\":\"first\",\"fill\":" +
        fill +
        "}",
      )
      is Err(_),
    )
  }
}

///|
test "pivot fill parameters retain declaration evidence and bound validation" {
  let params = @parameter.read_declarations(
    Some(
      cursor(
        "{\"n\":{\"type\":\"number\"},\"maybe\":{\"type\":\"number\",\"nullable\":true},\"text\":{\"type\":\"string\"}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for name in ["n", "maybe"] {
    let v = pivot_check(
      "{\"index\":[],\"column\":\"status\",\"values\":[\"a\"],\"value\":\"amount\",\"aggregate\":\"sum\",\"fill\":{\"$param\":\"" +
      name +
      "\"}}",
      params=Some(params),
    ).unwrap()
    assert_eq(field(output_row(v), "a").nullable, name == "maybe")
    assert_true(
      indexed_obligation_copy(
        @relation_typing.pending_validations(v),
        @relation_typing.pending_validation_count(v),
        i => @relation_typing.pending_validation_at(v, i),
        (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
      ).any(p => p.kind is BoundFill(_)),
    )
  }
  assert_true(
    pivot_check(
      "{\"index\":[],\"column\":\"status\",\"values\":[\"a\"],\"value\":\"amount\",\"aggregate\":\"sum\",\"fill\":{\"$param\":\"text\"}}",
      params=Some(params),
    )
    is Err({ kind: InvalidFill, .. }),
  )
}

///|
test "pivot literal admission shares cumulative work text and node budgets" {
  let body = cursor(
    "{\"index\":[],\"column\":\"status\",\"values\":[\"a\",\"b\"],\"value\":\"data\",\"aggregate\":\"first\",\"fill\":{\"literal\":{\"text\":[\"abc\",\"é\"]}}}",
  )
  let v = check_row(Pivot, body, pivot_row(), None, limits()).unwrap()
  let exact = {
    ..limits(),
    max_work: @relation_typing.work_used(v),
    max_nodes: @relation_typing.nodes_used(v),
    max_text_bytes: @relation_typing.text_bytes_used(v),
  }
  assert_true(check_row(Pivot, body, pivot_row(), None, exact) is Ok(_))
  for
    l in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(check_row(Pivot, body, pivot_row(), None, l) is Err(_))
  }
}
