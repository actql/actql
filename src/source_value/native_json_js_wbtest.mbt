///|
/// Opaque native DATA, not an admitted Program or an SDK snapshot receipt.
/// The fixed Node caller retains the original SDK capture and Request parent.
#external
type NativeJsonValue

///|
extern "js" fn native_json_kind(value : NativeJsonValue) -> Int =
  #|(value) => value === null || typeof value === 'number' && !Number.isFinite(value) ? 0 : typeof value === 'boolean' ? 1 :
  #| typeof value === 'number' ? 2 : typeof value === 'string' ? 3 :
  #| Array.isArray(value) ? 4 : value !== null && typeof value === 'object' ? 5 : 6

///|
extern "js" fn native_json_bool(value : NativeJsonValue) -> Bool =
  #|(value) => value

///|
extern "js" fn native_json_text(value : NativeJsonValue) -> String =
  #|(value) => value

///|
extern "js" fn native_json_number_text(value : NativeJsonValue) -> String =
  #|(value) => String(value)

///|
extern "js" fn native_json_keys(value : NativeJsonValue) -> FixedArray[String] =
  #|(value) => Object.keys(value)

///|
extern "js" fn native_json_length(value : NativeJsonValue) -> Int =
  #|(value) => Object.getOwnPropertyDescriptor(value, 'length').value

///|
// Own DATA only: a malformed internal caller cannot invoke a getter while
// pretending to supply a detached native snapshot. The original SDK capture
// has plain dense arrays/objects; no second caller traversal is performed.
extern "js" fn native_json_field(
  value : NativeJsonValue,
  key : String,
) -> NativeJsonValue =
  #|(value, key) => {
  #| const field = Object.getOwnPropertyDescriptor(value, key);
  #| return field !== undefined && Object.hasOwn(field, 'value') ? field.value : undefined;
  #|}

///|
let native_json_reader : JsonDataReader[NativeJsonValue] = {
  kind: native_json_kind,
  boolean: native_json_bool,
  text: native_json_text,
  number_text: native_json_number_text,
  keys: native_json_keys,
  length: native_json_length,
  field: native_json_field,
}

///|
#cfg(target="js")
extern "js" fn native_json_test_input(text : String) -> NativeJsonValue =
  #|(text) => JSON.parse(text)

///|
#cfg(target="js")
fn native_json_same_node(left : Node, right : Node) -> Bool {
  match (left.value, right.value) {
    (Null, Null) => true
    (Bool(a), Bool(b)) => a == b
    (Number(a), Number(b)) => a == b
    (String(a), String(b)) => a == b
    (Array(a), Array(b)) =>
      a.length() == b.length() &&
      a.iter().zip(b.iter()).all(pair => native_json_same_node(pair.0, pair.1))
    (Object(a), Object(b)) =>
      a.length() == b.length() &&
      a
      .iter()
      .zip(b.iter())
      .all(pair => {
        pair.0.key == pair.1.key &&
        native_json_same_node(pair.0.value, pair.1.value)
      })
    _ => false
  }
}

///|
#cfg(target="js")
test "native captured input retains nested values measurements and original Program key laws" {
  let document =
    #|{"version":"actql/0.1","id":"native-é","stages":[{"id":"main","inputs":{},"steps":[],"results":{},"effects":{"é":{"update":{"set":{"Name":{"literal":{"é":1,"é":2}}}}}}}],"params":{"é":{"type":"string"}},"name":{"a":[null,true,false,0.1,"😀\n\u0000",{"b":3}]}}
  let native = native_json_test_input(document)
  let limits : ParseLimits = {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 64,
  }
  let actual = admit_captured_json(
    native,
    native_json_reader,
    limits,
    program_keys=true,
  ).unwrap()
  let old = parse_program_json_measured(document, limits).unwrap()
  assert_true(native_json_same_node(actual.node, old.node))
  assert_eq(actual.usage, old.usage)
  // The default data reader must preserve the same keys instead of repairing
  // them through Program identifier normalization.
  let data = admit_captured_json(native, native_json_reader, limits).unwrap()
  let old_data = parse_admitted(
      document,
      "<memory>",
      limits,
      false,
      normalize_text=false,
    ).unwrap().node
  assert_true(native_json_same_node(data.node, old_data))
}

