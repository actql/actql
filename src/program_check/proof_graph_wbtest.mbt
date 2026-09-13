///|
test "persistent proof graph preserves repeated append operands and shared ownership" {
  let budget = IdentityBudget::{
    work: 100000000,
    bytes: 10000000,
    nodes: 1000000,
    depth: 100,
  }
  let (_, _, _, _, original_units) = remote_construction_fixture(budget)
  let node = @source.parse_json(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"append\":{\"with\":\"seed\"}}]",
    { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
  ).unwrap()
  let cursor = @decode.admit(node, {
    max_nodes: 1000,
    max_depth: 100,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
  let pipeline = @pipeline.check(cursor, [], None, None, {
    max_steps: 10,
    max_work: 100000,
    max_text_bytes: 10000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 100,
  }).unwrap()
  // Synthetic Unit fixture for conversion only, not a closed Program result.
  let units = [
    {
      ..original_units[0],
      pipeline,
      definition_cid: "sha256:" + "0".repeat(64),
    },
  ]
  let seed_proof = keyed_sourceview_claim()
  let seed = @step_bounds.check(units[0].pipeline, 0, seed_proof).unwrap()
  let input = @wire.cid(@wire.program_proof_witness(seed_proof))
  // These hashes build fixture inputs, not expected conversion outputs.
  let proof_body = "{\"inputs\":[\"\{input}\",\"\{input}\"],\"law_id\":\"actql.bound.append\",\"semantic_ref\":\"checked-step:1\",\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-proof/0.1\"}"
  let proof_cid = "sha256:" + @sha.hex(@utf8.encode(proof_body))
  let dependencies = if input < proof_cid {
    "[\"\{input}\",\"\{proof_cid}\"]"
  } else {
    "[\"\{proof_cid}\",\"\{input}\"]"
  }
  let body = "{\"dependencies\":\{dependencies},\"derivation\":{\"left\":\"\{input}\",\"op\":\"add\",\"right\":\"\{input}\"},\"law_id\":\"actql.bound.append\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"\{proof_cid}\",\"semantic_ref\":\"checked-step:1\"},\"unit\":\"rows\",\"value\":2,\"version\":\"actql-bound-witness/0.1\""
  let cid = "sha256:" + @sha.hex(@utf8.encode(body + "}"))
  let caps : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let witness = @wire.admit(
    @utf8.encode(body + ",\"witness_cid\":\"\{cid}\"}"),
    cid,
    caps,
  ).unwrap()
  let proof = @wire.bind_program_proof(@utf8.encode(proof_body), witness, caps).unwrap()
  let bound = @step_bounds.check_with_inputs(units[0].pipeline, 1, proof, [
    seed, seed,
  ]).unwrap()
  let converted = reidentify_step_graph(units, bound, budget)
  assert_eq(converted.inputs.length(), 2)
  assert_true(physical_equal(converted.inputs[0], converted.inputs[1]))
  let child = @wire.program_proof_witness(converted.inputs[0].proof)
  let output = @wire.program_proof_witness(converted.proof)
  assert_false(@wire.cid(child) == input)
  assert_true(
    @wire.derivation(output) is Add(a, b) && a == @wire.cid(child) && b == a,
  )
  assert_eq(@wire.program_proof_input_count(converted.proof), 2)
  for i in 0..<2 {
    assert_eq(
      @wire.program_proof_input_at(converted.proof, i),
      Some(@wire.cid(child)),
    )
  }
  let arithmetic = @wire.check_arithmetic_claims([child, output], {
    max_witnesses: 2,
    max_references: 10,
  }).unwrap()
  assert_eq(@wire.claim_count(arithmetic), 2)
  assert_eq(@wire.value(output), 2L)
}
