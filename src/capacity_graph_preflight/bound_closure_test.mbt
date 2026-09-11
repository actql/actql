///|
// Fixed canonical take bound, independently hashed with Node SHA-256.
fn bound_capacity(
  p : @pipeline.CheckedPipeline,
  values : @parameter.BoundValues,
  proof_pipeline? : @pipeline.CheckedPipeline? = None,
) -> @capacity_graph_preflight.ApplicationCoverage {
  let proof = "{\"inputs\":[],\"law_id\":\"actql.bound.take\",\"semantic_ref\":\"checked-step:0\",\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-proof/0.1\"}"
  let id = "sha256:db6a87fa0b3a193fe3ecf19742e8071fb7736e24e7847e89a315a487305aa449"
  let witness = "{\"dependencies\":[\"sha256:aa8458a5cac6cc355dfc0b2900c742ec1c1e4606c7485bc67429e09eec9e5aa4\"],\"derivation\":{\"maximum\":7,\"op\":\"clamp\"},\"law_id\":\"actql.bound.take\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:aa8458a5cac6cc355dfc0b2900c742ec1c1e4606c7485bc67429e09eec9e5aa4\",\"semantic_ref\":\"checked-step:0\"},\"unit\":\"rows\",\"value\":7,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:db6a87fa0b3a193fe3ecf19742e8071fb7736e24e7847e89a315a487305aa449\"}"
  let wire_limits : @wire.Limits = {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
  }
  let admitted = @wire.admit(@utf8.encode(witness), id, wire_limits).unwrap()
  let mixed = @wire.check_mixed_claims([admitted], [], {
    max_entities: 1,
    max_references: 10,
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  let claim = @wire.bind_program_proof(
    @utf8.encode(proof),
    @wire.admit(@utf8.encode(witness), id, wire_limits).unwrap(),
    wire_limits,
  ).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [claim], {
    max_witnesses: 2,
    max_references: 10,
  }).unwrap()
  let source = @host.bind_claim_sources(claims, [], {
    max_entries: 2,
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
  }).unwrap()
  let owner = proof_pipeline.unwrap_or(p)
  let bindings = @program.bind_parameters(
    owner,
    values,
    max_work=10,
    max_text_bytes=100,
  ).unwrap()
  let app = @program.check_with_inputs(
    owner,
    0,
    @wire.program_claim_proof_at(claims, 0).unwrap(),
    [],
    bindings=Some(bindings),
  ).unwrap()
  let program = @program.check_applications(claims, [app], max_work=10).unwrap()
  let selected = policy(false)
  let graph = @capacity_graph_preflight.check(p, source, selected, caps()).unwrap()
  let sequence = @sequence.check_applications(
    p,
    source,
    selected,
    [],
    max_work=100,
  ).unwrap()
  @capacity_graph_preflight.check_application_coverage(
    graph,
    program,
    sequence,
    max_work=100,
  ).unwrap()
}

///|
test "producer capacity closure rejects substituted bindings at a later repeated visit" {
  let declarations = @parameter.read_declarations(
    Some(closure_cursor("{\"n\":{\"type\":\"number\",\"default\":7}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let bind_limits : @value.Limits = {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }
  guard @parameter.bind(declarations, None, bind_limits).unwrap()
    is Ready(values) else {
    abort("ready expected")
  }
  guard @parameter.bind(
      declarations,
      Some(closure_cursor("{\"n\":9}")),
      bind_limits,
    ).unwrap()
    is Ready(other) else {
    abort("ready expected")
  }
  let rows = @carrier.relation(
    @carrier.typed_rows(
      @schema.from_object(
        @contract.object_contract(
          [("id", @contract.primitive(NumberType, nullable=false))],
          nullable=false,
          max_fields=1,
          max_name_bytes=2,
        ).unwrap(),
      ).unwrap(),
    ),
  )
  let keyed = @evidence.declare_primary_key(closure_cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let base = @pipeline.check_with_evidence(
    closure_cursor("[{\"take\":{\"$param\":\"n\"}}]"),
    [("rows", @pipeline.KeyedInput(keyed))],
    Some(declarations),
    None,
    {
      max_steps: 1,
      max_work: 1000,
      max_text_bytes: 1000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let produced = @pipeline.ProducedInput(
    @pipeline.produced_input(base, Step(0)).unwrap(),
  )
  let root = forwarding_pipeline([("a", produced), ("b", produced)])
  let orders = @pipeline.resolve_contextual_closure(
    root,
    max_steps=2,
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap()
  let a = empty_capacity(root)
  let b = bound_capacity(base, values)
  let cost = 3 +
    @capacity_graph_preflight.application_coverage_work(a) +
    2 * @capacity_graph_preflight.application_coverage_work(b) +
    4
  let guards = @pipeline.bind_contextual_guards(
    orders,
    [None, Some(values), Some(values)],
    max_work=100,
    max_text_bytes=100,
  ).unwrap()
  let checked = @capacity_graph_preflight.check_application_closure(
    orders,
    [a, b, b],
    selected_policy=policy(false),
    bound_guards=guards,
    max_work=cost,
  ).unwrap()
  assert_eq(@capacity_graph_preflight.application_closure_work(checked), cost)
  assert_true(
    physical_equal(
      @capacity_graph_preflight.application_closure_guards(checked),
      guards,
    ),
  )
  assert_eq(
    @program.guard_application_count(
      @capacity_graph_preflight.application_closure_bindings_at(checked, 2).unwrap(),
    ),
    1,
  )
  let bad = @pipeline.bind_contextual_guards(
    orders,
    [None, Some(values), Some(other)],
    max_work=100,
    max_text_bytes=100,
  ).unwrap()
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [a, b, b],
      selected_policy=policy(false),
      bound_guards=bad,
      max_work=cost,
    )
    is Err(GuardBindings(2, BindingMismatch(0))),
  )
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [a, b, b],
      selected_policy=policy(false),
      bound_guards=guards,
      max_work=cost - 1,
    )
    is Err(ProofWorkLimit),
  )
  let other_orders = @pipeline.resolve_contextual_closure(
    root,
    max_steps=2,
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap()
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      other_orders,
      [a, b, b],
      selected_policy=policy(false),
      bound_guards=guards,
      max_work=cost,
    )
    is Err(ForeignGuardClosure),
  )
  let cross = bound_capacity(root, values, proof_pipeline=Some(base))
  let membership_cost = 3 +
    @capacity_graph_preflight.application_coverage_work(cross) +
    2 * @capacity_graph_preflight.application_coverage_work(b) +
    3 +
    3 +
    1
  let registrations = [(0, 0, 1)]
  let combined = @capacity_graph_preflight.check_application_closure(
    orders,
    [cross, b, b],
    selected_policy=policy(false),
    bound_guards=guards,
    proof_owners=registrations,
    max_work=membership_cost,
  ).unwrap()
  assert_eq(
    @capacity_graph_preflight.application_closure_work(combined),
    membership_cost,
  )
  assert_eq(
    @capacity_graph_preflight.application_closure_proof_owner(combined, 0, 0),
    Some(1),
  )
  assert_eq(
    @capacity_graph_preflight.application_closure_proof_owner(combined, 1, 0),
    Some(1),
  )
  assert_eq(
    @capacity_graph_preflight.application_closure_proof_owner(combined, 2, 0),
    Some(2),
  )
  registrations[0] = (0, 0, 0)
  assert_eq(
    @capacity_graph_preflight.application_closure_proof_owner(combined, 0, 0),
    Some(1),
  )
  for
    (owners, issue) in [
      ([], @capacity_graph_preflight.MissingProofOwner(0, 0)),
      ([(0, 0, 0)], @capacity_graph_preflight.ForeignProofOwner(0, 0)),
      ([(0, 0, 3)], @capacity_graph_preflight.InvalidProofOwner(0, 0)),
      ([(0, 1, 1)], @capacity_graph_preflight.InvalidProofOwner(0, 1)),
      (
        [(0, 0, 1), (0, 0, 2)],
        @capacity_graph_preflight.DuplicateProofOwner(0, 0),
      ),
      ([(1, 0, 1)], @capacity_graph_preflight.UnnecessaryProofOwner(1, 0)),
    ] {
    let actual = @capacity_graph_preflight.check_application_closure(
      orders,
      [cross, b, b],
      selected_policy=policy(false),
      bound_guards=guards,
      proof_owners=owners,
      max_work=membership_cost + 1,
    )
    guard actual is Err(error) else { abort("rejection expected") }
    assert_eq(error, issue)
  }
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [cross, b, b],
      selected_policy=policy(false),
      bound_guards=guards,
      proof_owners=[(0, 0, 1)],
      max_work=membership_cost - 1,
    )
    is Err(ProofWorkLimit),
  )
  guard @parameter.bind(declarations, None, bind_limits).unwrap() is Ready(copy) else {
    abort("ready expected")
  }
  let substituted = bound_capacity(root, copy, proof_pipeline=Some(base))
  assert_true(
    @capacity_graph_preflight.check_application_closure(
      orders,
      [substituted, b, b],
      selected_policy=policy(false),
      bound_guards=guards,
      proof_owners=[(0, 0, 1)],
      max_work=membership_cost,
    )
    is Err(ProofBindingMismatch(0, 0)),
  )
}
