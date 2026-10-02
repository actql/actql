///|
fn source_text(expression : Expression) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(10000000, 500000, 40000)
  emit_source(expression, writer)
  @encode.finish(writer)
}

///|
test "normalized source emission preserves unbound references and opaque literal data" {
  for
    (input, expected) in [
      (
        (
          #|{"add":["$x + 1",{"to_decimal":{"value":{"field":"left.cost"},"precision":8,"scale":2}}]}
        ),
        (
          #|{"add":[{"add":[{"$param":"x"},{"literal":1}]},{"cast":{"target":{"precision":8,"scale":2,"type":"decimal"},"value":{"join_field":{"name":"cost","side":"left"}}}}]}
        ),
      ),
      (
        (
          #|{"literal":{"meta":{"keep":true},"literal":{"field":"x"},"$param":"hidden","empty":[],"null":null}}
        ),
        (
          #|{"literal":{"$param":"hidden","empty":[],"literal":{"field":"x"},"meta":{"keep":true},"null":null}}
        ),
      ),
      (
        (
          #|{"literal":{"":2,"😀":1,"é":"é\r\n"}}
        ),
        (
          #|{"literal":{"é":"é\r\n","😀":1,"":2}}
        ),
      ),
      (
        (
          #|{"template":"Hello {id}"}
        ),
        (
          #|{"template":"Hello {id}"}
        ),
      ),
      (
        (
          #|{"cast":{"value":{"literal":null},"target":{"type":"number"}}}
        ),
        (
          #|{"cast":{"target":{"type":"number"},"value":{"literal":null}}}
        ),
      ),
    ] {
    let expression = admit(source_cursor(input), test_limits()).unwrap()
    let text = source_text(expression)
    assert_eq(text, expected)
    let reparsed = admit(source_cursor(text), test_limits()).unwrap()
    assert_eq(source_text(reparsed), text)
    assert_cursor(tree(expression), tree(reparsed))
  }
  let text = admit(text_cursor("$x + 1"), test_limits()).unwrap()
  let structured = admit(
    source_cursor("{\"add\":[{\"$param\":\"x\"},{\"literal\":1}]}"),
    test_limits(),
  ).unwrap()
  assert_eq(source_text(text), source_text(structured))
}

///|
test "source emission shares text measurement and hash budgets with its enclosing body" {
  let expression = admit(text_cursor("$x + 1"), test_limits()).unwrap()
  let expected = "{\"expr\":{\"add\":[{\"$param\":\"x\"},{\"literal\":1}]}}"
  // ASCII bytes, 7 JSON nodes, 4 container levels including the envelope.
  for bytes in [expected.length() - 1, expected.length(), expected.length() + 1] {
    for nodes in [6, 7, 8] {
      for depth in [3, 4, 5] {
        let success = bytes >= expected.length() && nodes >= 7 && depth >= 4
        for mode in 0..<3 {
          let writer = match mode {
            0 => @encode.writer(bytes, nodes, depth)
            1 => @encode.measuring_writer(bytes, nodes, depth)
            _ => @encode.hashing_writer(bytes, nodes, depth)
          }
          let accepted = try {
            @encode.begin_object(writer)
            @encode.key(writer, "expr")
            emit_source(expression, writer)
            @encode.end_object(writer)
            match mode {
              0 => assert_eq(@encode.finish(writer), expected)
              1 =>
                assert_eq(@encode.finish_measurement(writer), expected.length())
              _ =>
                // Independent Node SHA-256 of the fixed canonical bytes.
                assert_eq(
                  @encode.finish_hash(writer),
                  "e1434b03be5d62a8d33460fccba09b82a39b754de6429c46685cf7ce8d717fbe",
                )
            }
            true
          } catch {
            _ => false
          }
          assert_eq(accepted, success)
        }
      }
    }
  }
}

///|
test "source emission is nonrecursive and keeps array occurrence order" {
  let depth = 10000
  let input = "{\"literal\":" +
    "[".repeat(depth) +
    "[2,1,2]" +
    "]".repeat(depth) +
    "}"
  let expression = admit(source_cursor(input), test_limits()).unwrap()
  assert_eq(source_text(expression), input)
  let nested = "{\"negate\":".repeat(depth) +
    "{\"field\":\"x\"}" +
    "}".repeat(depth)
  let expression = admit(source_cursor(nested), test_limits()).unwrap()
  assert_eq(source_text(expression), nested)
}

///|
test "wide literal objects use canonical name order without interpreting keys" {
  let input = StringBuilder()
  let expected = StringBuilder()
  input.write_string("{\"literal\":{")
  expected.write_string("{\"literal\":{")
  for i in 0..<10000 {
    if i != 0 {
      input.write_char(',')
      expected.write_char(',')
    }
    input.write_string("\"k" + (19999 - i).to_string() + "\":null")
    expected.write_string("\"k" + (10000 + i).to_string() + "\":null")
  }
  input.write_string("}}")
  expected.write_string("}}")
  let expression = admit(source_cursor(input.to_string()), test_limits()).unwrap()
  assert_eq(source_text(expression), expected.to_string())
}
