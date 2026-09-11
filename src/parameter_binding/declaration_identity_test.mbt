///|
fn declaration_text(source : String) -> String raise {
  let d = declaration_at(declarations(source), 0).unwrap()
  let writer = @encode.writer(8000000, 100000, 20000)
  emit_declaration(d, writer)
  @encode.finish(writer)
}

///|
test "semantic declaration retains defaults and nested meta but removes only annotations" {
  let input =
    #|{"p":{"meta":{"note":"annotation"},"type":"object","fields":{"meta":{"type":"string"}},"default":{"meta":"business"}}}
  let expected =
    #|{"default":{"meta":"business"},"fields":{"meta":{"type":"string"}},"type":"object"}
  assert_eq(declaration_text(input), expected)
  assert_eq(
    declaration_text(
      (
        #|{"p":{"type":"object","default":{"meta":"business"},"fields":{"meta":{"type":"string"}},"meta":{"note":"different"}}}
      ),
    ),
    expected,
  )
  assert_eq(
    declaration_text(
      (
        #|{"p":{"type":"number","nullable":true,"default":null,"integer":false,"minimum":0}}
      ),
    ),
    (
      #|{"default":null,"integer":false,"minimum":0,"nullable":true,"type":"number"}
    ),
  )
  assert_eq(
    declaration_text(
      (
        #|{"p":{"type":"string","format":"duration","default":"01s"}}
      ),
    ),
    (
      #|{"default":"01s","format":"duration","type":"string"}
    ),
  )
  assert_eq(
    declaration_text(
      (
        #|{"p":{"type":"number"}}
      ),
    ),
    (
      #|{"type":"number"}
    ),
  )
}

///|
test "semantic declaration shares text measure hash limits and failure closure" {
  let d = declaration_at(
    declarations(
      (
        #|{"p":{"type":"string","default":"é","meta":{"note":"excluded"}}}
      ),
    ),
    0,
  ).unwrap()
  let expected =
    #|{"default":"é","type":"string"}
  let text = @encode.writer(32, 3, 1)
  emit_declaration(d, text)
  assert_eq(@encode.finish(text), expected)
  let measure = @encode.measuring_writer(32, 3, 1)
  emit_declaration(d, measure)
  assert_eq(@encode.finish_measurement(measure), 32)
  let hash = @encode.hashing_writer(32, 3, 1)
  emit_declaration(d, hash)
  // Independently computed from the fixed UTF-8 text with Node SHA-256.
  assert_eq(
    @encode.finish_hash(hash),
    "6f365c1928f39c20cf5cd5b4c1771bcd158d31b1966b23d1e25e34a9ac9fcffd",
  )
  for (bytes, nodes, depth) in [(31, 3, 1), (32, 2, 1), (32, 3, 0)] {
    let writer = @encode.writer(bytes, nodes, depth)
    let failed = try {
      emit_declaration(d, writer)
      false
    } catch {
      _ => true
    }
    assert_true(failed)
    let closed = try {
      ignore(@encode.finish(writer))
      false
    } catch {
      _ => true
    }
    assert_true(closed)
  }
}

///|
test "semantic declaration sorts supplementary fields by UTF-16 and preserves semantic options" {
  assert_eq(
    declaration_text(
      (
        #|{"p":{"type":"object","fields":{"\ue000":{"type":"string"},"\ud800\udc00":{"type":"number"},"a/~":{"type":"boolean"}}}}
      ),
    ),
    (
      #|{"fields":{"a/~":{"type":"boolean"},"𐀀":{"type":"number"},"":{"type":"string"}},"type":"object"}
    ),
  )
  let first = declaration_text(
    (
      #|{"p":{"type":"number","default":1}}
    ),
  )
  let other = declaration_text(
    (
      #|{"p":{"type":"number","default":2}}
    ),
  )
  assert_true(first != other)
  assert_true(
    first !=
    declaration_text(
      (
        #|{"p":{"type":"number","default":1,"nullable":false}}
      ),
    ),
  )
}

///|
test "semantic declaration emission is nonrecursive" {
  let depth = 3000
  let raw = "{\"p\":" +
    "{\"type\":\"array\",\"items\":".repeat(depth) +
    "{\"type\":\"number\"}" +
    "}".repeat(depth) +
    "}"
  let expected = "{\"items\":".repeat(depth) +
    "{\"type\":\"number\"}" +
    ",\"type\":\"array\"}".repeat(depth)
  assert_eq(declaration_text(raw), expected)
}
