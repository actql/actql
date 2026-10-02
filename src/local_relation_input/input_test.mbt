///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn caps() -> Limits {
  { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }
}

///|
test "local Relation declarations preserve open and complete field evidence" {
  let short = read(cursor("\"relation\""), caps()).unwrap()
  let rows = @carrier.relation_rows(carrier(short)).unwrap()
  assert_eq(@carrier.field_set(rows), Open)
  assert_eq(@carrier.field_count(rows), 0)
  let source = cursor(
    "{\"carrier\":\"relation\",\"expected_columns\":[\"id\",\"name\"]}",
  )
  let value = read(source, caps()).unwrap()
  assert_true(physical_equal(@local_relation_input.source(value), source))
  let rows = @carrier.relation_rows(carrier(value)).unwrap()
  assert_eq(@carrier.field_set(rows), Open)
  assert_true(
    @carrier.lookup(rows, Unqualified("id")) is Present({ contract: None, .. }),
  )
  assert_true(@carrier.lookup(rows, Unqualified("extra")) is Unknown)
  let names = expected_columns(value)
  names.clear()
  assert_eq(expected_columns(value), ["id", "name"])
  let empty = read(
    cursor("{\"carrier\":\"relation\",\"expected_columns\":[],\"schema\":{}}"),
    caps(),
  ).unwrap()
  let rows = @carrier.relation_rows(carrier(empty)).unwrap()
  assert_eq(@carrier.field_set(rows), Closed)
  assert_true(@carrier.lookup(rows, Unqualified("extra")) is Absent)
  assert_eq(@schema.field_count(@carrier.complete_schema(rows).unwrap()), 0)
}

///|
test "local schema uses author contracts and conditional primary key evidence" {
  let value = read(
    cursor(
      (
        #|{"carrier":"relation","schema":{"id":{"type":"number","nullable":false},"amount":{"type":"decimal","precision":4,"scale":2,"nullable":true},"items":{"type":"array","nullable":false,"items":{"type":"object","nullable":false,"fields":{}}}},"expected_columns":["amount"],"primary_key":["id"],"meta":{"note":{"actql_nested":true}}}
      ),
    ),
    caps(),
  ).unwrap()
  let rows = @carrier.relation_rows(carrier(value)).unwrap()
  let schema = @carrier.complete_schema(rows).unwrap()
  assert_eq(@schema.field_count(schema), 3)
  let amount = @schema.lookup(schema, Unqualified("amount")).unwrap()
  assert_true(amount.shape is @contract.Decimal(precision=4, scale=2))
  assert_true(amount.nullable)
  let key = primary_key(value).unwrap()
  assert_eq(@evidence.key_field_count(key), 1)
  assert_true(!@evidence.key_pending(key).is_empty())
  assert_true(first_by_order(value) is None)
  let unknown = read(
    cursor("{\"carrier\":\"relation\",\"primary_key\":[\"id\"]}"),
    caps(),
  ).unwrap()
  assert_true(primary_key(unknown) is Some(_))
  assert_true(
    @carrier.complete_schema(@carrier.relation_rows(carrier(unknown)).unwrap())
    is None,
  )
}

///|
test "local input rejects malformed declarations and incompatible assertions" {
  for
    text in [
      "{}", "{\"expected_columns\":[\"id\"]}", "{\"carrier\":\"relation\",\"schema_ref\":\"x\"}",
      "{\"carrier\":\"relation\",\"expected_columns\":[\"id\",\"id\"]}", "{\"carrier\":\"relation\",\"expected_columns\":[\"\"]}",
      "{\"carrier\":\"relation\",\"schema\":{},\"expected_columns\":[\"id\"]}", "{\"carrier\":\"relation\",\"schema\":null}",
      "{\"carrier\":\"relation\",\"primary_key\":[]}", "{\"carrier\":\"relation\",\"schema\":{},\"primary_key\":[\"id\"]}",
      "{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":true}},\"primary_key\":[\"id\"]}",
      "{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"json\",\"nullable\":false}},\"primary_key\":[\"id\"]}",
      "{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\"}}}", "{\"carrier\":\"relation\",\"meta\":{}}",
      "{\"carrier\":\"relation\",\"meta\":{\"actql_reserved\":1}}",
    ] {
    assert_true(read(cursor(text), caps()) is Err(_))
  }
  assert_true(
    read(cursor("\"events\""), caps()) is Err(UnsupportedCarrier("events")),
  )
}

///|
test "first-by-order retains authored terms without proving normalization" {
  let value = read(
    cursor(
      (
        #|{"carrier":"relation","primary_key":["id"],"duplicates":{"first_by_order":{"order_by":[{"time":"desc"},{"time":"desc"}]}}}
      ),
    ),
    caps(),
  ).unwrap()
  let terms = first_by_order(value).unwrap()
  assert_eq(terms.length(), 2)
  assert_eq(terms[0].direction, Desc)
  assert_eq(terms[0].nulls, Last)
  terms.clear()
  assert_eq(first_by_order(value).unwrap().length(), 2)
  for
    text in [
      "{\"carrier\":\"relation\",\"duplicates\":\"first_by_order\"}", "{\"carrier\":\"relation\",\"duplicates\":{\"first_by_order\":{\"order_by\":[]}}}",
      "{\"carrier\":\"relation\",\"schema\":{},\"duplicates\":{\"first_by_order\":{\"order_by\":[{\"x\":\"asc\"}]}}}",
      "{\"carrier\":\"relation\",\"schema\":{\"x\":{\"type\":\"json\",\"nullable\":false}},\"duplicates\":{\"first_by_order\":{\"order_by\":[{\"x\":\"asc\"}]}}}",
    ] {
    assert_true(read(cursor(text), caps()) is Err(_))
  }
}

///|
test "local input source budgets cover all fields together" {
  let source = cursor(
    "{\"carrier\":\"relation\",\"expected_columns\":[\"id\"]}",
  )
  let exact : Limits = { max_nodes: 4, max_depth: 2, max_text_bytes: 33, }
  assert_true(read(source, exact) is Ok(_))
  for
    limit in [
      { ..exact, max_nodes: 3, },
      { ..exact, max_depth: 1, },
      { ..exact, max_text_bytes: 32, },
      { ..exact, max_nodes: -1, },
    ] {
    assert_true(read(source, limit) is Err(_))
  }
}

///|
test "metadata retains string values but cannot smuggle invalid numbers through declarations" {
  let span = @source.parse_json("null", {
      max_input_bytes: 4,
      max_nodes: 1,
      max_depth: 0,
    }).unwrap().span
  for
    invalid in [
      @source.Number(-0.0),
      @source.Number(1.0 / 0.0),
      @source.String("e\u0301"),
      @source.String("a\r\nb"),
    ] {
    let raw : @source.Node = {
      span,
      value: @source.Object([
        {
          key: "carrier",
          key_span: span,
          value: { span, value: @source.String("relation"), },
        },
        {
          key: "meta",
          key_span: span,
          value: {
            span,
            value: @source.Object([
              { key: "note", key_span: span, value: { span, value: invalid, }, },
            ]),
          },
        },
      ]),
    }
    let owned = @decode.admit(raw, {
      max_nodes: 20,
      max_depth: 5,
      max_string_bytes: 100,
      max_total_string_bytes: 100,
    }).unwrap()
    match invalid {
      @source.String(_) => assert_true(read(owned, caps()) is Ok(_))
      _ => assert_true(read(owned, caps()) is Err(_))
    }
  }
}
