///|
test "generic source parsers keep identifier normalization inside Effect-shaped data" {
  let text =
    #|{"stages":[{"effects":{"e":{"update":{"set":{"x":{"literal":{"é":1,"e\u0301":2}}}}}}}]}
  for
    result in [
      parse_json(text, limits()),
      parse_yaml(text, limits()),
      parse_json_bytes(@utf8.encode(text), limits()),
      parse_yaml_bytes(@utf8.encode(text), limits()),
    ] {
    assert_true(result is Err({ issue: DuplicateKey("é"), .. }))
  }
}
