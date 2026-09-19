///|
fn scalar_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 512, max_nodes: 32, max_depth: 4, },
      source_path="scalar.json",
    ).unwrap(),
    {
      max_nodes: 32,
      max_depth: 4,
      max_string_bytes: 256,
      max_total_string_bytes: 256,
    },
  ).unwrap()
}

///|
fn admitted_scalar(contract : String, value : String) -> CheckedValue {
  admit(
    @contract.read_author(scalar_cursor(contract), {
      max_nodes: 32,
      max_depth: 4,
      max_text_bytes: 256,
    }).unwrap(),
    scalar_cursor(value),
    { max_nodes: 8, max_depth: 2, max_text_bytes: 128, },
  ).unwrap()
}

///|
test "canonical scalar text preserves every supported scalar domain" {
  let cases = [
    ("{\"type\":\"number\",\"nullable\":false}", "1.25", "1.25"),
    ("{\"type\":\"string\",\"nullable\":false}", "\"é😀\"", "é😀"),
    (
      "{\"type\":\"decimal\",\"nullable\":false,\"precision\":4,\"scale\":2}", "\"-1.20\"",
      "-1.20",
    ),
    ("{\"type\":\"boolean\",\"nullable\":false}", "true", "true"),
    (
      "{\"type\":\"timestamp\",\"nullable\":false}", "\"2026-09-19T00:00:00.000Z\"",
      "2026-09-19T00:00:00.000Z",
    ),
    ("{\"type\":\"date\",\"nullable\":false}", "\"2026-09-19\"", "2026-09-19"),
  ]
  for (contract, value, expected) in cases {
    let checked = admitted_scalar(contract, value)
    assert_eq(canonical_scalar_text(checked, 128), Some(expected))
    assert_eq(canonical_scalar_text(checked, expected.length() - 1), None)
  }
}

///|
test "canonical scalar text rejects null and structured values" {
  assert_eq(
    canonical_scalar_text(
      admitted_scalar("{\"type\":\"string\",\"nullable\":true}", "null"),
      128,
    ),
    None,
  )
  assert_eq(
    canonical_scalar_text(
      admitted_scalar(
        "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
        "[1]",
      ),
      128,
    ),
    None,
  )
}
