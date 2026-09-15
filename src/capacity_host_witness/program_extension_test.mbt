///|
test "adding a Program count preserves admitted Host handles and policy owners" {
  let p = policy(fixture())
  let original = @capacity_host_witness.bind_claim_sources(
    source_program(source_wires()),
    [p],
    binding_caps(),
  ).unwrap()
  let proof = "{\"inputs\":[],\"law_id\":\"actql.bound.values\",\"semantic_ref\":\"checked-step:0\",\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-proof/0.1\"}"
  // Independent canonical Node SHA-256 vectors, also used by count preparation.
  let witness = "{\"dependencies\":[\"sha256:0cf6378d0fa4efd691d555347009038b128baf0ad435e3149bd2348393b76efe\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.values\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"sha256:0cf6378d0fa4efd691d555347009038b128baf0ad435e3149bd2348393b76efe\",\"semantic_ref\":\"checked-step:0\"},\"unit\":\"rows\",\"value\":3,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:4eeab1520aae127f1de078042f0ec9a4dd9d9841e6b78cf3dbfd23ba7f727554\"}"
  let caps : @wire.Limits = { max_bytes: 1000, max_nodes: 100, max_depth: 10, }
  let admitted = @wire.bind_program_proof(
    @utf8.encode(proof),
    @wire.admit(
      @utf8.encode(witness),
      "sha256:4eeab1520aae127f1de078042f0ec9a4dd9d9841e6b78cf3dbfd23ba7f727554",
      caps,
    ).unwrap(),
    caps,
  ).unwrap()
  let supplied = [admitted]
  let extended = @capacity_host_witness.extend_program_sources(
    original,
    supplied,
    { max_witnesses: 100, max_references: 1000, },
  ).unwrap()
  supplied.clear()
  assert_true(@capacity_host_witness.same_source_origin(original, extended))
  assert_true(
    physical_equal(
      @capacity_host_witness.source_origin_claims(extended),
      @capacity_host_witness.source_claims(original),
    ),
  )
  // Re-admitting even the exact same closed body is a new source admission.
  // Body identity must not bridge independently supplied evidence owners.
  let readmitted = @capacity_host_witness.bind_claim_sources(
    @capacity_host_witness.source_claims(original),
    [p],
    binding_caps(),
  ).unwrap()
  assert_true(!@capacity_host_witness.same_source_origin(original, readmitted))
  let next = @capacity_host_witness.extend_program_sources(extended, [], {
    max_witnesses: 100,
    max_references: 1000,
  }).unwrap()
  assert_true(@capacity_host_witness.same_source_origin(original, next))
  assert_true(!@capacity_host_witness.same_source_origin(next, readmitted))
  let old_claims = @capacity_host_witness.source_claims(original)
  let new_claims = @capacity_host_witness.source_claims(extended)
  let count = @wire.claim_count(@wire.program_claim_arithmetic(old_claims))
  assert_eq(
    @wire.claim_count(@wire.program_claim_arithmetic(new_claims)),
    count + 1,
  )
  assert_eq(
    @capacity_host_witness.source_count(extended),
    @capacity_host_witness.source_count(original),
  )
  assert_eq(
    @capacity_host_witness.source_usage(extended),
    @capacity_host_witness.source_usage(original),
  )
  for i in 0..<count {
    match @capacity_host_witness.source_at(original, i) {
      Some(prior) => {
        let retained = @capacity_host_witness.source_at(extended, i).unwrap()
        assert_true(physical_equal(retained, prior))
        assert_true(
          physical_equal(
            @policy.ceiling_policy(@capacity_host_witness.ceiling(retained)),
            p,
          ),
        )
      }
      None => assert_true(@capacity_host_witness.source_at(extended, i) is None)
    }
  }
  assert_true(@capacity_host_witness.source_at(extended, count) is None)
  assert_true(
    physical_equal(
      @wire.program_claim_proof_at(new_claims, count).unwrap(),
      admitted,
    ),
  )
  assert_true(
    physical_equal(
      @wire.mixed_limit_at(@wire.program_claim_mixed(new_claims).unwrap(), 0).unwrap(),
      @wire.mixed_limit_at(@wire.program_claim_mixed(old_claims).unwrap(), 0).unwrap(),
    ),
  )
  assert_true(
    @capacity_host_witness.extend_program_sources(original, [admitted], {
      max_witnesses: count,
      max_references: 1000,
    })
    is Err(_),
  )
}
