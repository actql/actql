///|
// Fixed complete-fragment preimages were independently assembled with Python
// canonical JSON and hashlib before product execution. See the matching corpus.
test "INSTR authored optional defaults and STRPOS control retain exact fragment identities" {
  for
    (source, expected, bytes) in [
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:aa4a861996f10eafe18b891262db498faabadcf6448c0d0be5e94f476a4b9009",
        3024,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1}]}",
        "sha256:833cf2a38a2a7a5b9efac6f2ecce6be83a8ed9f665d1960cf9a6da7682f8bd2d",
        3133,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1},{\"literal\":1}]}",
        "sha256:c6bfdc0c61ec2388263873a071567bcd18bccc68a39b5716024f0216dd26acf4",
        3242,
      ),
      (
        "{\"strpos\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:4c6d4ed0f91008775d6ffd2015ab0a526a2f3e5f4f9c5622c061bd9bda11d23a",
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
