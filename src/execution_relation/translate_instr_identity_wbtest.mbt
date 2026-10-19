///|
// Retain the authored corpus requests, limits and nodes; independently rebind
// only the declared expression-contract pin to the current normative body.
// Python canonical JSON/hashlib fixes these complete preimages before execution.
test "INSTR authored optional defaults and STRPOS control retain exact fragment identities" {
  for
    (source, expected, bytes) in [
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:267631ec58732b160e980e0c3cff9f97efe71235850eba00fa88010e9526e0d4",
        3024,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1}]}",
        "sha256:f72eda1060b57744f4c42b1bb1f0e0253a738b133dd9616a51f6ab3df398eaab",
        3133,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1},{\"literal\":1}]}",
        "sha256:31176e2f4db3a19f338453731fb880036d18ad0d5a19f45b31827a2363b4ef67",
        3242,
      ),
      (
        "{\"strpos\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:631eb06aeba76598f8a277e766dfef2c95291ffbf88bc37cc503d957728b4d46",
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
