///|
fn checkpoint_journal_test_binding() -> @checkpoint.ResumeBinding {
  {
    authorization_context_cid: "sha256:" + "2".repeat(64),
    environment_binding_cid: "sha256:" + "b".repeat(64),
  }
}

///|
test "portable original resume row preserves exact decimal bytes and retained binding" {
  let binding = checkpoint_journal_test_binding()
  let pending : @checkpoint.ResumeIntentView = {
    state: ResumePending,
    generation: 0L,
    claimant: "",
    lease_expires_ms: 0L,
  }
  let pending_wire = "{\"claimant\":\"\",\"generation\":\"0\",\"lease_expires_ms\":\"0\",\"state\":\"pending\"}"
  assert_eq(client_checkpoint_resume_row_body(pending), pending_wire)
  assert_eq(
    decode_client_checkpoint_resume_row(pending_wire, binding),
    Some(pending),
  )
  let claimed : @checkpoint.ResumeIntentView = {
    state: ResumeClaimed,
    generation: 9223372036854775806L,
    claimant: "original-host",
    lease_expires_ms: 9007199254740991L,
  }
  let claimed_wire = "{\"claimant\":\"original-host\",\"generation\":\"9223372036854775806\",\"lease_expires_ms\":\"9007199254740991\",\"state\":\"claimed\"}"
  assert_eq(client_checkpoint_resume_row_body(claimed), claimed_wire)
  assert_eq(
    decode_client_checkpoint_resume_row(claimed_wire, binding),
    Some(claimed),
  )
}

///|
test "portable resume row refuses noncanonical overflow and incomplete completion originals" {
  let binding = checkpoint_journal_test_binding()
  let original = "{\"claimant\":\"original-host\",\"generation\":\"1\",\"lease_expires_ms\":\"100\",\"state\":\"claimed\"}"
  for
    wire in [
      original + " ",
      original.replace_all(old="\"1\"", new="\"01\""),
      original.replace_all(old="\"1\"", new="\"9223372036854775807\""),
      original.replace_all(old="\"100\"", new="\"9007199254740992\""),
      original.replace_all(old="\"original-host\"", new="\"\""),
      original.replace_all(old="\"claimed\"", new="\"completed\""),
    ] {
    assert_eq(decode_client_checkpoint_resume_row(wire, binding), None)
  }
  assert_eq(
    decode_client_checkpoint_resume_row(original, {
      ..binding,
      authorization_context_cid: "not-an-original-cid",
    }),
    None,
  )
}

///|
fn checkpoint_journal_test_original() -> (
  ClientCheckpointJournalRecord,
  @publication.PublicationContract,
) {
  let definition = journal_encoding_original().definition
  let limits = client_checkpoint_journal_limits()
  let artifact = @checkpoint.seal_checkpoint(
    {
      checkpoint_id: "original-checkpoint",
      continuation_state_cid: "sha256:" + "3".repeat(64),
      subject: RunUnit(
        run_id="run",
        unit_id="original-unit",
        run_definition_cid=@publication.publication_contract_identity(
          definition,
        ),
      ),
      phase: Commit,
      kind: EffectSet,
      required_artifact_cid: "sha256:" + "4".repeat(64),
      review_projection_cid: "sha256:" + "5".repeat(64),
      requirements: [EffectScopeApproved],
      reason_code: "review_required",
      human_summary: "Original review",
      created_at: "2026-09-18T00:00:01.000Z",
      expires_at: "2026-09-19T00:00:00.000Z",
    },
    limits,
  ).unwrap()
  let updated_at = "2026-09-18T00:00:02.000Z"
  let persisted = @checkpoint.confirm_checkpoint_persisted(
    artifact,
    artifact.wire,
  ).unwrap()
  let state = @checkpoint.admit_run_state_wire(
    @checkpoint.issue_waiting_run_state(
      persisted,
      updated_at,
      ["answer"],
      limits,
    ).unwrap(),
    limits,
  ).unwrap()
  (
    {
      artifact,
      declared_results: ["answer"],
      unknown_effects: [],
      updated_at,
      state,
      resolution_cid: None,
      verified_wire: None,
      resume_intent_id: None,
      resume_intent: None,
      settlement_only: false,
      effect_ledger: [],
      binding: checkpoint_journal_test_binding(),
    },
    definition,
  )
}

///|
test "portable checkpoint row retains complete original envelope and canonical framing" {
  let (original, definition) = checkpoint_journal_test_original()
  let wire = client_checkpoint_journal_row_body(original).unwrap()
  // The expected outer framing is independent of the row encoder. The sealed
  // artifact/state are the exact admitted input wires, not reissued row facts.
  let quoted = (value : String) => {
    let output = @encode.writer(262144, 4, 2)
    @encode.string_value(output, value)
    @encode.finish(output)
  }
  let expected = "{\"authorization_context_cid\":\"sha256:" +
    "2".repeat(64) +
    "\",\"checkpoint\":" +
    quoted(original.artifact.wire) +
    ",\"declared_results\":[\"answer\"],\"environment_binding_cid\":\"sha256:" +
    "b".repeat(64) +
    "\",\"effect_ledger\":[],\"resolution_cid\":null,\"resume_intent_id\":null,\"verified_wire\":null,\"state\":" +
    quoted(original.state.wire) +
    ",\"resume_intent\":null,\"settlement_only\":false,\"unknown_effects\":[],\"updated_at\":\"2026-09-18T00:00:02.000Z\",\"version\":\"actql-native-client-checkpoint-row/0.1\"}"
  assert_eq(wire, expected)
  let decoded = decode_client_checkpoint_journal_row(wire, definition, {
    max_wire_bytes: 65536,
    max_nodes: 128,
    max_depth: 16,
  }).unwrap()
  assert_eq(decoded.artifact.wire, original.artifact.wire)
  assert_eq(decoded.state.wire, original.state.wire)
  assert_eq(decoded.binding, original.binding)
  assert_eq(client_checkpoint_journal_row_body(decoded), Ok(wire))
}

///|
test "portable checkpoint row refuses changed original authority state and absent resume material" {
  let (original, definition) = checkpoint_journal_test_original()
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 128,
    max_depth: 16,
  }
  let wire = client_checkpoint_journal_row_body(original).unwrap()
  for
    invalid in [
      wire + " ",
      client_checkpoint_journal_row_body({ ..original, settlement_only: true, }).unwrap(),
      client_checkpoint_journal_row_body({
        ..original,
        resolution_cid: Some("sha256:" + "6".repeat(64)),
      }).unwrap(),
      client_checkpoint_journal_row_body({
        ..original,
        binding: {
          ..original.binding,
          authorization_context_cid: "sha256:" + "9".repeat(64),
        },
      }).unwrap(),
      client_checkpoint_journal_row_body({
        ..original,
        declared_results: ["replacement"],
      }).unwrap(),
    ] {
    assert_true(
      decode_client_checkpoint_journal_row(invalid, definition, limits)
      is Err(InvalidMaterial),
    )
  }
}
