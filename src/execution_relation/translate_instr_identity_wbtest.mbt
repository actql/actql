///|
// Retain the authored corpus requests, limits and nodes; independently rebind
// only the declared expression-contract pin to the current normative body.
// Python canonical JSON/hashlib fixes these complete preimages before execution.
test "INSTR authored optional defaults and STRPOS control retain exact fragment identities" {
  for
    (source, expected, bytes) in [
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:d7f23b1835813ef68dea421887c2b47be6697a3fd7fd5aad12326cf234537f58",
        3024,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1}]}",
        "sha256:02db8f2f53a4fe5b846a86b2abc57940cef8ce05cdde79a0aea166513bb86018",
        3133,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1},{\"literal\":1}]}",
        "sha256:ff8013462f36c2b0aeae20675c6e60a092370731de9d5c7a95476cc118d1785d",
        3242,
      ),
      (
        "{\"strpos\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:ea5b1c39140d9f2edf5322fd3f250e142420f772fa2cc32c83f0ff5cd80b5cac",
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
