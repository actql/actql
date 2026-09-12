///|
fn artifact_evidence(expr : String) -> @lower.RootEvidence {
  let sequence = prepared_sequence(
    row_owner(",{\"derive\":{\"x\":" + expr + "}}"),
  )
  let roots = @lower.prepare_kernel_roots(sequence, 1, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  let demand = @lower.prepare_demand(roots, {
    max_roots: 100,
    max_nodes: 1000,
    max_work: 100000,
    max_text_bytes: 100000,
    max_links: 10000,
  }).unwrap()
  @lower.prepare_root_evidence(demand, 0, {
    max_nodes: 1000,
    max_tests: 1000,
    max_pointer_bytes: 100000,
  }).unwrap()
}

///|
test "root identity commits the complete root rather than just the machine node" {
  let evidence = artifact_evidence("{\"literal\":7}")
  let artifact = prepare_root_artifact(evidence, 10000, 1000, 100).unwrap()
  assert_true(physical_equal(artifact.evidence, evidence))
  // SHA-256 of the literal fixed preimage below, independently computed.
  assert_eq(
    artifact.cid,
    "sha256:39003a1c38b4fd68e3fe52959ec054812c4d510d5ec05bc28b2bd7f887e064f3",
  )
  assert_true(prepare_root_artifact(evidence, 193, 1000, 100) is Ok(_))
  assert_true(
    prepare_root_artifact(evidence, 192, 1000, 100) is Err(OutputLimit),
  )
  assert_eq(
    @identity.stringify_value(artifact.value, 10000, 1000, 100),
    "{\"contract\":{\"nullable\":false,\"type\":\"number\"},\"demand_paths\":{\"/roots/0/source\":[]},\"node\":{\"body\":7,\"op\":\"literal\"},\"parameter_pointer\":\"/exprs/x\",\"source\":{\"literal\":7},\"step_id\":\"derive_1\"}",
  )
  assert_true(prepare_root_artifact(evidence, 1, 1000, 100) is Err(OutputLimit))
  assert_true(
    prepare_root_artifact(evidence, 10000, 1, 100) is Err(OutputLimit),
  )
  assert_true(
    prepare_root_artifact(evidence, 10000, 1000, 0) is Err(OutputLimit),
  )
  assert_true(
    prepare_root_artifact(evidence, -1, 1000, 100) is Err(InvalidLimits),
  )
}

///|
test "canonical root removes object enumeration differences but preserves array order" {
  let a = prepare_root_artifact(
    artifact_evidence("{\"literal\":{\"z\":1,\"a\":[2,3]}}"),
    10000,
    1000,
    100,
  ).unwrap()
  let b = prepare_root_artifact(
    artifact_evidence("{\"literal\":{\"a\":[2,3],\"z\":1}}"),
    10000,
    1000,
    100,
  ).unwrap()
  let c = prepare_root_artifact(
    artifact_evidence("{\"literal\":{\"a\":[3,2],\"z\":1}}"),
    10000,
    1000,
    100,
  ).unwrap()
  assert_eq(a.cid, b.cid)
  assert_true(a.cid != c.cid)
}
