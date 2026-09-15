///|
test "measured parsing includes all source bytes and container depth" {
  let json = "\uFEFF {\"é\":[\"😀\",null]} \r\n"
  let yaml = "\uFEFFé: [\"😀\", null]\n...\n# tail\n"
  for (text, yaml) in [(json, false), (yaml, true)] {
    let bytes = @utf8.encode(text)
    let parsed = if yaml {
      parse_yaml_measured(text, limits()).unwrap()
    } else {
      parse_json_measured(text, limits()).unwrap()
    }
    let expected : ParseUsage = {
      input_bytes: bytes.length(),
      nodes: 4,
      depth: 2,
    }
    assert_eq(parsed.usage, expected)
    assert_true(parsed.node.span.end_byte < expected.input_bytes)
    let from_bytes = if yaml {
      parse_yaml_bytes_measured(bytes, limits()).unwrap()
    } else {
      parse_json_bytes_measured(bytes, limits()).unwrap()
    }
    assert_eq(from_bytes.usage, expected)
    let caps = limits(bytes=expected.input_bytes, nodes=4, depth=2)
    assert_true(
      (if yaml {
        parse_yaml_measured(text, caps)
      } else {
        parse_json_measured(text, caps)
      })
      is Ok(_),
    )
    for
      small in [
        limits(bytes=expected.input_bytes - 1),
        limits(nodes=3),
        limits(depth=1),
      ] {
      assert_true(
        (if yaml {
          parse_yaml_measured(text, small)
        } else {
          parse_json_measured(text, small)
        })
        is Err(_),
      )
    }
  }
  assert_eq(parse_json_measured("null", limits()).unwrap().usage, {
    input_bytes: 4,
    nodes: 1,
    depth: 0,
  })
  assert_eq(parse_yaml_measured("{missing:}", limits()).unwrap().usage, {
    input_bytes: 10,
    nodes: 2,
    depth: 1,
  })
}
