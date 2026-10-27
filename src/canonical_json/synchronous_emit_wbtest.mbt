///|
fn synchronous_emit_outcome(
  value : CanonicalValue,
  bytes : Int,
  nodes : Int,
  depth : Int,
  incremental : Bool,
  sink : Int,
) -> String {
  try {
    let writer = match sink {
      0 => @encode.writer(bytes, nodes, depth)
      1 => @encode.hashing_writer(bytes, nodes, depth)
      _ => @encode.measuring_writer(bytes, nodes, depth)
    }
    if incremental {
      let cursor = start_emit(value, writer)
      while !advance_emit(cursor) {
        ()
      }
    } else {
      emit_value(value, writer)
    }
    match sink {
      0 => @encode.finish(writer)
      1 => @encode.finish_hash(writer)
      _ => @encode.finish_measurement(writer).to_string()
    }
  } catch {
    @encode.InvalidStructure => "error:structure"
    @encode.InvalidUnicode => "error:unicode"
    @encode.InvalidNumber => "error:number"
    @encode.OutputLimit => "error:limit"
    @encode.ClosedWriter => "error:closed"
  }
}

///|
test "synchronous emission preserves complete text hash measure and every tight limit" {
  let long = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789é😀\n"
  let value = from_json(
    { "a": [Json::null(), true, 3, { "x": long + long }], "b": [], "c": {} },
    100,
    10,
    4096,
    data_keys=true,
  )
  let wire = synchronous_emit_outcome(value, 4096, 100, 10, true, 0)
  assert_true(wire.has_prefix("{\"a\":[null,true,3,"))
  for sink in 0..<3 {
    for bytes in 0..<400 {
      assert_eq(
        synchronous_emit_outcome(value, bytes, 100, 10, false, sink),
        synchronous_emit_outcome(value, bytes, 100, 10, true, sink),
      )
    }
    for nodes in 0..<15 {
      for depth in -1..<6 {
        assert_eq(
          synchronous_emit_outcome(value, 4096, nodes, depth, false, sink),
          synchronous_emit_outcome(value, 4096, nodes, depth, true, sink),
        )
      }
    }
  }
  assert_eq(synchronous_emit_outcome(Null, 4, 1, 0, false, 0), "null")
  assert_eq(synchronous_emit_outcome(Bool(true), 4, 1, 0, false, 0), "true")
}

///|
test "synchronous emission retains ordered long keys and shared children without recursion" {
  let key = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789longkey"
  let shared : CanonicalValue = String("é😀\"\\\n")
  let value : CanonicalValue = Object({
    values: [
      (key, Array({ values: [shared, shared], })),
      (key + "z", Object({ values: [], })),
    ],
  })
  for sink in 0..<3 {
    for bytes in [0, 63, 64, 65, 127, 128, 129, 4096] {
      assert_eq(
        synchronous_emit_outcome(value, bytes, 20, 8, false, sink),
        synchronous_emit_outcome(value, bytes, 20, 8, true, sink),
      )
    }
  }
  let mut deep = shared
  for _ in 0..<1024 {
    deep = Array({ values: [deep], })
  }
  assert_eq(
    synchronous_emit_outcome(deep, 4096, 2048, 1024, false, 0),
    synchronous_emit_outcome(deep, 4096, 2048, 1024, true, 0),
  )
}

///|
test "synchronous emission preserves malformed input refusal and closed writer" {
  let bad = String::from_array([(0xd800).unsafe_to_char()])
  let cases : Array[CanonicalValue] = [
    String(bad),
    String(String::make(65, 'a') + bad),
    Object({ values: [("z", Null), ("a", Null)], }),
    Object({ values: [("a", Null), ("a", Null)], }),
    Object({ values: [(String::make(65, 'a') + bad, Null)], }),
  ]
  for value in cases {
    for sink in 0..<3 {
      for bytes in [0, 1, 63, 64, 65, 66, 4096] {
        assert_eq(
          synchronous_emit_outcome(value, bytes, 20, 8, false, sink),
          synchronous_emit_outcome(value, bytes, 20, 8, true, sink),
        )
      }
    }
  }
  let writer = @encode.writer(100, 20, 8)
  @encode.cancel_writer(writer)
  let closed = try {
    emit_value(Null, writer)
    false
  } catch {
    @encode.ClosedWriter => true
    _ => false
  }
  assert_true(closed)
}
