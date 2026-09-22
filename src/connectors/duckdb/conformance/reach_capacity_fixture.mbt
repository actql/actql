///|
// Integrity-valid capacity evidence for a fixed traversal fixture.
fn traversal_fixture_proof(
  law : String,
  value : Int64,
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
    "],\"derivation\":{\"op\":\"source\"},\"law_id\":\"" +
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
fn traversal_fixture_capacity(
  environment : @environment.WireEnvironment,
  stage : String,
  operation : String,
  step? : Int = 1,
  path_emission? : Bool = false,
) -> @context.StageCapacityInput raise {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let proofs : Array[@wire.ProgramProofClaim] = []
  if operation == "traverse" {
    let input = traversal_fixture_proof("actql.bound.values", 40L, step=0)
    let graph = traversal_fixture_proof(
      "actql.bound.graph-nodes",
      40L,
      inputs=[@wire.cid(@wire.program_proof_witness(input))],
      step=0,
      unit="nodes",
    )
    proofs.push(input)
    proofs.push(graph)
    if !path_emission {
      let output = traversal_fixture_proof(
        "actql.bound.traverse-nodes",
        40L,
        inputs=[@wire.cid(@wire.program_proof_witness(graph))],
        step~,
      )
      proofs.push(output)
    }
  }
  let witnesses = proofs.map(@wire.program_proof_witness)
  let artifacts : Array[(Bytes, String)] = []
  for
    (field, unit, suffix) in [
      ("max_graph_paths", "paths", ":paths"),
      ("max_graph_output_rows", "rows", ""),
    ] {
    let host = @host.create(@capacity_policy.ceiling(policy, field).unwrap(), {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap()
    let writer = @encode.writer(10000, 1000, 30)
    @host.emit(host, writer)
    let text = @encode.finish(writer)
    let wire = @wire.admit(@utf8.encode(text), @host.cid(host), {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap()
    witnesses.push(wire)
    let candidates = [wire]
    if operation == "traverse" && !path_emission && unit == "rows" {
      candidates.push(@wire.program_proof_witness(proofs[proofs.length() - 1]))
      candidates.sort_by((a, b) => @wire.cid(a).compare(@wire.cid(b)))
    }
    let texts = candidates.map(candidate => {
      let writer = @encode.writer(10000, 1000, 30)
      @wire.emit(candidate, writer)
      @encode.finish(writer)
    })
    let mut effective = @wire.value(candidates[0])
    for candidate in candidates {
      effective = Int64::min(effective, @wire.value(candidate))
    }
    let prefix = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\"," +
      "\"candidates\":[" +
      texts.join(",") +
      "],\"effective_max\":" +
      effective.to_string() +
      ",\"enforcement\":\"engine_atomic\""
    let tail = ",\"subject_ref\":\"" +
      operation +
      ":checked-step:" +
      step.to_string() +
      suffix +
      "\",\"unit\":\"" +
      unit +
      "\",\"version\":\"actql-resolved-limit/0.1\"}"
    let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + tail))
    artifacts.push(
      (
        @utf8.encode(prefix + ",\"resolved_limit_cid\":\"" + cid + "\"" + tail),
        cid,
      ),
    )
  }
  let mixed = @wire.check_mixed_claims(witnesses, artifacts, {
    max_entities: 10,
    max_references: 20,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, proofs, {
    max_witnesses: 20,
    max_references: 100,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [policy], {
    max_entries: 20,
    max_bytes: 20000,
    max_nodes: 2000,
    max_depth: 30,
  }).unwrap()
  {
    stage,
    sources,
    uses: [
      @context.Traversal(
        step~,
        paths=@wire.mixed_limit_at(mixed, 0).unwrap(),
        output=@wire.mixed_limit_at(mixed, 1).unwrap(),
      ),
    ],
  }
}

///|
// Host-ceiling capacity evidence for the fixed reach conformance fixture.
// Reach does not require an authored proof for either traversal limit.
fn reach_fixture_capacity(
  environment : @environment.WireEnvironment,
  stage : String,
  step? : Int = 1,
) -> @context.StageCapacityInput raise {
  traversal_fixture_capacity(environment, stage, "reach", step~)
}

///|
fn traverse_fixture_capacity(
  environment : @environment.WireEnvironment,
  stage : String,
  step? : Int = 1,
  path_emission? : Bool = false,
) -> @context.StageCapacityInput raise {
  traversal_fixture_capacity(
    environment,
    stage,
    "traverse",
    step~,
    path_emission~,
  )
}
