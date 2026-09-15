///|
fn capacity_values_pipeline(
  rows : String,
  twice? : Bool = false,
) -> @pipeline.CheckedPipeline {
  let item = "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
    rows +
    "},\"as\":\"seed\"}"
  let text = "[" +
    item +
    (if twice { "," + item.replace(old="seed", new="other") } else { "" }) +
    "]"
  let parsed = @source.parse_json(text, {
    max_input_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }).unwrap()
  let admitted = @decode.admit(parsed, {
    max_nodes: 1000,
    max_depth: 100,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
  @pipeline.check(admitted, [], None, None, {
    max_steps: 2,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
}

///|
test "values capacity registration charges count artifacts once and preserves source slots" {
  let pipeline = capacity_values_pipeline("[]", twice=true)
  let original : CapacityMaterial = {
    sources: empty_capacity_input_sources(),
    consumers: [],
  }
  // Independent complete-artifact scope: each single-digit ordinal/count pair
  // is 606 UTF-8 bytes and 22 structural nodes. Two definitions require both.
  let metadata : @wire.Limits = {
    max_bytes: 1212,
    max_nodes: 44,
    max_depth: 10,
  }
  // Two steps + two 14-character subjects + 44 metadata nodes + graph's four
  // entities and two references. This is not measured from a prior run.
  let work = 2 + 2 * 14 + 44 + 4 + 2
  let result = derive_values_capacity_material(
    pipeline, original, work, metadata,
  ).unwrap()
  assert_eq(result.work, work)
  assert_eq(result.metadata_bytes, 1212)
  assert_eq(result.metadata_nodes, 44)
  assert_eq(result.slots, [Some(0), Some(1)])
  let claims = @host.source_claims(result.material.sources)
  for i in 0..<2 {
    let proof = @wire.program_claim_proof_at(claims, i).unwrap()
    assert_eq(@wire.value(@wire.program_proof_witness(proof)), 0L)
    assert_true(@step_bounds.check(pipeline, i, proof) is Ok(_))
  }
  for
    (w, m) in [
      (work - 1, metadata),
      (work, { ..metadata, max_bytes: 1211, }),
      (work, { ..metadata, max_nodes: 43, }),
    ] {
    assert_true(
      derive_values_capacity_material(pipeline, original, w, m) is Err(_),
    )
  }
  let reused = derive_values_capacity_material(
    pipeline,
    result.material,
    1000,
    { max_bytes: 0, max_nodes: 0, max_depth: 0, },
  ).unwrap()
  assert_eq(reused.metadata_bytes, 0)
  assert_eq(reused.metadata_nodes, 0)
  assert_eq(reused.slots, result.slots)
  assert_true(physical_equal(reused.material.sources, result.material.sources))
  assert_eq(
    @wire.claim_count(
      @wire.program_claim_arithmetic(@host.source_claims(original.sources)),
    ),
    0,
  )
}

///|
test "values capacity registration does not replace a different producer count" {
  let other = capacity_values_pipeline("[{\"id\":1}]")
  let empty = capacity_values_pipeline("[]")
  let base : CapacityMaterial = {
    sources: empty_capacity_input_sources(),
    consumers: [],
  }
  let metadata : @wire.Limits = {
    max_bytes: 606,
    max_nodes: 22,
    max_depth: 10,
  }
  let supplied = derive_values_capacity_material(other, base, 1000, metadata).unwrap()
  let result = derive_values_capacity_material(
    empty,
    supplied.material,
    1000,
    metadata,
  ).unwrap()
  assert_eq(result.slots, [Some(1)])
  let before = @host.source_claims(supplied.material.sources)
  let after = @host.source_claims(result.material.sources)
  assert_true(
    physical_equal(
      @wire.program_claim_proof_at(before, 0).unwrap(),
      @wire.program_claim_proof_at(after, 0).unwrap(),
    ),
  )
  assert_eq(
    @wire.value(
      @wire.program_proof_witness(
        @wire.program_claim_proof_at(after, 1).unwrap(),
      ),
    ),
    0L,
  )
}
