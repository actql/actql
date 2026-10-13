///|
// Fixed complete-fragment preimages were independently assembled with Python
// canonical JSON and hashlib before product execution. See the matching corpus.
test "INSTR authored optional defaults and STRPOS control retain exact fragment identities" {
  for
    (source, expected, bytes) in [
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:576b4802d1c57547c061b8559873a6df14789545fa578e9f00dd4cd3914ec165",
        3024,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1}]}",
        "sha256:e7cabe28686dac621c33bde5274a16453437a49f949e7a735f7784f5dabf0375",
        3133,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1},{\"literal\":1}]}",
        "sha256:7e5e6e381992969e1e2fb69c14d5fb1dc0019fe228439f909a7f7879aecf5908",
        3242,
      ),
      (
        "{\"strpos\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:8bdcec19bae24a9dd04e08d6686357a6fa3af2b8e1f712b2e3c114be15710323",
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
