///|
// Integrity-valid authored capacity evidence for the fixed components
// publication fixture. Application and ownership remain checker duties.
fn components_fixture_proof(
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
fn components_fixture_capacity(
  environment : @environment.WireEnvironment,
  stage : String,
  step? : Int = 1,
  rows? : Int64 = 2L,
) -> @context.StageCapacityInput raise {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let input = components_fixture_proof(
    "actql.bound.values", rows, "{\"op\":\"source\"}",
  )
  let input_cid = @wire.cid(@wire.program_proof_witness(input))
  let graph = components_fixture_proof(
    "actql.bound.graph-nodes",
    rows,
    "{\"op\":\"source\"}",
    inputs=[input_cid],
    unit="nodes",
  )
  let graph_cid = @wire.cid(@wire.program_proof_witness(graph))
  let nodes = components_fixture_proof(
    "actql.bound.components-input-nodes",
    rows,
    "{\"op\":\"source\"}",
    inputs=[graph_cid],
    step~,
    unit="nodes",
  )
  let output = components_fixture_proof(
    "actql.bound.components-nodes",
    rows,
    "{\"op\":\"source\"}",
    inputs=[graph_cid],
    step~,
  )
  let host = @host.create(
    @capacity_policy.ceiling(policy, "max_graph_output_rows").unwrap(),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, },
  ).unwrap()
  let writer = @encode.writer(10000, 1000, 30)
  @host.emit(host, writer)
  let host_wire = @wire.admit(
    @utf8.encode(@encode.finish(writer)),
    @host.cid(host),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, },
  ).unwrap()
  let proof_wires = [
    @wire.program_proof_witness(input),
    @wire.program_proof_witness(graph),
    @wire.program_proof_witness(nodes),
    @wire.program_proof_witness(output),
  ]
  let artifacts : Array[(Bytes, String)] = []
  for
    (unit, suffix, candidates) in [
      ("nodes", ":nodes", [proof_wires[2]]),
      ("rows", "", [proof_wires[3], host_wire]),
    ] {
    candidates.sort_by((a, b) => @wire.cid(a).compare(@wire.cid(b)))
    let texts = candidates.map(candidate => {
      let writer = @encode.writer(10000, 1000, 30)
      @wire.emit(candidate, writer)
      @encode.finish(writer)
    })
    let mut maximum = @wire.value(candidates[0])
    for candidate in candidates {
      maximum = Int64::min(maximum, @wire.value(candidate))
    }
    let body = "{\"author_guard_binding\":\"absent\"," +
      "\"breach\":\"fail\",\"candidates\":[" +
      texts.join(",") +
      "],\"effective_max\":" +
      maximum.to_string() +
      ",\"enforcement\":\"engine_atomic\"," +
      "\"subject_ref\":\"components:checked-step:" +
      step.to_string() +
      suffix +
      "\",\"unit\":\"" +
      unit +
      "\",\"version\":\"actql-resolved-limit/0.1\"}"
    let cid = "sha256:" + @sha.hex(@utf8.encode(body))
    artifacts.push(
      (
        @utf8.encode(
          body.replace(
            old="\"subject_ref\":",
            new="\"resolved_limit_cid\":\"" + cid + "\",\"subject_ref\":",
          ),
        ),
        cid,
      ),
    )
  }
  let witnesses = proof_wires.copy()
  witnesses.push(host_wire)
  let mixed = @wire.check_mixed_claims(witnesses, artifacts, {
    max_entities: 10,
    max_references: 20,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(
    mixed,
    [input, graph, nodes, output],
    { max_witnesses: 20, max_references: 100, },
  ).unwrap()
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
      @context.Components(
        step~,
        nodes=@wire.mixed_limit_at(mixed, 0).unwrap(),
        output=@wire.mixed_limit_at(mixed, 1).unwrap(),
      ),
    ],
  }
}
