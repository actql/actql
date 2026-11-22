///|
// Retain the authored corpus requests, limits and nodes; independently rebind
// only the declared expression-contract pin to the current normative body.
// Python canonical JSON/hashlib fixes these complete preimages before execution.
test "INSTR authored optional defaults and STRPOS control retain exact fragment identities" {
  for
    (source, expected, bytes) in [
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:6d4a8cc7a6890a867548da8e7940a49bcb2b86d651d5e7e54ad011134ce37ab1",
        3024,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1}]}",
        "sha256:3b7e38ce8f66d75411eeb66698427dda280732b551633a274c9aea7240353135",
        3133,
      ),
      (
        "{\"instr\":[{\"literal\":\"banana\"},{\"literal\":\"an\"},{\"literal\":1},{\"literal\":1}]}",
        "sha256:352dbc669aafaa230788946bf469e564f615525a3ec227ca684b765894d238af",
        3242,
      ),
      (
        "{\"strpos\":[{\"literal\":\"banana\"},{\"literal\":\"an\"}]}", "sha256:f0a0c91b041edf3e5eef2ed3766fff98e15bc301a39e4082305138590860b332",
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
