///|
fn cursor(text : String) -> @decode.Cursor {
  let source = @source.parse_json(text, {
    max_input_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 20000,
  }).unwrap()
  @decode.admit(source, tree_limits()).unwrap()
}

///|
fn tree_limits() -> @decode.Limits {
  {
    max_nodes: 100000,
    max_depth: 20000,
    max_string_bytes: 1000000,
    max_total_string_bytes: 1000000,
  }
}

///|
fn field(root : @decode.Cursor, name : String) -> @decode.Cursor {
  @decode.lookup(@decode.open_object(root).unwrap(), name).unwrap()
}

///|
fn declarations_for(root : @decode.Cursor) -> @parameter.Declarations {
  @parameter.read_declarations(Some(field(root, "params")), {
    max_parameters: 100,
    max_nodes: 100000,
    max_depth: 20000,
    max_text_bytes: 1000000,
  }).unwrap()
}

///|
fn occurrences(slot : @decode.Cursor) -> @expression.ParameterOccurrences {
  let e = @expression.admit(slot, {
    max_nodes: 100000,
    max_depth: 20000,
    max_text_bytes: 1000000,
    max_tokens: 100000,
    tree: tree_limits(),
  }).unwrap()
  @expression.collect_parameter_occurrences(e, max_work=100000).unwrap()
}

///|
fn limits(
  slots? : Int = 100,
  refs? : Int = 100,
  units? : Int = 100000,
) -> Limits {
  { max_slots: slots, max_references: refs, max_pointer_units: units, }
}

///|
fn rendered(index : Index, used? : Bool = false) -> String raise {
  let out = @encode.writer(1000000, 100000, 20000)
  if used {
    emit_used_declarations(index, out)
  } else {
    emit_references(index, out)
  }
  @encode.finish(out)
}

///|
test "reference index binds normalized source paths and annotation-free declarations" {
  let root = cursor(
    (
      #|{"params":{"z":{"type":"string"},"q":{"type":"number"},"p":{"type":"number","default":1,"meta":{"note":"not identity"}}},"body":{"z":"$q","a/~":"$p + $p","data":{"literal":{"$param":"hidden"}}}}
    ),
  )
  let body = field(root, "body")
  let declarations = declarations_for(root)
  let slots = [
    occurrences(field(body, "z")),
    occurrences(field(body, "a/~")),
    occurrences(field(body, "data")),
  ]
  let index = build(body, declarations, slots, limits()).unwrap()
  let expected =
    #|[{"name":"p","path":"/a~1~0/add/0","type":{"default":1,"type":"number"}},{"name":"p","path":"/a~1~0/add/1","type":{"default":1,"type":"number"}},{"name":"q","path":"/z","type":{"type":"number"}}]
  assert_eq(rendered(index), expected)
  assert_eq(
    rendered(index, used=true),
    (
      #|{"p":{"default":1,"type":"number"},"q":{"type":"number"}}
    ),
  )
  assert_eq(reference_count(index), 3)
  assert_true(physical_equal(source(index), body))
  assert_true(
    physical_equal(@parameter_references.declarations(index), declarations),
  )
  let first = slot_at(index, 0).unwrap()
  slots[0] = slots[1]
  assert_true(physical_equal(slot_at(index, 0).unwrap(), first))
  assert_true(reference_at(index, -1) is None)
  assert_true(reference_at(index, 3) is None)
  let global = build(root, declarations, [first], limits()).unwrap()
  assert_eq(reference_at(global, 0).unwrap().path, "/body/z")
  assert_eq(pointer_units(index), 26)
  let exact_slots = [
    slot_at(index, 0).unwrap(),
    slot_at(index, 1).unwrap(),
    slot_at(index, 2).unwrap(),
  ]
  assert_true(
    build(body, declarations, exact_slots, limits(slots=3, refs=3, units=26))
    is Ok(_),
  )
  assert_true(
    build(body, declarations, exact_slots, limits(slots=2)) is Err(SlotLimit),
  )
  assert_true(
    build(body, declarations, exact_slots, limits(refs=2))
    is Err(ReferenceLimit),
  )
  assert_true(
    build(body, declarations, exact_slots, limits(units=25))
    is Err(PointerLimit),
  )
  assert_true(
    build(body, declarations, exact_slots, limits(units=-1))
    is Err(InvalidLimits),
  )
}

