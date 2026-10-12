///|
fn protocol_test_start(
  wire : String,
  nodes : Array[ProtocolSchemaRule],
  root : Int,
  work : Int,
) -> ProtocolValidationCursor {
  let value = parse_contract_wire(wire, 10000, 1000, 16, data_keys=true).unwrap()
  start_protocol_validation(value, root, nodes, {
    remaining: work,
    max_wire_bytes: 10000,
    max_nodes: 1000,
    max_depth: 16,
  })
}

///|
fn protocol_test_finish(
  cursor : ProtocolValidationCursor,
  quantum : Int,
) -> (Bool, Int, Int) raise {
  let mut transitions = 0
  for _ in 0..<10000 {
    let (done, used) = cursor.advance(quantum)
    assert_true(used <= quantum)
    transitions += used
    if done {
      return (cursor.result, cursor.budget.remaining, transitions)
    }
    assert_true(used > 0)
  }
  fail("protocol validation did not terminate")
}

///|
test "protocol positional records preserve order exact length and independent work" {
  let nodes = [
    StringRule(Some("original"), [], 0, 0),
    BoolRule(Some(true)),
    TupleRule([0, 1]),
  ]
  for quantum in [1, 7, 64] {
    // One visit for the tuple and each field, plus the same indexed controls
    // as ordinary arrays: 3 * 2 + 2 transitions, independent of quantum.
    assert_eq(
      protocol_test_finish(
        protocol_test_start("[\"original\",true]", nodes, 2, 3),
        quantum,
      ),
      (true, 0, 8),
    )
    for
      wire in [
        "[true,\"original\"]", "[\"original\"]", "[\"original\",true,null]", "[\"original\",false]",
      ] {
      assert_eq(
        protocol_test_finish(protocol_test_start(wire, nodes, 2, 3), quantum).0,
        false,
      )
    }
    assert_eq(
      protocol_test_finish(
        protocol_test_start("[\"original\",true]", nodes, 2, 2),
        quantum,
      ).0,
      false,
    )
    let empty = protocol_test_start("[]", [TupleRule([])], 0, 1)
    assert_eq(protocol_test_finish(empty, quantum), (true, 0, 2))
  }
}

///|
test "protocol nested tuple cancellation retires frames without copying or refunding" {
  let nodes = [NumberRule, TupleRule([0, 0]), TupleRule([1, 1])]
  let cursor = protocol_test_start("[[1,2],[3,4]]", nodes, 2, 7)
  guard cursor.pending[0] is Visit(input, _) else { fail("input") }
  for _ in 0..<5 {
    assert_eq(cursor.advance(1).1, 1)
  }
  let spent = cursor.budget.remaining
  assert_true(spent < 7)
  cursor.cancel()
  cursor.cancel()
  assert_eq(cursor.pending.length(), 0)
  assert_eq(cursor.budget.remaining, spent)
  assert_eq(cursor.advance(1), (false, 0))
  assert_eq(@json.stringify_value(input, 10000, 1000, 16), "[[1,2],[3,4]]")
}

///|
test "protocol registered ceilings use exact scalar lengths and existing cursor budgets" {
  for quantum in [1, 7, 64] {
    let strings = [
      StringRule(None, [], 0, 0),
      StringCeilingRule(1),
      AllOfRule([0, 1]),
    ]
    let exact = protocol_test_start("\"😀\"", strings, 2, 3)
    assert_eq(protocol_test_finish(exact, quantum).0, true)
    assert_eq(exact.budget.remaining, 0)
    let short = protocol_test_start("\"😀\"", strings, 2, 2)
    assert_eq(protocol_test_finish(short, quantum).0, false)
    let long = protocol_test_start("\"😀x\"", strings, 2, 3)
    assert_eq(protocol_test_finish(long, quantum).0, false)
    let objects = [ObjectCeilingRule(1)]
    // JSON Schema object keywords do not impose a type. An explicit
    // ObjectRule in the generated conjunction separately enforces that type.
    assert_eq(
      protocol_test_finish(
        protocol_test_start("\"scalar\"", objects, 0, 1),
        quantum,
      ).0,
      true,
    )
    assert_eq(
      protocol_test_finish(
        protocol_test_start("{\"a\":1}", objects, 0, 1),
        quantum,
      ).0,
      true,
    )
    assert_eq(
      protocol_test_finish(
        protocol_test_start("{\"a\":1,\"b\":2}", objects, 0, 1),
        quantum,
      ).0,
      false,
    )
  }
}

