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
    "\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"" +
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
fn components_capacity_material(
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
  let input = query_capacity_proof(
    "actql.bound.values",
    rows,
    "{\"op\":\"source\"}",
    step=0,
  )
  let input_cid = @wire.cid(@wire.program_proof_witness(input))
  let graph = query_capacity_proof(
    "actql.bound.graph-nodes",
    rows,
    "{\"op\":\"source\"}",
    inputs=[input_cid],
    step=0,
    unit="nodes",
  )
  let graph_cid = @wire.cid(@wire.program_proof_witness(graph))
  let nodes = query_capacity_proof(
    "actql.bound.components-input-nodes",
    rows,
    "{\"op\":\"source\"}",
    inputs=[graph_cid],
    step~,
    unit="nodes",
  )
  let output = query_capacity_proof(
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
    let body = "{\"author_guard_binding\":\"absent\",\"breach\":\"fail\",\"candidates\":[" +
      texts.join(",") +
      "],\"effective_max\":" +
      maximum.to_string() +
      ",\"enforcement\":\"engine_atomic\",\"subject_ref\":\"components:checked-step:" +
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

///|
fn traversal_capacity_material(
  environment : @environment.WireEnvironment,
  stage : String,
  operation : String,
  step? : Int = 1,
  input_rows? : Int64 = 2L,
  output_rows? : Int64 = 2L,
  selector_rows? : Int64? = None,
  predicate_selector? : Bool = false,
  path_emission? : Bool = false,
) -> @context.StageCapacityInput raise {
  let policy = @environment.capacity_policy(
    @environment.read_capacity(environment, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 30,
    }).unwrap(),
  )
  let witnesses : Array[@wire.WireWitness] = []
  let proofs : Array[@wire.ProgramProofClaim] = []
  if operation == "traverse" {
    let input = query_capacity_proof(
      "actql.bound.values",
      input_rows,
      "{\"op\":\"source\"}",
      step=0,
    )
    let graph = query_capacity_proof(
      "actql.bound.graph-nodes",
      input_rows,
      "{\"op\":\"source\"}",
      inputs=[@wire.cid(@wire.program_proof_witness(input))],
      step=0,
      unit="nodes",
    )
    proofs.push(input)
    proofs.push(graph)
    let output_inputs = [@wire.cid(@wire.program_proof_witness(graph))]
    if selector_rows is Some(rows) {
      let selector = query_capacity_proof(
        "actql.bound.values",
        rows,
        "{\"op\":\"source\"}",
        step=0,
      )
      proofs.push(selector)
      output_inputs.push(@wire.cid(@wire.program_proof_witness(selector)))
    }
    if !path_emission {
      let output = query_capacity_proof(
        "actql.bound.traverse-nodes",
        output_rows,
        "{\"op\":\"source\"}",
        inputs=output_inputs,
        step~,
      )
      proofs.push(output)
    }
    for proof in proofs {
      witnesses.push(@wire.program_proof_witness(proof))
    }
  } else if operation == "shortest_path" {
    let output_inputs : Array[String] = []
    if predicate_selector {
      let input = query_capacity_proof(
        "actql.bound.values",
        2L,
        "{\"op\":\"source\"}",
        step=0,
      )
      let graph = query_capacity_proof(
        "actql.bound.graph-nodes",
        2L,
        "{\"op\":\"source\"}",
        inputs=[@wire.cid(@wire.program_proof_witness(input))],
        step=0,
        unit="nodes",
      )
      proofs.push(input)
      proofs.push(graph)
      output_inputs.push(@wire.cid(@wire.program_proof_witness(graph)))
    } else if selector_rows is Some(rows) {
      let selector = query_capacity_proof(
        "actql.bound.values",
        rows,
        "{\"op\":\"source\"}",
        step=0,
      )
      proofs.push(selector)
      let selector_cid = @wire.cid(@wire.program_proof_witness(selector))
      // Source and target are distinct ordered input edges even when they
      // select the same material.
      output_inputs.push(selector_cid)
      output_inputs.push(selector_cid)
    }
    let output = query_capacity_proof(
      "actql.bound.shortest-path",
      output_rows,
      "{\"op\":\"source\"}",
      inputs=output_inputs,
      step~,
    )
    proofs.push(output)
    for proof in proofs {
      witnesses.push(@wire.program_proof_witness(proof))
    }
  }
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
    if (
        operation == "shortest_path" ||
        (operation == "traverse" && !path_emission)
      ) &&
      unit == "rows" {
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
    max_entities: 12,
    max_references: 24,
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
