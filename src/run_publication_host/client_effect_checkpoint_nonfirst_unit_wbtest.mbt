///|
// Original checked-owner correspondence only: this fixture issues no physical
// capture, persisted waiting Checkpoint, permission, key or signature.
fn checkpoint_nonfirst_unit_fixture() -> (
  ClientEffectAllowedRun,
  @publication.PublicationContract,
  @checkpoint.CheckpointRequest,
) {
  let document =
    #|{"version":"actql/0.1","id":"signing-second-unit","stages":[{"id":"producer","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false}},"rows":[{"value":1}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["value"]}}},{"id":"apply","inputs":{"input":{"result":{"stage":"producer","result":"rows"}}},"steps":[{"filter":"value >= 1","as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"apply","result":"out"}}}}
  let (_, environment, effect_limits) = client_composed_effect_base_fixture()
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
    allowed, "scope", "original-second-unit-run", "2026-10-09T00:00:00.000Z", "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let body : @checkpoint.CheckpointRequest = {
    checkpoint_id: "original-second-unit-review",
    continuation_state_cid: "sha256:" + "1".repeat(64),
    subject: @checkpoint.RunUnit(
      run_id="original-second-unit-run",
      unit_id="apply",
      run_definition_cid=@publication.publication_contract_identity(definition),
    ),
    phase: @checkpoint.Commit,
    kind: @checkpoint.EffectSet,
    required_artifact_cid: "sha256:" + "2".repeat(64),
    review_projection_cid: "sha256:" + "3".repeat(64),
    requirements: [@checkpoint.EffectScopeApproved],
    reason_code: "effect_review",
    human_summary: "Review the second authored unit",
    created_at: "2026-10-09T01:00:00.000Z",
    expires_at: "2026-10-09T02:00:00.000Z",
  }
  (allowed, definition, body)
}

///|
test "Checkpoint signing unit uses the explicit second original unit rather than the first" {
  let (allowed, definition, body) = checkpoint_nonfirst_unit_fixture()
  let artifact = @checkpoint.seal_checkpoint(body, {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 64,
  }).unwrap()
  let original = @checked.effect_program_static_checked_computation(
    prepared_client_effect_computation_candidate(allowed.compilation.owner),
  )
  assert_eq(@checked.unit_count(original), 2)
  assert_eq(client_effect_compilation_unit_id(allowed.compilation), "apply")
  let first = @checked.unit_definition_cid(original, 0).unwrap()
  let second = @checked.unit_definition_cid(original, 1).unwrap()
  assert_true(first != second)
  // Expected correspondence comes from the independently retained checked
  // Owner at the authored index, not from the projection under test.
  assert_eq(
    client_effect_review_checkpoint_unit_definition_cid(
      allowed, definition, artifact,
    ).unwrap(),
    second,
  )
}

///|
test "Checkpoint signing unit refuses the real producer coordinate without first-unit fallback" {
  let (allowed, definition, body) = checkpoint_nonfirst_unit_fixture()
  let artifact = @checkpoint.seal_checkpoint(
    {
      ..body,
      subject: @checkpoint.RunUnit(
        run_id="original-second-unit-run",
        unit_id="producer",
        run_definition_cid=@publication.publication_contract_identity(
          definition,
        ),
      ),
    },
    { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 64, },
  ).unwrap()
  assert_true(
    client_effect_review_checkpoint_unit_definition_cid(
      allowed, definition, artifact,
    )
    is Err(ForeignSubject),
  )
}
