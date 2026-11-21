///|
// Retain the authored corpus requests, limits and nodes; independently rebind
// only the declared expression-contract pin to the current normative body.
// Python canonical JSON/hashlib fixes these complete preimages before execution.
test "INSTR authored optional defaults and STRPOS control retain exact fragment identities" {
  for
    (source, expected, bytes) in [
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:699de7996fbc6b9241037fe7d74de6796cedd0b37cef0c30bf30c1e5e4c93563",
        3024,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1}]}",
        "sha256:32b4850cc18b5370d6a40650c698f2803ec9338e9bfe0ca73513f015f9660e4f",
        3133,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1},{\"literal\":1}]}",
        "sha256:06df75827f3bda5fa7c166809108defcab3f92a1770c84743418fc73e36fe562",
        3242,
      ),
      (
        "{\"strpos\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:e063781b7d87bd24fbc36e574f0df34fe6843aa568d6be6f41939163cf86d780",
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
