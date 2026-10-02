///|
fn graph_capacity(
  graph : @input.GraphInputs,
  applications : @program.Applications,
) -> @capacity_graph_preflight.ApplicationCoverage {
  let sequence = @sequence.check_applications(
    @input.checked_pipeline(graph),
    @input.checked_sources(graph),
    @input.selected_policy(graph),
    [],
    max_work=10000,
  ).unwrap()
  @capacity_graph_preflight.check_application_coverage(
    graph,
    applications,
    sequence,
    max_work=10000,
  ).unwrap()
}

///|
test "capacity closure registers imported Graph bounds without detaching their preflights" {
  let base = input_bound_pipeline("[]")
  let root = @pipeline.check_with_evidence(
    closure_cursor(
      "[{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}}]",
    ),
    [
      (
        "g",
        @pipeline.ProducedInput(
          @pipeline.produced_input(base, Input(0)).unwrap(),
        ),
      ),
    ],
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
  let policy = policy(false)
  let initial = @input.check(base, sources(0, policy), policy, caps()).unwrap()
  let id = @wire.cid(
    @input.bound_witness(@input.input_bound(initial, 0, Nodes).unwrap()),
  )
  let proof = graph_proof(
    "actql.bound.match-nodes",
    1L,
    "{\"op\":\"source\"}",
    inputs=[id],
  )
  let sources = sources(0, policy, proofs=[proof])
  let base_graph = @input.check(base, sources, policy, caps()).unwrap()
  let root_graph = @input.check(root, sources, policy, caps()).unwrap()
  let app = @program.check_with_sources(
    root,
    0,
    proof,
    [@program.GraphInput(@input.input_bound(base_graph, 0, Nodes).unwrap())],
    max_input_work=1,
  ).unwrap()
  let claims = @host.source_claims(sources)
  let applications = @program.check_applications(claims, [app], max_work=1000).unwrap()
  let entries = [
    graph_capacity(root_graph, applications),
    graph_capacity(base_graph, applications),
  ]
  let orders = @pipeline.resolve_contextual_closure(
    root,
    max_steps=10,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
  assert_eq(@pipeline.contextual_closure_count(orders), 2)
  let guards = empty_guard_closure(orders)
  let index = @wire.claim_index(
    @wire.program_claim_arithmetic(claims),
    @wire.cid(@wire.program_proof_witness(proof)),
  ).unwrap()
  let registrations = [(0, index, 0, 1), (1, index, 0, 1)]
  let checked = @capacity_graph_preflight.check_application_closure(
    orders,
    entries,
    selected_policy=policy,
    bound_guards=guards,
    proof_owners=[(1, index, 0)],
    input_owners=registrations,
    max_work=10000,
  ).unwrap()
  for visit in 0..<2 {
    assert_eq(
      @capacity_graph_preflight.application_closure_input_owner(
        checked, visit, index, 0,
      ),
      Some(1),
    )
  }
  registrations.clear()
  assert_eq(
    @capacity_graph_preflight.application_closure_input_owner(
      checked, 0, index, 0,
    ),
    Some(1),
  )
  let work = @capacity_graph_preflight.application_closure_work(checked)
  for
    (registrations, expected) in [
      ([], @capacity_graph_preflight.MissingInputOwner(0, index, 0)),
      (
        [(0, index, 0, 1)],
        @capacity_graph_preflight.MissingInputOwner(1, index, 0),
      ),
      (
        [(0, index, 0, 0)],
        @capacity_graph_preflight.ForeignInputOwner(0, index, 0),
      ),
      (
        [(0, index, 0, 2)],
        @capacity_graph_preflight.InvalidInputOwner(0, index, 0),
      ),
      (
        [(0, index, 1, 1)],
        @capacity_graph_preflight.InvalidInputOwner(0, index, 1),
      ),
      (
        [(0, index, 0, 1), (0, index, 0, 1)],
        @capacity_graph_preflight.DuplicateInputOwner(0, index, 0),
      ),
    ] {
    let result = @capacity_graph_preflight.check_application_closure(
      orders,
      entries,
      selected_policy=policy,
      bound_guards=guards,
      proof_owners=[(1, index, 0)],
      input_owners=registrations,
      max_work=10000,
    )
    guard result is Err(issue) else { abort("rejection expected") }
    assert_eq(issue, expected)
  }
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      entries,
      selected_policy=policy,
      bound_guards=guards,
      proof_owners=[(1, index, 0)],
      input_owners=[(0, index, 0, 1), (1, index, 0, 1)],
      max_work=work,
    )
    is Ok(_),
  )
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      entries,
      selected_policy=policy,
      bound_guards=guards,
      proof_owners=[(1, index, 0)],
      input_owners=[(0, index, 0, 1), (1, index, 0, 1)],
      max_work=work - 1,
    )
    is Err(ProofWorkLimit),
  )
}

