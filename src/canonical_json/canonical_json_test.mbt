///|
test "large canonical CID matches text serialization without changing preimages" {
  let input = Json::string("é😀\n\"\\".repeat(200000))
  let value = @canonical_json.from_json(input, 1, 0, 2000000)
  let size = @canonical_json.measure_value(value, 4000000, 1, 0)
  let text = @canonical_json.stringify_value(value, size, 1, 0)
  assert_eq(
    @canonical_json.cid_value(value, size, 1, 0),
    "sha256:" + @sha256.text_hex(text).unwrap(),
  )
  let rejected = try {
    ignore(@canonical_json.cid_value(value, size - 1, 1, 0))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "normalization and ordering precede canonical emission" {
  let input = @json.parse(
    "{\"2\":\"e\\u0301\\r\\n\",\"10\":\"x\\ry\",\"z\":null,\"a\":true}",
  )
  let value = @canonical_json.from_json(input, 5, 1, 20)
  assert_eq(
    @canonical_json.stringify_value(value, 100, 5, 1),
    "{\"10\":\"x\\ny\",\"2\":\"é\\n\",\"a\":true,\"z\":null}",
  )
}

///|
test "normalized key collisions include NFC and newline folding" {
  for
    text in [
      "{\"é\":1,\"e\\u0301\":2}", "{\"a\\r\\n\":1,\"a\\n\":2}", "{\"a\\r\":1,\"a\\n\":2}",
      "{\"가\":1,\"\\u1100\\u1161\":2}",
    ] {
    let rejected = try {
      ignore(@canonical_json.from_json(@json.parse(text), 10, 2, 100))
      false
    } catch {
      @canonical_json.DuplicateKey(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "invalid numbers and UTF16 are rejected without replacement" {
  for number in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0, -0.0] {
    let rejected = try {
      ignore(@canonical_json.from_json(Json::number(number), 1, 0, 0))
      false
    } catch {
      @canonical_json.InvalidNumber => true
      _ => false
    }
    assert_true(rejected)
  }
  for units in [[0xd800], [0xdc00], [0xd800, 65]] {
    let bad = String::from_array(units.map(x => x.unsafe_to_char()))
    for as_key in [false, true] {
      let input = if as_key {
        Json::object(Map([(bad, Json::null())]))
      } else {
        Json::string("😀" + bad)
      }
      let rejected = try {
        ignore(@canonical_json.from_json(input, 2, 1, 10))
        false
      } catch {
        @canonical_json.InvalidUnicode(offset) =>
          offset == (if as_key { 0 } else { 2 })
        _ => false
      }
      assert_true(rejected)
    }
  }
}

///|
test "input node depth and raw UTF16 budgets have exact boundaries" {
  let input = @json.parse("{\"e\\u0301\":[\"😀\\r\\n\"]}")
  // Three nodes, two containers, six UTF-16 units before normalization.
  let admitted = @canonical_json.from_json(input, 3, 2, 6)
  assert_eq(
    @canonical_json.stringify_value(admitted, 100, 3, 2),
    "{\"é\":[\"😀\\n\"]}",
  )
  for
    limits in [
      (2, 2, 6),
      (3, 1, 6),
      (3, 2, 5),
      (0, 2, 6),
      (3, -1, 6),
      (3, 2, -1),
    ] {
    let (nodes, depth, units) = limits
    let rejected = try {
      ignore(@canonical_json.from_json(input, nodes, depth, units))
      false
    } catch {
      @canonical_json.InputLimit => true
      _ => false
    }
    assert_true(rejected)
  }
  for empty in [Json::array([]), Json::object(Map([]))] {
    ignore(@canonical_json.from_json(empty, 1, 1, 0))
    let rejected = try {
      ignore(@canonical_json.from_json(empty, 1, 0, 0))
      false
    } catch {
      @canonical_json.InputLimit => true
      _ => false
    }
    assert_true(rejected)
  }
  ignore(@canonical_json.from_json(Json::null(), 1, 0, 0))
}

///|
test "raw input units and normalized output bytes are independent" {
  // NFC expands U+0344 into two combining scalars.
  let value = @canonical_json.from_json(Json::string("\u0344"), 1, 0, 1)
  assert_eq(@canonical_json.stringify_value(value, 6, 1, 0), "\"\u0308\u0301\"")
  assert_eq(@canonical_json.measure_value(value, 6, 1, 0), 6)
  let rejected = try {
    ignore(@canonical_json.stringify_value(value, 4, 1, 0))
    false
  } catch {
    @encode.OutputLimit => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "input size is rejected before normalizing strings and keys" {
  let oversized = "e\u0301".repeat(10000)
  for
    input in [
      Json::string(oversized),
      Json::object(Map([(oversized, Json::null())])),
    ] {
    let rejected = try {
      ignore(@canonical_json.from_json(input, 2, 1, 10))
      false
    } catch {
      @canonical_json.InputLimit => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "canonical trees own their collections and detached access cannot mutate them" {
  let children : Array[Json] = [Json::number(1.0)]
  let object = Map([("a", Json::array(children))])
  let value = @canonical_json.from_json(Json::object(object), 3, 2, 1)
  children[0] = Json::number(9.0)
  object["a"] = Json::null()
  guard value is @canonical_json.Object(fields) else { fail("expected object") }
  let detached = @canonical_json.array_values(fields)
  guard detached[0].1 is @canonical_json.Array(items) else {
    fail("expected array")
  }
  let detached_items = @canonical_json.array_values(items)
  detached_items.clear()
  detached.clear()
  assert_eq(@canonical_json.stringify_value(value, 9, 3, 2), "{\"a\":[1]}")
}

///|
test "deep admission serialization measurement and CID avoid recursive traversal" {
  let depth = 10000
  let mut input = Json::null()
  for _ in 0..<depth {
    input = Json::array([input])
  }
  let value = @canonical_json.from_json(input, depth + 1, depth, 0)
  let text = "[".repeat(depth) + "null" + "]".repeat(depth)
  let bytes = depth * 2 + 4
  assert_eq(
    @canonical_json.stringify_value(value, bytes, depth + 1, depth),
    text,
  )
  assert_eq(
    @canonical_json.measure_value(value, bytes, depth + 1, depth),
    bytes,
  )
  let expected = @sha256.text_hex(text).unwrap()
  assert_eq(
    @canonical_json.cid_value(value, bytes, depth + 1, depth),
    "sha256:" + expected,
  )
  let rejected = try {
    ignore(@canonical_json.from_json(input, depth + 1, depth - 1, 0))
    false
  } catch {
    @canonical_json.InputLimit => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "cycles stop at a budget and shared subtrees count at each occurrence" {
  let children : Array[Json] = []
  let cyclic = Json::array(children)
  children.push(cyclic)
  for limits in [(50, 100), (100, 50)] {
    let rejected = try {
      ignore(@canonical_json.from_json(cyclic, limits.0, limits.1, 0))
      false
    } catch {
      @canonical_json.InputLimit => true
      _ => false
    }
    assert_true(rejected)
  }
  children.clear()
  let shared = Json::array([Json::string("x")])
  let tree = Json::array([shared, shared])
  ignore(@canonical_json.from_json(tree, 5, 2, 2))
  for limits in [(4, 2), (5, 1)] {
    let rejected = try {
      ignore(@canonical_json.from_json(tree, limits.0, 2, limits.1))
      false
    } catch {
      @canonical_json.InputLimit => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "every standalone output requires exact byte node and depth budgets" {
  let value = @canonical_json.from_json(
    @json.parse("{\"a\":[\"😀\"]}"),
    3,
    2,
    3,
  )
  let text = "{\"a\":[\"😀\"]}"
  let bytes = 14
  assert_eq(@canonical_json.stringify_value(value, bytes, 3, 2), text)
  assert_eq(@canonical_json.measure_value(value, bytes, 3, 2), bytes)
  for limits in [(bytes - 1, 3, 2), (bytes, 2, 2), (bytes, 3, 1)] {
    for operation in [0, 1, 2] {
      let rejected = try {
        match operation {
          0 =>
            ignore(
              @canonical_json.stringify_value(
                value,
                limits.0,
                limits.1,
                limits.2,
              ),
            )
          1 =>
            ignore(
              @canonical_json.measure_value(value, limits.0, limits.1, limits.2),
            )
          _ =>
            ignore(
              @canonical_json.cid_value(value, limits.0, limits.1, limits.2),
            )
        }
        false
      } catch {
        @encode.OutputLimit => true
        _ => false
      }
      assert_true(rejected)
    }
  }
}

///|
test "canonical emission charges parent budgets and preserves poisoning" {
  let value = @canonical_json.from_json(Json::array([Json::null()]), 2, 1, 0)
  let writer = @encode.writer(8, 3, 2)
  @encode.begin_array(writer)
  @canonical_json.emit_value(value, writer)
  @encode.end_array(writer)
  assert_eq(@encode.finish(writer), "[[null]]")
  let short = @encode.writer(7, 3, 2)
  @encode.begin_array(short)
  @canonical_json.emit_value(value, short)
  let rejected = try {
    @encode.end_array(short)
    false
  } catch {
    @encode.OutputLimit => true
    _ => false
  }
  assert_true(rejected)
  let closed = try {
    @canonical_json.emit_value(value, short)
    false
  } catch {
    @encode.ClosedWriter => true
    _ => false
  }
  assert_true(closed)
}
