///|
/// Authored fixture material for join step zero and the catalog's fixed 10000
/// row Host ceiling. This is input to the checker, not an expected result
/// generated from a checked Program or an execution result.
fn join_graph_capacity_material(
  environment : @environment.WireEnvironment,
  stage : String,
  steps? : Array[Int] = [0],
  proofs? : Array[@wire.ProgramProofClaim] = [],
  candidates? : Array[@wire.ProgramProofClaim] = [],
) -> @context.StageCapacityInput raise {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let host = @host.create(
    @capacity_policy.ceiling(policy, "max_relation_output_rows").unwrap(),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, },
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 30)
  @host.emit(host, writer)
  let host_text = @encode.finish(writer)
  let witness = @wire.admit(@utf8.encode(host_text), @host.cid(host), {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let candidate_wires = candidates.map(@wire.program_proof_witness)
  candidate_wires.push(witness)
  candidate_wires.sort_by((a, b) => @wire.cid(a).compare(@wire.cid(b)))
  let candidate_text = candidate_wires.map(candidate => {
    let writer = @encode.writer(10000, 1000, 30)
    @wire.emit(candidate, writer)
    @encode.finish(writer)
  })
  let mut effective_max = @wire.value(candidate_wires[0])
  for candidate in candidate_wires {
    effective_max = Int64::min(effective_max, @wire.value(candidate))
  }
  let body = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
    candidate_text.join(",") +
    "],\"effective_max\":" +
    effective_max.to_string() +
    ",\"enforcement\":\"engine_atomic\",\"subject_ref\":\"join:checked-step:0:output\",\"unit\":\"rows\",\"version\":\"actql-resolved-limit/0.1\"}"
  let artifacts = steps.map(step => {
    let body = body.replace(
      old="checked-step:0:",
      new="checked-step:" + step.to_string() + ":",
    )
    let cid = "sha256:" + @sha.hex(@utf8.encode(body))
    let resolved = body.replace(
      old="\"subject_ref\":",
      new="\"resolved_limit_cid\":\"" + cid + "\",\"subject_ref\":",
    )
    (@utf8.encode(resolved), cid)
  })
  let witnesses = proofs.map(@wire.program_proof_witness)
  witnesses.push(witness)
  let mixed = @wire.check_mixed_claims(witnesses, artifacts, {
    max_entities: 10,
    max_references: 20,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, proofs, {
    max_witnesses: 10,
    max_references: 20,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [policy], {
    max_entries: 10,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  {
    stage,
    sources,
    uses: Array::makei(steps.length(), i => {
      Join(step=steps[i], output=@wire.mixed_limit_at(mixed, i).unwrap())
    }),
  }
}

///|
// Integrity-valid authored capacity evidence for a fixed fixture operation.
// Application and ownership remain the formal checker's responsibility.
fn query_capacity_proof(
  law : String,
  value : Int64,
  derivation : String,
  inputs? : Array[String] = [],
) -> @wire.ProgramProofClaim {
  let input_text = inputs.map(value => "\"" + value + "\"").join(",")
  let proof_body = "{\"inputs\":[" +
    input_text +
    "],\"law_id\":\"" +
    law +
    "\",\"semantic_ref\":\"checked-step:0\",\"unit\":\"rows\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-proof/0.1\"}"
  let proof_cid = "sha256:" + @sha.hex(@utf8.encode(proof_body))
  let dependencies = inputs.copy()
  dependencies.push(proof_cid)
  dependencies.sort()
  let unique_dependencies : Array[String] = []
  for dependency in dependencies {
    if !unique_dependencies.contains(dependency) {
      unique_dependencies.push(dependency)
    }
  }
  let dependency_text = unique_dependencies
    .map(value => "\"" + value + "\"")
    .join(",")
  let prefix = "{\"dependencies\":[" +
    dependency_text +
    "],\"derivation\":" +
    derivation +
    ",\"law_id\":\"" +
    law +
    "\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"" +
    proof_cid +
    "\",\"semantic_ref\":\"checked-step:0\"},\"unit\":\"rows\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-witness/0.1\""
  let witness_cid = "sha256:" + @sha.hex(@utf8.encode(prefix + "}"))
  let limits : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let witness = @wire.admit(
    @utf8.encode(prefix + ",\"witness_cid\":\"" + witness_cid + "\"}"),
    witness_cid,
    limits,
  ).unwrap()
  @wire.bind_program_proof(@utf8.encode(proof_body), witness, limits).unwrap()
}