///|
test "reference index rejects foreign source owners and duplicate locations" {
  let raw =
    #|{"params":{"p":{"type":"number"}},"a":{"x":"$p"},"b":{"x":"$p"},"unknown":"$missing"}
  let root = cursor(raw)
  let d = declarations_for(root)
  let a = field(root, "a")
  let ar = occurrences(field(a, "x"))
  assert_true(build(a, d, [ar, ar], limits()) is Err(DuplicateLocation("/x")))
  assert_true(
    build(a, d, [occurrences(field(field(root, "b"), "x"))], limits())
    is Err(ForeignExpression(0)),
  )
  assert_true(
    build(root, d, [occurrences(field(field(cursor(raw), "a"), "x"))], limits())
    is Err(ForeignExpression(0)),
  )
  assert_true(
    build(root, d, [occurrences(field(root, "unknown"))], limits())
    is Err(UnknownParameter("missing", "/unknown")),
  )
  let empty = build(root, d, [], limits(slots=0, refs=0, units=0)).unwrap()
  assert_eq(rendered(empty), "[]")
  assert_eq(rendered(empty, used=true), "{}")
  let scalar = cursor("\"$p\"")
  assert_true(
    build(scalar, d, [occurrences(scalar)], limits()) is Err(EmptyLocation),
  )
}

///|
test "reference index sorts pointers in UTF-16 order and escapes empty keys" {
  let root = cursor(
    (
      #|{"params":{"p":{"type":"number"}},"\ue000":"$p","\ud800\udc00":"$p","":"$p"}
    ),
  )
  let index = build(
    root,
    declarations_for(root),
    [
      occurrences(field(root, "")),
      occurrences(field(root, "𐀀")),
      occurrences(field(root, "")),
    ],
    limits(),
  ).unwrap()
  assert_eq(reference_at(index, 0).unwrap().path, "/")
  assert_eq(reference_at(index, 1).unwrap().path, "/𐀀")
  assert_eq(reference_at(index, 2).unwrap().path, "/")
  assert_eq(pointer_units(index), 6)
  let out = @encode.hashing_writer(100000, 1000, 100)
  emit_references(index, out)
  // Fixed UTF-8 preimage independently hashed with Node SHA-256.
  assert_eq(
    @encode.finish_hash(out),
    "b96620a256d17f7443ab793885c6c32e2edc6e664ac52c530f311a17987cfdc8",
  )
  for
    (bytes, nodes, depth, accepted) in [
      (155, 16, 3, true),
      (154, 16, 3, false),
      (155, 15, 3, false),
      (155, 16, 2, false),
    ] {
    for sink in 0..<3 {
      let out = match sink {
        0 => @encode.writer(bytes, nodes, depth)
        1 => @encode.measuring_writer(bytes, nodes, depth)
        _ => @encode.hashing_writer(bytes, nodes, depth)
      }
      let success = try {
        emit_references(index, out)
        match sink {
          0 => ignore(@encode.finish(out))
          1 => assert_eq(@encode.finish_measurement(out), 155)
          _ => ignore(@encode.finish_hash(out))
        }
        true
      } catch {
        _ => false
      }
      assert_eq(success, accepted)
    }
  }
}

///|
test "reference pointers remain bounded for deeply normalized expressions" {
  let root = cursor(
    "{\"params\":{\"p\":{\"type\":\"number\"}},\"expr\":\"" +
    "not ".repeat(2000) +
    "$p\"}",
  )
  let slots = [occurrences(field(root, "expr"))]
  let d = declarations_for(root)
  let index = build(root, d, slots, limits(units=8005)).unwrap()
  assert_eq(pointer_units(index), 8005)
  assert_eq(reference_at(index, 0).unwrap().path, "/expr" + "/not".repeat(2000))
  assert_true(build(root, d, slots, limits(units=8004)) is Err(PointerLimit))
}
