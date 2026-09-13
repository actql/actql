// Generated independent analytic numeric slot preimages.

///|
test "analytic numeric slot preimage 0" {
  let input = @json.parse(
    "{\"output_name\":\"sum\",\"reduction_profile_cid\":\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\",\"source_ordinal\":0,\"unit_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-analytic-numeric-slot/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:5b40eb999d35eeb93959abbb4b57a49d93271ba3a27bd71562e08efb0d7d6839",
  )
}

///|
test "analytic numeric slot preimage 1" {
  let input = @json.parse(
    "{\"output_name\":\"sum\",\"reduction_profile_cid\":\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\",\"source_ordinal\":0,\"unit_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"version\":\"actql-analytic-numeric-slot/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:7ee63999d4bf0f72afc19affd1963705660b2e9ec13f7ec87e20040dc3511f6c",
  )
}

///|
test "analytic numeric slot preimage 2" {
  let input = @json.parse(
    "{\"output_name\":\"sum\",\"reduction_profile_cid\":\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\",\"source_ordinal\":1,\"unit_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-analytic-numeric-slot/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:1efb11cb817261c737da9733a3411a3ef0106affec3245e0e1341ca2d6451548",
  )
}

///|
test "analytic numeric slot preimage 3" {
  let input = @json.parse(
    "{\"output_name\":\"avg\",\"reduction_profile_cid\":\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\",\"source_ordinal\":0,\"unit_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-analytic-numeric-slot/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:a7990d8b87d469ba5caa962ea13bf9d2c9745a90c54ee68e9d85833f734f87d2",
  )
}

///|
test "analytic numeric slot preimage 4" {
  let input = @json.parse(
    "{\"output_name\":\"é~/\\n😀\",\"reduction_profile_cid\":\"sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df\",\"source_ordinal\":0,\"unit_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-analytic-numeric-slot/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:1cb2eeacb728ef169827cb2156ceebd4662a8aab011a3a96377b5625d5a87bff",
  )
}

///|
test "analytic numeric slot preimage 5" {
  let input = @json.parse(
    "{\"output_name\":\"sum\",\"reduction_profile_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"source_ordinal\":0,\"unit_definition_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-analytic-numeric-slot/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:f9e117a90c7922c7e2f83979b424208f66af38b9b446066b9d0c3d894d5c9924",
  )
}
