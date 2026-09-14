// Generated independent pivot numeric slot preimages.

///|
test "pivot numeric slot preimage 0" {
  let input = @json.parse(
    "{\"output_name\":\"a\",\"reduction_profile_cid\":\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\",\"source_ordinal\":0,\"unit_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-pivot-numeric-slot/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:5e4b51816db97338ae7b31b860859de82ed5406153dc9a33bba9081b973598e8",
  )
}

///|
test "pivot numeric slot preimage 1" {
  let input = @json.parse(
    "{\"output_name\":\"a\",\"reduction_profile_cid\":\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\",\"source_ordinal\":0,\"unit_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"version\":\"actql-pivot-numeric-slot/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:34c46b2c902069558a1d5c5001d99dd6d3684fa486acb37b34007037f888ca35",
  )
}

///|
test "pivot numeric slot preimage 2" {
  let input = @json.parse(
    "{\"output_name\":\"a\",\"reduction_profile_cid\":\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\",\"source_ordinal\":1,\"unit_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-pivot-numeric-slot/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:465ebcc1b12acf1d5754aa7db720c47b9a78a6dcf9d924a32a02137dce6e6807",
  )
}

///|
test "pivot numeric slot preimage 3" {
  let input = @json.parse(
    "{\"output_name\":\"z\",\"reduction_profile_cid\":\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\",\"source_ordinal\":0,\"unit_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-pivot-numeric-slot/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:26bf4c43cbe74de0143d81d5cd6317d14a550eb6921b53a69d07c172fa770211",
  )
}

///|
test "pivot numeric slot preimage 4" {
  let input = @json.parse(
    "{\"output_name\":\"é~/\\n😀\",\"reduction_profile_cid\":\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\",\"source_ordinal\":0,\"unit_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-pivot-numeric-slot/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:603df6896f74f07fe80af79caea35050ebd2c1769c77b1d1b07ecf81355ef439",
  )
}

///|
test "pivot numeric slot preimage 5" {
  let input = @json.parse(
    "{\"output_name\":\"a\",\"reduction_profile_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"source_ordinal\":0,\"unit_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-pivot-numeric-slot/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:aecbb14c88586ad70c02a82b4232931c44e4e47d13da48c0d7b1255b5449afea",
  )
}