///|
#cfg(target="js")
test "native captured input preserves normalization collision refusal and exact byte node depth bounds" {
  let document = "{\"é\":1,\"é\":2}"
  let limits : ParseLimits = {
    max_input_bytes: 100,
    max_nodes: 100,
    max_depth: 8,
  }
  assert_true(
    admit_captured_json(
      native_json_test_input(document),
      native_json_reader,
      limits,
      program_keys=true,
    )
    is Err({ issue: DuplicateKey("é"), .. }),
  )
  let native = native_json_test_input("{\"a\":[\"é😀\\n\",2]}")
  let measured = admit_captured_json(native, native_json_reader, limits).unwrap().usage
  let exact = {
    max_input_bytes: measured.input_bytes,
    max_nodes: measured.nodes,
    max_depth: measured.depth,
  }
  assert_eq(
    admit_captured_json(native, native_json_reader, exact).unwrap().usage,
    measured,
  )
  assert_true(
    admit_captured_json(native, native_json_reader, {
      ..exact,
      max_input_bytes: exact.max_input_bytes - 1,
    })
    is Err({ issue: InputLimit, .. }),
  )
  assert_true(
    admit_captured_json(native, native_json_reader, {
      ..exact,
      max_nodes: exact.max_nodes - 1,
    })
    is Err({ issue: NodeLimit, .. }),
  )
  assert_true(
    admit_captured_json(native, native_json_reader, {
      ..exact,
      max_depth: exact.max_depth - 1,
    })
    is Err({ issue: DepthLimit, .. }),
  )
  assert_true(
    admit_captured_json(native, native_json_reader, { ..exact, max_nodes: -1, })
    is Err({ issue: InvalidLimits, .. }),
  )
}

///|
#cfg(target="js")
extern "js" fn native_json_test_snapshot() -> NativeJsonValue =
  #|() => JSON.parse(JSON.stringify({rounded:JSON.rawJSON('9007199254740993'),
  #| overflow:JSON.rawJSON('1e999'), zero:JSON.rawJSON('-0'),fraction:0.1}))

///|
#cfg(target="js")
test "native captured input uses the detached numeric value rather than obsolete raw JSON spelling" {
  let limits : ParseLimits = {
    max_input_bytes: 1000,
    max_nodes: 100,
    max_depth: 8,
  }
  let actual = admit_captured_json(
    native_json_test_snapshot(),
    native_json_reader,
    limits,
  ).unwrap()
  let expected = parse_json_measured(
    "{\"rounded\":9007199254740992,\"overflow\":null,\"zero\":0,\"fraction\":0.1}",
    limits,
  ).unwrap()
  assert_true(native_json_same_node(actual.node, expected.node))
  assert_eq(actual.usage, expected.usage)
}

///|
#cfg(target="js")
extern "js" fn native_json_test_accessor() -> NativeJsonValue =
  #|() => Object.freeze({get trap(){throw new Error('caller getter ran')}})

///|
#cfg(target="js")
test "native captured input never invokes a copied accessor and still refuses malformed Unicode" {
  let limits : ParseLimits = {
    max_input_bytes: 1000,
    max_nodes: 100,
    max_depth: 8,
  }
  assert_true(
    admit_captured_json(native_json_test_accessor(), native_json_reader, limits)
    is Err({ issue: UnexpectedToken, .. }),
  )
  assert_true(
    admit_captured_json(
      native_json_test_input("\"\\ud800\""),
      native_json_reader,
      limits,
    )
    is Err({ issue: InvalidUnicodeEscape, .. }),
  )
}

