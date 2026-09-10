///|
fn row_checked(
  op : @relation_typing.Operation,
  text : String,
) -> @relation_typing.CheckedOperation {
  check_row(op, cursor(text), input(), None, limits()).unwrap()
}

///|
test "row operations preflight deep unused fields and bounded wide key lists" {
  let mut nested = @contract.primitive(NumberType, nullable=false)
  for _ in 0..<10000 {
    nested = @contract.array_contract(nested, nullable=false).unwrap()
  }
  let row = @contract.object_contract(
    [
      ("id", @contract.primitive(NumberType, nullable=false)),
      ("unused", nested),
    ],
    nullable=false,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let cases : Array[(@relation_typing.Operation, String)] = [
    (Sort, "[]"),
    (Take, "1"),
    (Distinct, "[\"id\"]"),
    (DedupeRows, "{\"by\":[],\"order_by\":[{\"id\":\"asc\"}]}"),
  ]
  for (op, text) in cases {
    assert_true(check_row(op, cursor(text), row, None, limits()) is Ok(_))
    assert_true(
      check_row(op, cursor(text), row, None, { ..limits(), max_depth: 10000, })
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
  let text = "[" + "{\"id\":\"asc\"},".repeat(9999) + "{\"id\":\"asc\"}]"
  let checked = row_checked(Sort, text)
  assert_true(
    @relation_typing.row_operation(checked) is Some(Sort(terms)) &&
    terms.length() == 10000,
  )
  let text = "{\"by\":[" +
    "\"id\",".repeat(9999) +
    "\"id\"],\"order_by\":[{\"id\":\"asc\"}]}"
  let checked = row_checked(DedupeRows, text)
  assert_true(
    @relation_typing.row_operation(checked) is Some(DedupeRows(by~, ..)) &&
    by.length() == 10000,
  )
}

///|
test "empty sort retains source and schema without supplying order evidence" {
  let checked = row_checked(Sort, "[]")
  assert_true(
    @relation_typing.row_operation(checked) is Some(Sort(terms)) &&
    terms.is_empty(),
  )
  assert_true(@relation_typing.pending_validations(checked).is_empty())
  assert_true(
    @contract.type_equal(input_row(checked), output_row(checked), 1000),
  )
  assert_true(@decode.view(@relation_typing.source(checked)) is ArrayValue(_))
  let empty = schema("{}")
  let cases : Array[(@relation_typing.Operation, String)] = [
    (Sort, "[]"),
    (Distinct, "true"),
    (Take, "1"),
  ]
  for (op, text) in cases {
    assert_true(check_row(op, cursor(text), empty, None, limits()) is Ok(_))
  }
  assert_true(
    check_row(Distinct, cursor("[]"), empty, None, limits())
    is Err({ kind: EmptyBody, .. }),
  )
}

///|
test "sort retains repeated terms and exact null placement without proving total order" {
  let checked = row_checked(
    Sort,
    "[{\"flag\":\"desc\"},{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"first\"},{\"id\":\"desc\"}]",
  )
  let terms = match @relation_typing.row_operation(checked).unwrap() {
    Sort(terms) => terms
    _ => abort("sort")
  }
  assert_eq(terms.length(), 3)
  assert_eq(terms[0].nulls, @order.Last)
  assert_eq(terms[1].nulls, @order.First)
  assert_eq(terms[0].direction, @order.Desc)
  assert_true(!terms[0].explicit_nulls && terms[1].explicit_nulls)
  assert_eq(terms[1].field, @schema.Unqualified("id"))
  assert_eq(
    @relation_typing.pending_validations(checked)[0].kind,
    SortOrderCompletion,
  )
  terms.clear()
  assert_true(
    @relation_typing.row_operation(checked) is Some(Sort(terms)) &&
    terms.length() == 3,
  )
}

///|
test "take retains canonical count and offset separately without summing or binding them" {
  for text in ["7", "{\"count\":7}", "{\"count\":7,\"offset\":0}"] {
    let checked = row_checked(Take, text)
    assert_true(
      @relation_typing.row_operation(checked)
      is Some(Take(count=Literal(7L), offset=Literal(0L))),
    )
    assert_eq(
      @relation_typing.pending_validations(checked)[0].kind,
      StableInputOrder,
    )
  }
  let checked = row_checked(
    Take,
    "{\"count\":9007199254740991,\"offset\":9007199254740991}",
  )
  assert_true(
    @relation_typing.row_operation(checked)
    is Some(
      Take(count=Literal(9007199254740991L), offset=Literal(9007199254740991L))
    ),
  )
  for
    text in [
      "null", "true", "\"1\"", "{}", "{\"count\":1,\"limit\":2}", "{\"count\":1,\"offset\":null}",
      "{\"$param\":\"n\",\"offset\":0}",
    ] {
    assert_true(
      check_row(Take, cursor(text), input(), None, limits()) is Err(_),
    )
  }
  for n in [-1.0, -0.0, 0.5, 9007199254740992.0, 1.0 / 0.0, 0.0 / 0.0] {
    let source = cursor("null")
    let s = @decode.admit(
      {
        value: @source.Object([
          {
            key: "count",
            key_span: @decode.cursor_span(source),
            value: {
              value: @source.Number(1.0),
              span: @decode.cursor_span(source),
            },
          },
          {
            key: "offset",
            key_span: @decode.cursor_span(source),
            value: {
              value: @source.Number(n),
              span: @decode.cursor_span(source),
            },
          },
        ]),
        span: @decode.cursor_span(source),
      },
      {
        max_nodes: 100,
        max_depth: 10,
        max_string_bytes: 100,
        max_total_string_bytes: 100,
      },
    ).unwrap()
    assert_true(
      check_row(Take, s, input(), None, limits())
      is Err({ kind: InvalidCount, .. }),
    )
  }
}

///|
test "take parameter declarations remain symbolic with separate bound value obligations" {
  let params = @parameter.read_declarations(
    Some(
      cursor(
        "{\"n\":{\"type\":\"number\",\"nullable\":true,\"default\":null},\"off\":{\"type\":\"number\",\"default\":2},\"text\":{\"type\":\"string\"}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let checked = check_row(
    Take,
    cursor("{\"count\":{\"$param\":\"n\"},\"offset\":{\"$param\":\"off\"}}"),
    input(),
    Some(params),
    limits(),
  ).unwrap()
  assert_true(
    @relation_typing.row_operation(checked)
    is Some(Take(count=Parameter("n"), offset=Parameter("off"))),
  )
  let pending = @relation_typing.pending_validations(checked)
  assert_eq(pending.map(p => p.kind), [
    BoundInteger(name="n", minimum=1L),
    BoundInteger(name="off", minimum=0L),
    StableInputOrder,
  ])
  assert_eq(@decode.cursor_path(pending[0].source), [@source.Key("count")])
  pending.clear()
  assert_eq(@relation_typing.pending_validations(checked).length(), 3)
  for
    text in [
      "{\"$param\":\"n\"}", "{\"count\":{\"$param\":\"n\"},\"offset\":{\"$param\":\"n\"}}",
    ] {
    assert_true(
      check_row(Take, cursor(text), input(), Some(params), limits()) is Ok(_),
    )
  }
  assert_true(
    check_row(
      Take,
      cursor("{\"$param\":\"text\"}"),
      input(),
      Some(params),
      limits(),
    )
    is Err({ kind: InvalidCount, .. }),
  )
  assert_true(
    check_row(
      Take,
      cursor("{\"$param\":\"absent\"}"),
      input(),
      Some(params),
      limits(),
    )
    is Err({ kind: UnknownParameter("absent"), .. }),
  )
}

///|
test "equality domains differ from order domains and whole-row distinct" {
  let types = [
    ("{\"type\":\"number\",\"nullable\":true}", true, true),
    ("{\"type\":\"string\",\"nullable\":false}", true, true),
    ("{\"type\":\"boolean\",\"nullable\":false}", true, true),
    (
      "{\"type\":\"decimal\",\"precision\":38,\"scale\":10,\"nullable\":false}",
      true, true,
    ),
    ("{\"type\":\"date\",\"nullable\":false}", true, true),
    ("{\"type\":\"timestamp\",\"nullable\":false}", true, true),
    (
      "{\"type\":\"resource_ref\",\"resource_kind\":\"r\",\"nullable\":true}", true,
      false,
    ),
    ("{\"type\":\"artifact_ref\",\"nullable\":false}", true, false),
    ("{\"type\":\"json\",\"nullable\":false}", false, false),
    ("{\"type\":\"object\",\"fields\":{},\"nullable\":false}", false, false),
    (
      "{\"type\":\"array\",\"items\":{\"type\":\"number\",\"nullable\":false},\"nullable\":false}",
      false, false,
    ),
    ("{\"type\":\"vector\",\"dimensions\":3,\"nullable\":false}", false, false),
  ]
  for (type_, comparable, orderable) in types {
    let row = schema(
      "{\"x\":" + type_ + ",\"id\":{\"type\":\"number\",\"nullable\":false}}",
    )
    assert_true(
      check_row(Distinct, cursor("true"), row, None, limits()) is Ok(_),
    )
    assert_eq(
      check_row(Distinct, cursor("[\"x\"]"), row, None, limits()) is Ok(_),
      comparable,
    )
    assert_eq(
      check_row(
        DedupeRows,
        cursor("{\"by\":[\"x\",\"x\"],\"order_by\":[{\"id\":\"asc\"}]}"),
        row,
        None,
        limits(),
      )
      is Ok(_),
      comparable,
    )
    assert_eq(
      check_row(Sort, cursor("[{\"x\":\"asc\"}]"), row, None, limits()) is Ok(_),
      orderable,
    )
    assert_true(
      check_row(
        DedupeRows,
        cursor("{\"by\":[],\"order_by\":[{\"id\":\"asc\"}]}"),
        row,
        None,
        limits(),
      )
      is Ok(_),
    )
  }
}

///|
test "dedupe retains all rows fields and repeated keys without adding evidence" {
  let checked = row_checked(
    DedupeRows,
    "{\"by\":[\"id\",\"id\"],\"order_by\":[{\"amount\":\"desc\"}]}",
  )
  assert_true(
    @contract.type_equal(input_row(checked), output_row(checked), 1000),
  )
  assert_eq(@relation_typing.pending_validations(checked).map(p => p.kind), [
    FailOnTopTie,
  ])
  let by = match @relation_typing.row_operation(checked).unwrap() {
    DedupeRows(by~, ..) => by
    _ => abort("dedupe")
  }
  assert_eq(by.map(k => k.field), [
    @schema.Unqualified("id"),
    @schema.Unqualified("id"),
  ])
  by.clear()
  assert_true(
    @relation_typing.row_operation(checked) is Some(DedupeRows(by~, ..)) &&
    by.length() == 2,
  )
  let global = row_checked(
    DedupeRows,
    "{\"by\":[],\"order_by\":[{\"id\":\"asc\"}]}",
  )
  assert_true(
    @relation_typing.row_operation(global) is Some(DedupeRows(by~, ..)) &&
    by.is_empty(),
  )
  assert_eq(@relation_typing.pending_validations(global).map(p => p.kind), [
    FailOnTopTie,
  ])
}

///|
test "row operations retain exact source paths on failed field and count checks" {
  let cases : Array[
    (@relation_typing.Operation, String, Array[@source.PathSegment]),
  ] = [
    (
      Sort,
      "[{\"field\":\"missing\",\"dir\":\"asc\",\"nulls\":\"last\"}]",
      [@source.Index(0), Key("field")],
    ),
    (Distinct, "[\"id\",\"missing\"]", [@source.Index(1)]),
    (
      DedupeRows,
      "{\"by\":[\"missing\"],\"order_by\":[{\"id\":\"asc\"}]}",
      [@source.Key("by"), Index(0)],
    ),
    (Take, "{\"count\":1,\"offset\":-1}", [@source.Key("offset")]),
  ]
  for (op, text, path) in cases {
    let issue = check_row(op, cursor(text), input(), None, limits()).unwrap_err()
    assert_eq(issue.path, path)
    assert_eq(issue.span.source_path, "relation.aql")
    assert_eq(issue.range, None)
  }
}

///|
test "row operation budgets admit exact consumption and reject each shortage" {
  let cases : Array[(@relation_typing.Operation, String)] = [
    (Sort, "[]"),
    (Sort, "[{\"id\":\"asc\"}]"),
    (Take, "{\"count\":1,\"offset\":2}"),
    (Distinct, "true"),
    (Distinct, "[\"id\",\"amount\"]"),
    (DedupeRows, "{\"by\":[],\"order_by\":[{\"id\":\"asc\"}]}"),
  ]
  for (op, text) in cases {
    let checked = row_checked(op, text)
    let exact : @relation_typing.Limits = {
      ..limits(),
      max_work: @relation_typing.work_used(checked),
      max_nodes: @relation_typing.nodes_used(checked),
      max_text_bytes: @relation_typing.text_bytes_used(checked),
      max_tokens: 0,
    }
    assert_true(check_row(op, cursor(text), input(), None, exact) is Ok(_))
    for
      cap in [
        { ..exact, max_work: exact.max_work - 1, },
        { ..exact, max_nodes: exact.max_nodes - 1, },
        { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
        { ..exact, max_depth: 0, },
      ] {
      assert_true(
        check_row(op, cursor(text), input(), None, cap)
        is Err({ kind: BudgetExceeded, .. }),
      )
    }
  }
}
