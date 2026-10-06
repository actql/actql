///|
fn input_bound_pipeline(body : String) -> @pipeline.CheckedPipeline {
  let graph = current_graph_input()
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
    (op, definition, measure, law) in [
      ("match_nodes", "N", @input.Nodes, "actql.bound.match-nodes"),
      ("match_edges", "E", @input.Edges, "actql.bound.match-edges"),
    ] {
    let body = "[{\"" +
      op +
      "\":{\"definition\":\"" +
      definition +
      "\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}}]"
    let pipeline = input_bound_pipeline(body)
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
    let other = input_bound_pipeline(body)
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
test "Graph MATCH bounds cross retained row transformations without losing units" {
  let policy = policy(false)
  for
    (operation, definition, measure, law) in [
      ("match_nodes", "N", @input.Nodes, "actql.bound.match-nodes"),
      ("match_edges", "E", @input.Edges, "actql.bound.match-edges"),
    ] {
    let p = input_bound_pipeline(
      "[{\"" +
      operation +
      "\":{\"definition\":\"" +
      definition +
      "\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}}," +
      "{\"select\":[\"element\"]},{\"derive\":{\"copy\":\"element\"}},{\"take\":2}]",
    )
    let initial = @input.check(p, sources(0, policy), policy, caps()).unwrap()
    let id = @wire.cid(
      @input.bound_witness(@input.input_bound(initial, 0, measure).unwrap()),
    )
    let projected = graph_proof(law, 1L, "{\"op\":\"source\"}", inputs=[id])
    let projected_id = @wire.cid(@wire.program_proof_witness(projected))
    let take = graph_proof(
      "actql.bound.take",
      1L,
      "{\"input\":\"" + projected_id + "\",\"maximum\":2,\"op\":\"clamp\"}",
      reference="checked-step:3",
      inputs=[projected_id],
    )
    let source = sources(0, policy, proofs=[projected, take])
    let graph = @input.check(p, source, policy, caps()).unwrap()
    let input = @program.GraphInput(
      @input.input_bound(graph, 0, measure).unwrap(),
    )
    let rows = @program.check_with_sources(p, 0, projected, [input]).unwrap()
    let downstream = @program.check_with_inputs(
      p,
      3,
      take,
      [rows],
      max_input_work=2,
    ).unwrap()
    assert_eq(@program.input_work(downstream), 2)
    assert_true(physical_equal(@program.input_at(downstream, 0).unwrap(), rows))
    let collection = @program.check_applications(
      @host.source_claims(source),
      [rows, downstream],
      max_work=100,
    ).unwrap()
    assert_true(
      @capacity_graph_preflight.check_source_coverage(
        graph,
        collection,
        max_work=100,
      )
      is Ok(_),
    )
    assert_true(
      @program.check_with_inputs(p, 3, take, [rows], max_input_work=1)
      is Err(InputWorkLimit),
    )
    // Equal numeric values do not make a Graph measure into a row bound.
    let wrong_unit = graph_proof(
      "actql.bound.take",
      1L,
      "{\"input\":\"" + id + "\",\"maximum\":2,\"op\":\"clamp\"}",
      reference="checked-step:3",
      inputs=[id],
    )
    assert_true(
      @program.check_with_sources(p, 3, wrong_unit, [input], max_input_work=3)
      is Err(InputUnitMismatch(0)),
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
    closure_cursor(
      "[{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}}]",
    ),
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
    "actql.bound.match-nodes",
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