///|
#cfg(target="js")
test "native normalized keys do not claim an unavailable original spelling" {
  // These distinct combining-mark orders have equal byte/UTF16 geometry.
  // Both normalize to the same key; a normalized Cursor and its measurements
  // cannot determine which original JSON Pointer was actually submitted.
  let first = "q\u{0301}\u{0323}"
  let second = "q\u{0323}\u{0301}"
  let canonical = "q\u{0323}\u{0301}"
  let limits : ParseLimits = {
    max_input_bytes: 1000,
    max_nodes: 100,
    max_depth: 8,
  }
  let originals : Array[ParsedSource] = []
  for key in [first, second] {
    let document = "{\"" + key + "\":\"caller-owned\"}"
    let native = admit_captured_json(
      native_json_test_input(document),
      native_json_reader,
      limits,
      normalize_keys=true,
    ).unwrap()
    guard native.node.value is Object(fields) else {
      fail("the original supplied input must remain an object")
    }
    assert_eq(fields[0].key, canonical)
    assert_true(fields[0].key_span.end_byte > fields[0].key_span.start_byte)
    assert_eq(fields[0].key_span.source_path, "<captured-json>")
    originals.push(native)
    // Both readers require this corresponding original representation.
    // A scalar span by itself cannot recover either original spelling.
    let bytes = @utf8.encode(document)
    let textual = parse_json_measured(document, limits).unwrap()
    guard textual.node.value is Object(text_fields) else {
      fail("the original text must remain an object")
    }
    for span in [text_fields[0].key_span, fields[0].key_span] {
      assert_true(span.end_byte > span.start_byte)
      let scalar = parse_json_bytes_preserving(
        bytes[span.start_byte:span.end_byte].to_owned(),
        { max_input_bytes: 100, max_nodes: 1, max_depth: 0, },
      ).unwrap()
      assert_true(scalar.value is String(actual) && actual == key)
    }
  }
  assert_true(first != second)
  assert_eq(originals[0].usage, originals[1].usage)
  assert_true(native_json_same_node(originals[0].node, originals[1].node))
}

///|
#cfg(target="js")
extern "js" fn native_json_test_wire(input : NativeJsonValue) -> String =
  #|(input) => JSON.stringify(input)

///|
fn native_json_same_key_offsets(actual : Node, expected : Node) -> Bool {
  match (actual.value, expected.value) {
    (Object(a), Object(b)) =>
      a.length() == b.length() &&
      a
      .iter()
      .zip(b.iter())
      .all(pair => {
        pair.0.key_span.start_byte == pair.1.key_span.start_byte &&
        pair.0.key_span.end_byte == pair.1.key_span.end_byte &&
        pair.0.key_span.start_line == pair.1.key_span.start_line &&
        pair.0.key_span.end_line == pair.1.key_span.end_line &&
        pair.0.key_span.start_column == pair.1.key_span.start_column &&
        pair.0.key_span.end_column == pair.1.key_span.end_column &&
        native_json_same_key_offsets(pair.0.value, pair.1.value)
      })
    (Array(a), Array(b)) =>
      a.length() == b.length() &&
      a
      .iter()
      .zip(b.iter())
      .all(pair => native_json_same_key_offsets(pair.0, pair.1))
    _ => true
  }
}

///|
#cfg(target="js")
test "native key offsets bind the same detached JSON representation across containers and escaped scalars" {
  let document =
    #|{ "a": [null,true,false,0.1,-0,1e21,"é😀\n\u0000",{},[],{"a/b~\"\\é😀":"last"}], "q̣́": {"nested": [{"é": 7}]} }
  let input = native_json_test_input(document)
  let wire = native_json_test_wire(input)
  let limits : ParseLimits = {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 64,
  }
  let native = admit_captured_json(
    input,
    native_json_reader,
    limits,
    normalize_keys=true,
  ).unwrap()
  let textual = parse_json_measured(wire, limits).unwrap()
  assert_true(native_json_same_node(native.node, textual.node))
  assert_eq(native.usage, textual.usage)
  assert_true(native_json_same_key_offsets(native.node, textual.node))
  assert_eq(native.node.span.start_byte, 0)
  assert_eq(native.node.span.end_byte, 0)
}
