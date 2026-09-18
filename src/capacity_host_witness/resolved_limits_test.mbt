///|
fn resolved_limit_program_proof() -> @wire.ProgramProofClaim {
  let proof = "{\"inputs\":[],\"law_id\":\"actql.bound.values\",\"semantic_ref\":\"checked-step:0\",\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-proof/0.1\"}"
  let witness = "{\"dependencies\":[\"sha256:0cf6378d0fa4efd691d555347009038b128baf0ad435e3149bd2348393b76efe\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.values\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0cf6378d0fa4efd691d555347009038b128baf0ad435e3149bd2348393b76efe\",\"semantic_ref\":\"checked-step:0\"},\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:4eeab1520aae127f1de078042f0ec9a4dd9d9841e6b78cf3dbfd23ba7f727554\"}"
  let caps : @wire.Limits = { max_bytes: 1000, max_nodes: 100, max_depth: 10, }
  @wire.bind_program_proof(
    @utf8.encode(proof),
    @wire.admit(
      @utf8.encode(witness),
      "sha256:4eeab1520aae127f1de078042f0ec9a4d" +
      "d9d9841e6b78cf3dbfd23ba7f727554",
      caps,
    ).unwrap(),
    caps,
  ).unwrap()
}

///|
fn resolved_limit_fixture() -> (
  @capacity_host_witness.HostSources,
  @policy.Ceiling,
  @wire.ProgramProofClaim,
) {
  let selected_policy = policy(fixture())
  let original = @capacity_host_witness.bind_claim_sources(
    source_program(source_wires()),
    [selected_policy],
    binding_caps(),
  ).unwrap()
  let proof = resolved_limit_program_proof()
  let extended = @capacity_host_witness.extend_program_sources(
    original,
    [proof],
    { max_witnesses: 100, max_references: 1000, },
  ).unwrap()
  (
    extended,
    @policy.ceiling(selected_policy, "max_relation_output_rows").unwrap(),
    proof,
  )
}

///|
test "resolved limits preserve owners and batch local insertions" {
  let (original, ceiling, proof) = resolved_limit_fixture()
  let requests : Array[@capacity_host_witness.ResolvedLimitRequest] = [
    { subject: "join:checked-step:1:output", candidates: [proof], },
    { subject: "join:checked-step:2:output", candidates: [proof], },
  ]
  let caps : @capacity_host_witness.ResolvedLimitLimits = {
    max_work: 1000,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let extended = @capacity_host_witness.extend_resolved_limits(
    original,
    ceiling,
    requests,
    @wire.EngineAtomic,
    caps,
  ).unwrap()
  let sources = @capacity_host_witness.resolved_limit_sources(extended)
  assert_true(@capacity_host_witness.same_source_origin(original, sources))
  assert_eq(@capacity_host_witness.resolved_limit_count(extended), 2)
  let first = @capacity_host_witness.resolved_limit_at(extended, 0).unwrap()
  let second = @capacity_host_witness.resolved_limit_at(extended, 1).unwrap()
  assert_eq(@wire.limit_subject(first), "join:checked-step:1:output")
  assert_eq(@wire.limit_subject(second), "join:checked-step:2:output")
  assert_eq(@wire.limit_enforcement(first), @wire.EngineAtomic)
  assert_eq(@wire.limit_enforcement(second), @wire.EngineAtomic)
  assert_eq(@derivation.minimum_candidate_count(@wire.limit_minimum(first)), 2)
  assert_eq(@derivation.minimum_candidate_count(@wire.limit_minimum(second)), 2)
  let first_index = @capacity_host_witness.resolved_limit_index(extended, 0).unwrap()
  assert_eq(
    @capacity_host_witness.resolved_limit_index(extended, 1),
    Some(first_index + 1),
  )
  assert_true(
    physical_equal(
      @wire.mixed_limit_at(
        @wire.program_claim_mixed(@capacity_host_witness.source_claims(sources)).unwrap(),
        first_index,
      ).unwrap(),
      first,
    ),
  )
  let usage = @capacity_host_witness.resolved_limit_usage(extended)
  let exact = @capacity_host_witness.extend_resolved_limits(
    original,
    ceiling,
    requests,
    @wire.EngineAtomic,
    {
      max_work: usage.0,
      max_bytes: usage.1,
      max_nodes: usage.2,
      max_depth: 30,
    },
  )
  assert_true(exact is Ok(_))
  for
    limits in [
      { ..caps, max_work: usage.0 - 1, },
      { ..caps, max_bytes: usage.1 - 1, },
      { ..caps, max_nodes: usage.2 - 1, },
    ] {
    assert_true(
      @capacity_host_witness.extend_resolved_limits(
        original,
        ceiling,
        requests,
        @wire.EngineAtomic,
        limits,
      )
      is Err(_),
    )
  }
}

///|
test "resolved limits reject a same CID proof from another admission" {
  let (original, ceiling, _) = resolved_limit_fixture()
  let foreign = resolved_limit_program_proof()
  assert_true(
    @capacity_host_witness.extend_resolved_limits(
      original,
      ceiling,
      [{ subject: "join:checked-step:1:output", candidates: [foreign], }],
      @wire.EngineAtomic,
      { max_work: 1000, max_bytes: 20000, max_nodes: 1000, max_depth: 30, },
    )
    is Err(MissingCandidate(0, 0)),
  )
}
