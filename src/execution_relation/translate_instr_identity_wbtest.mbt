///|
// Retain the authored corpus requests, limits and nodes; independently rebind
// only the declared expression-contract pin to the current normative body.
// Python canonical JSON/hashlib fixes these complete preimages before execution.
test "INSTR authored optional defaults and STRPOS control retain exact fragment identities" {
  for
    (source, expected, bytes) in [
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:470d29694c31fec40c8848c5ed4c404743d1df1d0c0fcb1a212c3f421a99d18f",
        3024,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1}]}",
        "sha256:9127228e9a6354db6133da4e02c8f81f23c6ee1d141c55e768283c2add70f2c5",
        3133,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1},{\"literal\":1}]}",
        "sha256:9f17b62c24b000637400bd86942bbfa11ad4a67d2150b4f9e0b83f4e1985cee8",
        3242,
      ),
      (
        "{\"strpos\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:27aaf5bd3225e32e6593ab2d4356319f545610fa0407bbb2192d2bf851cf9d5d",
        3030,
      ),
    ] {
    let material = prepare_fragment_material(
      artifact_request(source, 10L),
      material_demands(),
      registry_limits(),
    ).unwrap()
    let candidate = prepare_fragment_candidate(
      test_fragment_contract(),
      material,
      registry_limits(),
    ).unwrap()
    assert_eq(candidate.artifact.cid, expected)
    assert_eq(candidate.artifact.bytes, bytes)
  }
}