///|
test "capacity closure retains the exact local Graph input check" {
  let p = input_bound_pipeline(
    "[{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\"]}}]",
  )
  let policy = policy(false)
  let first = @input.check(p, sources(0, policy), policy, caps()).unwrap()
  let id = @wire.cid(
    @input.bound_witness(@input.input_bound(first, 0, Nodes).unwrap()),
  )
  let proof = graph_proof(
    "actql.bound.match-nodes",
    1L,
    "{\"op\":\"source\"}",
    inputs=[id],
  )
  let sources = sources(0, policy, proofs=[proof])
  let graph = @input.check(p, sources, policy, caps()).unwrap()
  let app = @program.check_with_sources(p, 0, proof, [
    @program.GraphInput(@input.input_bound(graph, 0, Nodes).unwrap()),
  ]).unwrap()
  let claims = @host.source_claims(sources)
  let applications = @program.check_applications(claims, [app], max_work=1000).unwrap()
  let coverage = graph_capacity(graph, applications)
  let orders = @pipeline.resolve_contextual_closure(
    p,
    max_steps=10,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
  let guards = empty_guard_closure(orders)
  let index = @wire.claim_index(
    @wire.program_claim_arithmetic(claims),
    @wire.cid(@wire.program_proof_witness(proof)),
  ).unwrap()
  let checked = @capacity_graph_preflight.check_application_closure(
    orders,
    [coverage],
    selected_policy=policy,
    bound_guards=guards,
    max_work=10000,
  ).unwrap()
  assert_eq(
    @capacity_graph_preflight.application_closure_input_owner(
      checked, 0, index, 0,
    ),
    Some(0),
  )
  assert_true(
    @capacity_graph_preflight.application_closure_input_owner(
      checked, 0, index, 1,
    )
    is None,
  )
  let work = @capacity_graph_preflight.application_closure_work(checked)
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [coverage],
      selected_policy=policy,
      bound_guards=guards,
      max_work=work,
    )
    is Ok(_),
  )
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [coverage],
      selected_policy=policy,
      bound_guards=guards,
      max_work=work - 1,
    )
    is Err(ProofWorkLimit),
  )
  let detached = @input.check(p, sources, policy, caps()).unwrap()
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [graph_capacity(detached, applications)],
      selected_policy=policy,
      bound_guards=guards,
      max_work=10000,
    )
    is Err(MissingInputOwner(0, _, 0)),
  )
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [graph_capacity(detached, applications)],
      selected_policy=policy,
      bound_guards=guards,
      input_owners=[(0, index, 0, 0)],
      max_work=10000,
    )
    is Err(ForeignInputOwner(0, _, 0)),
  )
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [coverage],
      selected_policy=policy,
      bound_guards=guards,
      input_owners=[(0, index, 0, 0)],
      max_work=10000,
    )
    is Err(UnnecessaryInputOwner(0, _, 0)),
  )
}