///|
test "protocol array validation keeps independent rule budgets and quantum transitions" {
  let wire = "[" + Array::make(64, "7").join(",") + "]"
  let nodes = [NumberRule, ArrayRule(0, 0, false, -1)]
  for quantum in [1, 7, 64] {
    let exact = protocol_test_start(wire, nodes, 1, 65)
    // One rule per container/element; three control transitions per element
    // plus the container entry and final indexed-read boundary.
    assert_eq(protocol_test_finish(exact, quantum), (true, 0, 194))
    let short = protocol_test_start(wire, nodes, 1, 64)
    assert_eq(protocol_test_finish(short, quantum).0, false)
    assert_eq(short.budget.remaining, 0)
  }
}

///|
test "protocol object validation preserves required and closed member refusals" {
  let open = [NumberRule, ObjectRule([], ["z"], 0, 1, None, 0)]
  for quantum in [1, 7, 64] {
    assert_eq(
      protocol_test_finish(
        protocol_test_start("{\"a\":1,\"z\":2}", open, 1, 3),
        quantum,
      ).0,
      true,
    )
    let missing = protocol_test_start("{\"a\":1}", open, 1, 3)
    let (result, remaining, _) = protocol_test_finish(missing, quantum)
    assert_eq((result, remaining), (false, 2))
    let closed = [NumberRule, ObjectRule([("z", 0)], ["z"], -1, 1, None, 0)]
    let unknown = protocol_test_start("{\"a\":1,\"z\":2}", closed, 1, 3)
    let (result, remaining, _) = protocol_test_finish(unknown, quantum)
    assert_eq((result, remaining), (false, 2))
  }
}

///|
test "protocol alternatives negation and conditional keep their original budget edges" {
  let nodes : Array[ProtocolSchemaRule] = [
    NullRule,
    StringRule(None, [], 0, 0),
    NumberRule,
    AnyRule,
    OneOfRule([0, 1]),
    AnyOfRule([0, 1]),
    AllOfRule([2, 3]),
    NotRule(0),
    ConditionalRule(0, 2, 1),
    OneOfRule([2, 2]),
  ]
  for
    (wire, root, work, expected, remaining) in [
      ("\"ok\"", 4, 4, true, 1),
      ("\"ok\"", 4, 3, false, 0),
      ("\"ok\"", 5, 3, true, 0),
      ("7", 6, 3, true, 0),
      ("\"ok\"", 7, 3, true, 1),
      ("\"ok\"", 7, 2, false, 1),
      ("null", 7, 3, false, 1),
      ("\"ok\"", 8, 3, true, 0),
      ("null", 8, 3, false, 0),
      ("7", 9, 4, false, 1),
    ] {
    for quantum in [1, 7, 64] {
      let (actual, left, _) = protocol_test_finish(
        protocol_test_start(wire, nodes, root, work),
        quantum,
      )
      assert_eq((actual, left), (expected, remaining))
    }
  }
}

///|
test "protocol unique arrays keep raw data spelling and duplicate refusal" {
  let nodes = [StringRule(None, [], 0, 0), ArrayRule(0, 0, true, -1)]
  let distinct = protocol_test_start("[\"é\",\"e\u0301\"]", nodes, 1, 3)
  assert_eq(protocol_test_finish(distinct, 1).0, true)
  let duplicate = protocol_test_start("[\"é\",\"é\"]", nodes, 1, 3)
  let (result, remaining, _) = protocol_test_finish(duplicate, 1)
  assert_eq((result, remaining), (false, 2))
}

///|
test "protocol cancellation preserves the borrowed input and consumed rule work" {
  let nodes = [NumberRule, ArrayRule(0, 0, false, -1)]
  let cursor = protocol_test_start("[1,2,3,4,5,6,7,8]", nodes, 1, 9)
  guard cursor.pending[0] is Visit(input, _) else { fail("input") }
  for _ in 0..<10 {
    assert_eq(cursor.advance(1).1, 1)
  }
  let remaining = cursor.budget.remaining
  assert_true(remaining > 0 && remaining < 9)
  cursor.cancel()
  cursor.cancel()
  assert_eq(cursor.pending.length(), 0)
  assert_eq(cursor.budget.remaining, remaining)
  assert_eq(cursor.advance(1), (false, 0))
  assert_eq(@json.stringify_value(input, 10000, 1000, 16), "[1,2,3,4,5,6,7,8]")
}
