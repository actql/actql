///|
// Integrity-valid authored Graph input evidence. Application and ownership
// remain checker duties; no retired component-output claim is issued.
fn graph_fixture_proof(
  law : String,
  value : Int64,
  derivation : String,
  inputs? : Array[String] = [],
  step? : Int = 0,
  unit? : String = "rows",
) -> @wire.ProgramProofClaim {
  let proof_inputs = inputs.copy()
  proof_inputs.sort()
  let input_text = proof_inputs.map(value => "\"" + value + "\"").join(",")
  let semantic_ref = "checked-step:" + step.to_string()
  let proof_body = "{\"inputs\":[" +
    input_text +
    "],\"law_id\":\"" +
    law +
    "\",\"semantic_ref\":\"" +
    semantic_ref +
    "\",\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-proof/0.1\"}"
  let proof_cid = "sha256:" + @sha.hex(@utf8.encode(proof_body))
  let dependencies = proof_inputs.copy()
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
    "\",\"role\":\"proven_upper_bound\",\"source\":{" +
    "\"kind\":\"program\",\"proof_cid\":\"" +
    proof_cid +
    "\",\"semantic_ref\":\"" +
    semantic_ref +
    "\"},\"unit\":\"" +
    unit +
    "\",\"value\":" +
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

///|
fn graph_fixture_capacity(
  environment : @environment.WireEnvironment,
  stage : String,
  rows : Int64,
  node_rows? : Int64 = rows,
) -> @context.StageCapacityInput {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let input = graph_fixture_proof(
    "actql.bound.values", rows, "{\"op\":\"source\"}",
  )
  let input_cid = @wire.cid(@wire.program_proof_witness(input))
  let nodes = graph_fixture_proof(
    "actql.bound.graph-nodes",
    node_rows,
    "{\"op\":\"source\"}",
    inputs=[input_cid],
    unit="nodes",
  )
  let proof_wires = [
    @wire.program_proof_witness(input),
    @wire.program_proof_witness(nodes),
  ]
  let mixed = @wire.check_mixed_claims(proof_wires, [], {
    max_entities: 10,
    max_references: 20,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [input, nodes], {
    max_witnesses: 20,
    max_references: 100,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [policy], {
    max_entries: 20,
    max_bytes: 20000,
    max_nodes: 2000,
    max_depth: 30,
  }).unwrap()
  { stage, sources, uses: [], }
}
