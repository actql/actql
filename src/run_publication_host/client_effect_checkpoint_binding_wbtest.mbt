///|
fn checkpoint_binding_fixture() -> (
  ClientEffectAllowedRun,
  @publication.PublicationContract,
  @checkpoint.CheckpointRequest,
) {
  let (document, environment, effect_limits) = client_composed_effect_base_fixture()
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    effect_limits,
  ).unwrap()
  let limits = run_materials_limits()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "scope", "original-run", "2026-10-09T00:00:00.000Z", "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let body : @checkpoint.CheckpointRequest = {
    checkpoint_id: "original-review",
    continuation_state_cid: "sha256:" + "1".repeat(64),
    subject: @checkpoint.RunUnit(
      run_id="original-run",
      unit_id=client_effect_compilation_unit_id(compilation),
      run_definition_cid=@publication.publication_contract_identity(definition),
    ),
    phase: @checkpoint.Commit,
    kind: @checkpoint.EffectSet,
    required_artifact_cid: "sha256:" + "2".repeat(64),
    review_projection_cid: "sha256:" + "3".repeat(64),
    requirements: [@checkpoint.EffectScopeApproved],
    reason_code: "effect_review",
    human_summary: "Review",
    created_at: "2026-10-09T01:00:00.000Z",
    expires_at: "2026-10-09T02:00:00.000Z",
  }
  (allowed, definition, body)
}

///|
test "Effect Checkpoint retained metadata reads the admitted original" {
  let (allowed, definition, body) = checkpoint_binding_fixture()
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 64,
  }
  let sealed_checkpoint = @checkpoint.seal_checkpoint(body, limits).unwrap()
  let original = admit_client_effect_review_checkpoint_binding(
    allowed,
    definition,
    sealed_checkpoint.wire,
    limits,
  ).unwrap()
  let expected = [
    sealed_checkpoint.checkpoint_cid,
    sealed_checkpoint.wire,
    "original-run",
    client_effect_compilation_unit_id(allowed.compilation),
    @publication.publication_contract_identity(definition),
    "sha256:" + "2".repeat(64),
    "sha256:" + "3".repeat(64),
    "sha256:" + "1".repeat(64),
  ]
  assert_eq(
    client_effect_review_checkpoint_binding_fields(original).unwrap(),
    expected,
  )
  assert_eq(
    client_effect_review_checkpoint_binding_fields(original).unwrap(),
    expected,
  )
  assert_eq(original.wire, sealed_checkpoint.wire)
}

///|
test "Effect Checkpoint binding validates original Run unit and sealed metadata" {
  let (allowed, definition, body) = checkpoint_binding_fixture()
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 64,
  }
  let sealed_checkpoint = @checkpoint.seal_checkpoint(body, limits).unwrap()
  let accepted = admit_client_effect_review_checkpoint_binding(
    allowed,
    definition,
    sealed_checkpoint.wire,
    limits,
  ).unwrap()
  assert_eq(accepted.wire, sealed_checkpoint.wire)
  assert_eq(accepted.checkpoint_cid, sealed_checkpoint.checkpoint_cid)
  assert_eq(
    client_effect_review_checkpoint_members(
      allowed,
      definition,
      sealed_checkpoint.wire,
      limits,
      64,
      10000,
    ).unwrap(),
    ["save"],
  )
  assert_true(
    client_effect_review_checkpoint_members(
      allowed,
      definition,
      sealed_checkpoint.wire,
      limits,
      0,
      10000,
    )
    is Err(InvalidLimits),
  )
  // Synthetic artifact CIDs test metadata admission only. They prove no
  // physical capture, Preview, Store confirmation, waiting commit or approval.
  for
    subject in [
      @checkpoint.RunUnit(
        run_id="foreign",
        unit_id=client_effect_compilation_unit_id(allowed.compilation),
        run_definition_cid=@publication.publication_contract_identity(
          definition,
        ),
      ),
      @checkpoint.RunUnit(
        run_id="original-run",
        unit_id="foreign-unit",
        run_definition_cid=@publication.publication_contract_identity(
          definition,
        ),
      ),
      @checkpoint.RunUnit(
        run_id="original-run",
        unit_id=client_effect_compilation_unit_id(allowed.compilation),
        run_definition_cid="sha256:" + "f".repeat(64),
      ),
    ] {
    let foreign = @checkpoint.seal_checkpoint({ ..body, subject, }, limits).unwrap()
    assert_true(
      admit_client_effect_review_checkpoint_binding(
        allowed,
        definition,
        foreign.wire,
        limits,
      )
      is Err(ForeignSubject),
    )
  }
  let other = issue_client_effect_run_definition(
    allowed, "scope", "another-run", "2026-10-09T00:00:00.000Z", "2026-10-10T00:00:00.000Z",
  ).unwrap()
  assert_true(
    admit_client_effect_review_checkpoint_binding(
      allowed,
      other,
      sealed_checkpoint.wire,
      limits,
    )
    is Err(ForeignSubject),
  )
}

///|
test "Effect Checkpoint binding rejects another review and extended original lifetime" {
  let (allowed, definition, body) = checkpoint_binding_fixture()
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 64,
  }
  let partial = @checkpoint.seal_checkpoint(
    {
      ..body,
      requirements: [
        @checkpoint.EffectScopeApproved,
        @checkpoint.PartialApplicationAccepted,
      ],
    },
    limits,
  ).unwrap()
  assert_true(
    admit_client_effect_review_checkpoint_binding(
      allowed,
      definition,
      partial.wire,
      limits,
    )
    is Err(UnsupportedReview),
  )
  let read = @checkpoint.seal_checkpoint(
    {
      ..body,
      phase: @checkpoint.Preflight,
      kind: @checkpoint.ReadAccess,
      requirements: [@checkpoint.InvocationScopeApproved],
    },
    limits,
  ).unwrap()
  assert_true(
    admit_client_effect_review_checkpoint_binding(
      allowed,
      definition,
      read.wire,
      limits,
    )
    is Err(UnsupportedReview),
  )
  for
    altered in [
      { ..body, created_at: "2026-10-08T23:59:59.000Z", },
      { ..body, expires_at: "2026-10-10T00:00:01.000Z", },
    ] {
    let foreign = @checkpoint.seal_checkpoint(altered, limits).unwrap()
    assert_true(
      admit_client_effect_review_checkpoint_binding(
        allowed,
        definition,
        foreign.wire,
        limits,
      )
      is Err(OriginalLifetime),
    )
  }
  assert_true(
    admit_client_effect_review_checkpoint_binding(
      allowed, definition, "{}", limits,
    )
    is Err(Checkpoint(_)),
  )
}

///|
test "Effect Checkpoint exclusive end may equal original Run deadline without permitting a start there" {
  let (allowed, definition, body) = checkpoint_binding_fixture()
  let (_, until) = @publication.run_definition_lifetime(definition).unwrap()
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 64,
  }
  let original = @checkpoint.seal_checkpoint(
    { ..body, expires_at: until, },
    limits,
  ).unwrap()
  assert_true(
    admit_client_effect_review_checkpoint_binding(
      allowed,
      definition,
      original.wire,
      limits,
    )
    is Ok(_),
  )
  assert_false(client_effect_run_start_current(allowed, definition, until))
  let extended = @checkpoint.seal_checkpoint(
    { ..body, expires_at: "2026-10-10T00:00:00.001Z", },
    limits,
  ).unwrap()
  assert_true(
    admit_client_effect_review_checkpoint_binding(
      allowed,
      definition,
      extended.wire,
      limits,
    )
    is Err(OriginalLifetime),
  )
}
