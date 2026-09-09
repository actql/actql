///|
test "open closed and required object reads preserve presence and spans" {
  let root = admit(
    node(
      @source.Object([
        entry("z", node(@source.Null, start=8), start=2),
        entry("a", node(@source.String(""), start=12), start=10),
        entry("unknown", node(@source.Bool(true), start=30), start=20),
      ]),
      start=1,
    ),
    budget(),
  ).unwrap()
  let object = open_object(root).unwrap()
  assert_true(field(object, "absent") is Missing)
  assert_true(field(object, "z") is ExplicitNull)
  assert_true(field(object, "a") is Present(_))
  assert_true(lookup(object, "absent") is None)
  assert_true(is_null(lookup(object, "z").unwrap()))
  assert_eq(text(required(object, "a").unwrap()), Ok(""))
  let missing = rejection(required(object, "missing/~"))
  assert_eq(missing.kind, MissingField)
  assert_eq(missing.path, [@source.Key("missing/~")])
  assert_eq(missing.span, mark(1))
  let null = rejection(required(object, "z"))
  assert_eq(null.kind, UnexpectedNull)
  assert_eq(null.span, mark(8))
  let unknown = rejection(closed_object(root, ["z", "a"]))
  assert_eq(unknown.kind, UnknownField)
  assert_eq(unknown.path, [@source.Key("unknown")])
  assert_eq(unknown.span, mark(20))
  assert_eq(rejection(closed_object(root, [])).path, [@source.Key("z")])
  let allowed = ["z", "a", "unknown", "not-required"]
  let closed = closed_object(root, allowed).unwrap()
  allowed[0] = "changed"
  assert_true(field(closed, "z") is ExplicitNull)
  assert_true(lookup(closed, "not-required") is None)
  guard view(root) is ObjectValue(projected) else {
    fail("expected object view")
  }
  assert_eq(text(required(projected, "a").unwrap()), Ok(""))
}

///|
test "primitive readers do not coerce or add numeric domain validity to admission" {
  assert_true(view(owned(@source.Null)) is NullValue)
  assert_true(view(owned(@source.Bool(true))) is BoolValue(true))
  assert_true(view(owned(@source.Number(1.5))) is NumberValue(1.5))
  assert_true(view(owned(@source.String("x"))) is TextValue("x"))
  assert_eq(boolean(owned(@source.Bool(false))), Ok(false))
  assert_eq(text(owned(@source.String(" true "))), Ok(" true "))
  let null = owned(@source.Null)
  assert_eq(rejection(text(null)).kind, WrongType)
  assert_eq(rejection(boolean(null)).kind, WrongType)
  assert_eq(rejection(finite_number(null)).kind, WrongType)
  assert_eq(rejection(safe_integer(null)).kind, WrongType)
  assert_eq(rejection(int32(null)).kind, WrongType)
  assert_eq(rejection(decimal_int64(null)).kind, WrongType)
  assert_eq(rejection(open_object(null)).kind, WrongType)
  assert_eq(rejection(closed_object(null, [])).kind, WrongType)
  assert_eq(rejection(elements(null)).kind, WrongType)
  assert_eq(rejection(object_field_names(null)).kind, WrongType)
  assert_eq(rejection(safe_integer(owned(@source.String("1")))).kind, WrongType)
  assert_eq(rejection(boolean(owned(@source.Number(1)))).kind, WrongType)
  for value in [1.0 / 0.0, -1.0 / 0.0, 0.0 / 0.0] {
    let cursor = owned(@source.Number(value))
    assert_true(view(cursor) is NumberValue(_))
    assert_eq(rejection(finite_number(cursor)).kind, OutOfRange)
    assert_eq(rejection(safe_integer(cursor)).kind, OutOfRange)
    assert_eq(rejection(int32(cursor)).kind, OutOfRange)
  }
  let negative_zero = owned(@source.Number(-0.0))
  assert_eq(1.0 / finite_number(negative_zero).unwrap(), -1.0 / 0.0)
  assert_eq(safe_integer(negative_zero), Ok(0L))
  assert_eq(int32(negative_zero), Ok(0))
}

///|
test "numeric readers enforce representation bounds without narrowing other fields" {
  for value in [9007199254740991.0, -9007199254740991.0] {
    assert_eq(safe_integer(owned(@source.Number(value))), Ok(value.to_int64()))
  }
  for value in [9007199254740992.0, -9007199254740992.0, 1.5] {
    assert_eq(finite_number(owned(@source.Number(value))), Ok(value))
    assert_eq(
      rejection(safe_integer(owned(@source.Number(value)))).kind,
      OutOfRange,
    )
  }
  assert_eq(int32(owned(@source.Number(2147483647))), Ok(2147483647))
  assert_eq(int32(owned(@source.Number(-2147483648))), Ok(-2147483648))
  for value in [2147483648.0, -2147483649.0, 0.5] {
    assert_eq(rejection(int32(owned(@source.Number(value)))).kind, OutOfRange)
  }
  assert_eq(
    decimal_int64(owned(@source.String("9223372036854775807"))),
    Ok(9223372036854775807L),
  )
  assert_eq(
    decimal_int64(owned(@source.String("-9223372036854775808"))),
    Ok(-9223372036854775808L),
  )
  for value in ["", "01", "-0", " 1", "1.0", "9223372036854775808", "١"] {
    assert_eq(
      rejection(decimal_int64(owned(@source.String(value)))).kind,
      InvalidDecimal,
    )
  }
}

///|
test "parsed source integrates without conflating normalization with structural admission" {
  let source = @source.parse_json("{\"e\\u0301\":[true,null,3]}", {
    max_input_bytes: 100,
    max_nodes: 10,
    max_depth: 2,
  }).unwrap()
  let root = admit(source, budget()).unwrap()
  let object = closed_object(root, ["é"]).unwrap()
  let children = elements(required(object, "é").unwrap()).unwrap()
  assert_eq(boolean(children[0]), Ok(true))
  assert_true(is_null(children[1]))
  assert_eq(safe_integer(children[2]), Ok(3L))
  assert_eq(rejection(text(children[2])).path, [
    @source.Key("é"),
    @source.Index(2),
  ])
}
