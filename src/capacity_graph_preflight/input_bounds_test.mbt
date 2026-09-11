///|
fn input_bound_pipeline(body : String) -> @pipeline.CheckedPipeline {
  let rows = @carrier.typed_rows(
    @schema.from_object(
      @contract.object_contract(
        [],
        nullable=false,
        max_fields=0,
        max_name_bytes=0,
      ).unwrap(),
    ).unwrap(),
  )
  let graph = @carrier.graph(
    @contract.primitive(StringType, nullable=false),
    rows,
    rows,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  @pipeline.check_carriers(closure_cursor(body), [("g", graph)], None, None, {
    max_steps: 20,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 100,
  }).unwrap()
}

///|
test "Graph input bounds retain exact preflight owners and enforce measure roles" {
  let policy = policy(false)
  for
    (op, measure, law) in [
      ("node_rows", @input.Nodes, "actql.bound.graph-node-rows"),
      ("edge_rows", @input.Edges, "actql.bound.graph-edge-rows"),
    ] {
    let pipeline = input_bound_pipeline("[{\"" + op + "\":true}]")
    let standalone = sources(0, policy)
    let first = @input.check(pipeline, standalone, policy, caps()).unwrap()
    let original = @input.input_bound(first, 0, measure).unwrap()
    let id = @wire.cid(@input.bound_witness(original))
    let proof = graph_proof(law, 1L, "{\"op\":\"source\"}", inputs=[id])
    let sources = sources(0, policy, proofs=[proof])
    let owner = @input.check(pipeline, sources, policy, caps()).unwrap()
    let bound = @input.input_bound(owner, 0, measure).unwrap()
    assert_true(physical_equal(@input.bound_owner(bound), owner))
    assert_eq(@input.bound_input(bound), 0)
    assert_true(@input.input_bound(owner, -1, measure) is None)
    assert_true(@input.input_bound(owner, 1, measure) is None)
    let dependencies = [@program.GraphInput(bound)]
    let application = @program.check_with_sources(
      pipeline, 0, proof, dependencies,
    ).unwrap()
    dependencies.clear()
    assert_eq(@program.input_count(application), 1)
    assert_true(@program.input_at(application, 0) is None)
    guard @program.source_at(application, 0)
      is Some(@program.GraphInput(retained)) else {
      abort("missing retained Graph source")
    }
    assert_true(physical_equal(bound, retained))
    assert_eq(@program.input_work(application), 0)
    let collection = @host.source_claims(sources)
    let applications = @program.check_applications(
      collection,
      [application],
      max_work=100,
    ).unwrap()
    assert_true(
      @capacity_graph_preflight.check_source_coverage(
        owner,
        applications,
        max_work=100,
      )
      is Ok(_),
    )
    let exact = @program.application_work(applications)
    assert_true(
      @program.check_applications(collection, [application], max_work=exact)
      is Ok(_),
    )
    assert_true(
      @program.check_applications(collection, [application], max_work=exact - 1)
      is Err(WorkLimit),
    )
    // Equal witness bytes from a separately admitted collection are not owners.
    let detached = @program.check_with_sources(pipeline, 0, proof, [
      @program.GraphInput(original),
    ]).unwrap()
    assert_true(
      @program.check_applications(collection, [detached], max_work=100)
      is Err(ForeignDependency(_, _)),
    )
    let wrong_measure = if measure == @input.Nodes {
      @input.Edges
    } else {
      @input.Nodes
    }
    assert_true(
      @program.check_with_sources(pipeline, 0, proof, [
        @program.GraphInput(
          @input.input_bound(owner, 0, wrong_measure).unwrap(),
        ),
      ])
      is Err(InputUnitMismatch(0)),
    )
    let other = input_bound_pipeline("[{\"" + op + "\":true}]")
    assert_true(
      @program.check_with_sources(
        other,
        0,
        proof,
        [@program.GraphInput(bound)],
        max_input_work=10,
      )
      is Err(MissingInputProducer(0)),
    )
    assert_true(
      @program.check_with_sources(pipeline, 0, proof, [])
      is Err(InputCountMismatch),
    )
  }
}

///|
test "Graph source bounds compose through repeated union inputs and row bridges" {
  let policy = policy(false)
  let pipeline = input_bound_pipeline(
    "[{\"union_graphs\":{\"with\":[\"g\",\"g\"]},\"as\":\"merged\"},{\"node_rows\":true},{\"from\":\"merged\",\"edge_rows\":true},{\"take\":2}]",
  )
  for
    (measure, unit, bridge, law) in [
      (@input.Nodes, "nodes", 1, "actql.bound.graph-node-rows"),
      (@input.Edges, "edges", 2, "actql.bound.graph-edge-rows"),
    ] {
    let first = @input.check(pipeline, sources(0, policy), policy, caps()).unwrap()
    let id = @wire.cid(
      @input.bound_witness(@input.input_bound(first, 0, measure).unwrap()),
    )
    let combined = graph_proof(
      "actql.bound.graph-" + unit,
      3L,
      "{\"op\":\"source\"}",
      unit~,
      inputs=[id, id, id],
    )
    let projected = graph_proof(
      law,
      3L,
      "{\"op\":\"source\"}",
      reference="checked-step:" + bridge.to_string(),
      inputs=[@wire.cid(@wire.program_proof_witness(combined))],
    )
    let sources = sources(0, policy, proofs=[combined, projected])
    let root = @input.check(pipeline, sources, policy, caps()).unwrap()
    let operand = @program.GraphInput(
      @input.input_bound(root, 0, measure).unwrap(),
    )
    let inputs = [operand, operand, operand]
    assert_true(
      @program.check_with_sources(
        pipeline,
        0,
        combined,
        inputs,
        max_operand_work=14,
      )
      is Err(OperandWorkLimit),
    )
    let union = @program.check_with_sources(
      pipeline,
      0,
      combined,
      inputs,
      max_operand_work=15,
    ).unwrap()
    assert_eq(@program.operand_work(union), 15)
    assert_eq(@program.input_count(union), 3)
    let output = @program.check_with_inputs(pipeline, bridge, projected, [union]).unwrap()
    let apps = @program.check_applications(
      @host.source_claims(sources),
      [union, output],
      max_work=100,
    ).unwrap()
    assert_true(
      @capacity_graph_preflight.check_source_coverage(root, apps, max_work=100)
      is Ok(_),
    )
    // A graph measure cannot stand in for a row count, even with the same value.
    let take = graph_proof(
      "actql.bound.take",
      1L,
      "{\"input\":\"" + id + "\",\"maximum\":2,\"op\":\"clamp\"}",
      reference="checked-step:3",
      inputs=[id],
    )
    assert_true(
      @program.check_with_sources(
        pipeline,
        3,
        take,
        [operand],
        max_input_work=10,
      )
      is Err(InputUnitMismatch(0)),
    )
  }
}

///|
test "Graph bounds cross normalization and subgraph without crossing expanding unions" {
  let policy = policy(false)
  for
    (operation, measure, law) in [
      ("node_rows", @input.Nodes, "actql.bound.graph-node-rows"),
      ("edge_rows", @input.Edges, "actql.bound.graph-edge-rows"),
    ] {
    let text = "[{\"normalize_graph\":true},{\"subgraph\":{\"nodes\":{\"ids\":[\"a\"]}}},{\"" +
      operation +
      "\":true}]"
    let p = input_bound_pipeline(text)
    let graph = @input.check(p, sources(0, policy), policy, caps()).unwrap()
    let input = @input.input_bound(graph, 0, measure).unwrap()
    let proof = graph_proof(
      law,
      1L,
      "{\"op\":\"source\"}",
      reference="checked-step:2",
      inputs=[@wire.cid(@input.bound_witness(input))],
    )
    let app = @program.check_with_sources(
      p,
      2,
      proof,
      [@program.GraphInput(input)],
      max_input_work=2,
    ).unwrap()
    assert_eq(@program.input_work(app), 2)
    guard @program.source_at(app, 0) is Some(@program.GraphInput(retained)) else {
      abort("missing original preflight")
    }
    assert_true(physical_equal(@input.bound_owner(retained), graph))
    assert_true(
      @program.check_with_sources(
        p,
        2,
        proof,
        [@program.GraphInput(input)],
        max_input_work=1,
      )
      is Err(InputWorkLimit),
    )
    let expanded = input_bound_pipeline(
      "[{\"union_graphs\":{\"with\":\"g\"}},{\"normalize_graph\":true},{\"" +
      operation +
      "\":true}]",
    )
    let root = @input.check(expanded, sources(0, policy), policy, caps()).unwrap()
    assert_true(
      @program.check_with_sources(
        expanded,
        2,
        proof,
        [@program.GraphInput(@input.input_bound(root, 0, measure).unwrap())],
        max_input_work=2,
      )
      is Err(InputTargetMismatch(0)),
    )
  }
}

///|
test "Graph preflight bounds follow actual imported owners under cumulative traversal budgets" {
  let policy = policy(false)
  let base = input_bound_pipeline("[]")
  let sources = sources(0, policy)
  let preflight = @input.check(base, sources, policy, caps()).unwrap()
  let bound = @input.input_bound(preflight, 0, Nodes).unwrap()
  let input = @pipeline.ProducedInput(
    @pipeline.produced_input(base, Input(0)).unwrap(),
  )
  let receiver = @pipeline.check_with_evidence(
    closure_cursor("[{\"node_rows\":true}]"),
    [("imported", input)],
    None,
    None,
    {
      max_steps: 1,
      max_work: 1000,
      max_text_bytes: 1000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 20,
    },
  ).unwrap()
  let proof = graph_proof(
    "actql.bound.graph-node-rows",
    1L,
    "{\"op\":\"source\"}",
    inputs=[@wire.cid(@input.bound_witness(bound))],
  )
  assert_true(
    @program.check_with_sources(receiver, 0, proof, [@program.GraphInput(bound)])
    is Err(InputWorkLimit),
  )
  let app = @program.check_with_sources(
    receiver,
    0,
    proof,
    [@program.GraphInput(bound)],
    max_input_work=1,
  ).unwrap()
  assert_eq(@program.input_work(app), 1)
  let other = input_bound_pipeline("[]")
  let foreign = @input.check(other, sources, policy, caps()).unwrap()
  assert_true(
    @program.check_with_sources(
      receiver,
      0,
      proof,
      [@program.GraphInput(@input.input_bound(foreign, 0, Nodes).unwrap())],
      max_input_work=2,
    )
    is Err(MissingInputProducer(0)),
  )
}

///|
// Integrity-valid fixtures; application truth is independently asserted below.
fn graph_proof(
  law : String,
  value : Int64,
  derivation : String,
  reference? : String = "checked-step:0",
  unit? : String = "rows",
  inputs? : Array[String] = [],
) -> @wire.ProgramProofClaim {
  let body = "{\"inputs\":" +
    cid_array(inputs) +
    ",\"law_id\":\"" +
    law +
    "\",\"semantic_ref\":\"" +
    reference +
    "\",\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-proof/0.1\"}"
  let id = "sha256:" + @sha.hex(@utf8.encode(body))
  let dependencies = inputs.copy()
  dependencies.push(id)
  let preimage = "{\"dependencies\":" +
    cid_array(dependencies, unique=true) +
    ",\"derivation\":" +
    derivation +
    ",\"law_id\":\"" +
    law +
    "\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"" +
    id +
    "\",\"semantic_ref\":\"" +
    reference +
    "\"},\"unit\":\"" +
    unit +
    "\",\"value\":" +
    value.to_string() +
    ",\"version\":\"actql-bound-witness/0.1\""
  let cid = "sha256:" + @sha.hex(@utf8.encode(preimage + "}"))
  let bytes = @utf8.encode(preimage + ",\"witness_cid\":\"" + cid + "\"}")
  let caps : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let wire = @wire.admit(bytes, cid, caps).unwrap()
  @wire.bind_program_proof(@utf8.encode(body), wire, caps).unwrap()
}

///|
fn cid_array(ids : Array[String], unique? : Bool = false) -> String {
  let ordered : Array[String] = []
  for id in ids {
    if unique && ordered.contains(id) {
      continue
    }
    ordered.push(id)
    let mut i = ordered.length() - 1
    while i > 0 && ordered[i] < ordered[i - 1] {
      let previous = ordered[i - 1]
      ordered[i - 1] = ordered[i]
      ordered[i] = previous
      i = i - 1
    }
  }
  "[" + ordered.map(id => "\"" + id + "\"").join(",") + "]"
}
