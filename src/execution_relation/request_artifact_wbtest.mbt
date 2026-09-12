///|
fn artifact_request(expr : String, rows : Int64) -> @lower.FragmentRequest {
  let sequence = prepared_sequence(
    row_owner(",{\"derive\":{\"x\":" + expr + "}}"),
  )
  let pipeline = @lower.prepare_fragment_pipeline(sequence, 1, {
    max_roots: 100,
    max_pointer_bytes: 10000,
    max_work: 100000,
  }).unwrap()
  @lower.prepare_fragment_request(pipeline, rows, 1000L).unwrap()
}

///|
test "canonical request has an independently fixed preimage and CID" {
  let artifact = prepare_request_artifact(
      artifact_request("{\"literal\":7}", 10L),
      10000,
      1000,
      100,
    ).unwrap().artifact
  assert_eq(
    @identity.stringify_value(artifact.value, 10000, 1000, 100),
    "{\"max_rows\":10,\"max_value_bytes\":1000,\"parameters\":{},\"pipeline\":{\"output\":\"derive_1\",\"sources\":{\"input\":{\"sort\":\"relation\"}},\"steps\":[{\"id\":\"derive_1\",\"in\":[\"input\"],\"op\":\"REL.derive\",\"params\":{\"exprs\":{\"x\":{\"literal\":7}}}}],\"version\":\"aoa-pipeline/0.1\"},\"source_schemas\":{\"input\":{\"a\":{\"nullable\":false,\"type\":\"number\"},\"b\":{\"nullable\":false,\"type\":\"number\"}}}}",
  )
  // Independently hashed from the literal preimage, not product output.
  assert_eq(
    artifact.cid,
    "sha256:11c9b5fc86de8efc9792c74139f1c36211c1f22a44d6c20a964d35889eca1cbc",
  )
  assert_eq(artifact.bytes, 363)
}

///|
test "request identity retains ownership ceilings and opaque literal values" {
  let request = artifact_request("{\"literal\":{\"z\":1,\"a\":[2,3]}}", 10L)
  let a = prepare_request_artifact(request, 10000, 1000, 100).unwrap()
  let b = prepare_request_artifact(
    artifact_request("{\"literal\":{\"a\":[2,3],\"z\":1}}", 10L),
    10000,
    1000,
    100,
  ).unwrap()
  let c = prepare_request_artifact(
    artifact_request("{\"literal\":{\"a\":[3,2],\"z\":1}}", 10L),
    10000,
    1000,
    100,
  ).unwrap()
  let d = prepare_request_artifact(
    artifact_request("{\"literal\":{\"a\":[2,3],\"z\":1}}", 11L),
    10000,
    1000,
    100,
  ).unwrap()
  assert_true(physical_equal(a.request, request))
  assert_eq(a.artifact.cid, b.artifact.cid)
  assert_true(a.artifact.cid != c.artifact.cid)
  assert_true(a.artifact.cid != d.artifact.cid)
  let bytes = a.artifact.bytes
  assert_true(prepare_request_artifact(request, bytes, 1000, 100) is Ok(_))
  assert_true(
    prepare_request_artifact(request, bytes - 1, 1000, 100) is Err(OutputLimit),
  )
  assert_true(
    prepare_request_artifact(request, 10000, 1, 100) is Err(OutputLimit),
  )
  assert_true(
    prepare_request_artifact(request, 10000, 1000, 0) is Err(OutputLimit),
  )
  assert_true(
    prepare_request_artifact(request, -1, 1000, 100) is Err(InvalidLimits),
  )
}
