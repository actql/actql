///|
let submitted_rows_reference_wire : String =
  #|{"epoch":{"authenticator":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","authorityScopeCid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","epochNonce":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","expiresAt":2000,"notBefore":1000,"version":"actql-submission-epoch/0.1"},"nonce":"original-submit"}

///|
fn submitted_rows_preparation(
  text : String,
) -> @input.LocalSubmittedPreparation {
  let env = environment()
  @input.prepare_local_submitted_input(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":" +
    @json.to_json(text).stringify() +
    "},\"parameters\":null}",
    env,
    Some(@input.bind_local_input_context(env, [], "python.local").unwrap()),
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
fn submitted_rows_plan(
  value : @input.LocalSubmittedPreparation,
  created_at? : String = "2026-10-12T00:00:00.000Z",
  valid_until? : String = "2099-01-01T00:00:00.000Z",
  run_id? : String = "original-submitted-run",
) -> LocalRunPlan {
  let input = @input.local_submitted_preparation_input(value)
  let current = account(Allow)
  prepare_source_free_local_publication_run(
    input,
    "sha256:" + "b".repeat(64),
    "sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267",
    permit(input, current),
    current,
    tuple(),
    context_cid(),
    "sha256:" + "c".repeat(64),
    "local",
    run_id,
    created_at,
    valid_until,
    (source_free_original_policy_cid, source_free_original_policy),
  ).unwrap()
}

///|
fn submitted_rows_before(value : @input.LocalSubmittedPreparation) -> Bytes {
  @host.client_submitted_intent_journal_row_body(
    submitted_rows_reference_wire,
    @input.local_submitted_preparation_intent(value),
  ).unwrap()
}

///|
fn submitted_rows_prepare(
  plan : LocalRunPlan,
  value : @input.LocalSubmittedPreparation,
  before : Bytes,
  current? : @authorization.AdmittedAccountConfiguration = account(Allow),
  now? : Double = 1000.0,
  local_policy_original? : @host.ClientLocalRunPolicyOriginal? = None,
) -> Result[LocalSubmittedRunRows, LocalSubmittedRunRowsIssue] {
  let input = @input.local_submitted_preparation_input(value)
  prepare_local_submitted_run_rows(
    plan,
    value,
    @host.admit_client_submission_reference_record(
      submitted_rows_reference_wire,
    ).unwrap(),
    before,
    permit(input, account(Allow)),
    current,
    tuple(),
    context_cid(),
    now,
    local_policy_original~,
  )
}

///|
fn submitted_rows_finite_policy(
  plan : LocalRunPlan,
  adoption? : String = "sha256:" + "a".repeat(64),
) -> @host.ClientLocalRunPolicyOriginal {
  // Actual dependency bodies, while physical adoption and read authority are
  // intentionally not asserted by this pure Owner fixture.
  let originals = @host.client_local_product_common_originals(
    "/private/local",
    "2026-10-12T00:00:00.000Z",
    @host.client_local_product_assets(),
  ).unwrap()
  let profile = @host.client_local_run_policy_profile(originals).unwrap()
  let at = "2026-10-13T00:00:00.001Z"
  @host.bind_client_local_run_policy_original(
    profile,
    @host.admit_client_submission_reference_record(
      submitted_rows_reference_wire,
    ).unwrap(),
    plan.request,
    plan.definition,
    @host.issue_client_local_run_retention_policy(profile, at).unwrap(),
    at,
    adoption,
    "sha256:" + "f".repeat(64),
  ).unwrap()
}

///|
test "SDK first acceptance retains evidence while legacy rows remain unchanged" {
  let preparation = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(
    preparation,
    created_at="2026-10-13T00:00:00.001Z",
    valid_until="2026-10-14T00:00:00.001Z",
  )
  let reference = @host.admit_client_submission_reference_record(
    submitted_rows_reference_wire,
  ).unwrap()
  let policy = submitted_rows_finite_policy(plan)
  let before = submitted_rows_before(preparation)
  let legacy = submitted_rows_prepare(
    plan,
    preparation,
    before,
    local_policy_original=Some(policy),
  ).unwrap()
  let rows = prepare_local_sdk_submitted_run_rows(
    plan,
    preparation,
    reference,
    before,
    permit(
      @input.local_submitted_preparation_input(preparation),
      account(Allow),
    ),
    account(Allow),
    tuple(),
    context_cid(),
    1000.0,
    policy,
  ).unwrap()
  let (_, _, old_observation) = @host.decode_client_run_journal_row_with_observation_originals(
    legacy.run,
  ).unwrap()
  assert_eq(old_observation, None)
  let (record, finite, observation) = @host.decode_client_run_journal_row_with_observation_originals(
    rows.run,
  ).unwrap()
  assert_true(finite is Some(_))
  let expected = @host.capture_client_run_observation_originals(
      plan.compiled,
      plan.definition,
    )
    .unwrap()
    .wire()
    .unwrap()
  assert_eq(observation, Some(expected))
  validate_local_saved_submitted_rows(
    rows,
    plan,
    preparation,
    @host.client_request_scope_cid(plan.request),
    0L,
    rows.run,
    @host.client_submission_reference_record_request_id(reference),
    0L,
    rows.submitted,
  ).unwrap()
  for changed in [None, Some("foreign")] {
    let replaced = @host.client_run_journal_row_body(
      record,
      local_run_policy_originals=finite,
      run_observation_originals=changed,
    ).unwrap()
    assert_true(
      validate_local_saved_submitted_rows(
        rows,
        plan,
        preparation,
        @host.client_request_scope_cid(plan.request),
        0L,
        replaced,
        @host.client_submission_reference_record_request_id(reference),
        0L,
        rows.submitted,
      )
      is Err(CustodyLost),
    )
  }
}

///|
test "first accept row keeps finite packet beyond initial adoption deadline" {
  let preparation = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(
    preparation,
    created_at="2026-10-13T00:00:00.001Z",
    valid_until="2026-10-14T00:00:00.001Z",
  )
  let policy = submitted_rows_finite_policy(plan)
  let rows = submitted_rows_prepare(
    plan,
    preparation,
    submitted_rows_before(preparation),
    local_policy_original=Some(policy),
  ).unwrap()
  let (run_key, submission_key, _, run, submitted) = local_submitted_run_rows(
    rows, plan, preparation,
  ).unwrap()
  let (decoded, packet) = @host.decode_client_run_journal_row_with_local_policy(
    run,
  ).unwrap()
  assert_eq(
    @publication.publication_contract_identity(decoded.definition),
    local_run_definition_cid(plan),
  )
  assert_eq(
    packet.unwrap(),
    @utf8.decode(@host.client_local_run_policy_original_body(policy)),
  )
  assert_eq(
    @host.client_local_run_policy_original_issued_at(policy),
    "2026-10-13T00:00:00.001Z",
  )
  assert_eq(
    @publication.result_retention_interval_state(
      @host.client_local_run_policy_original_retention(policy),
      "2026-10-14T00:00:00.001Z",
    ),
    Ok("available"),
  )
  assert_eq(
    @publication.result_retention_interval_state(
      @host.client_local_run_policy_original_retention(policy),
      "2026-10-14T00:00:00.002Z",
    ),
    Ok("retention_expired"),
  )
  assert_eq(
    @publication.result_retention_interval_state(
      @host.client_local_run_policy_original_retention(policy),
      "2026-10-15T00:00:00.001Z",
    ),
    Ok("delete_due"),
  )
  assert_eq(
    @publication.result_metadata_retention_state(
      @host.client_local_run_policy_original_retention(policy),
      "2026-10-20T00:00:00.001Z",
    ),
    Ok("delete_due"),
  )
  let advanced = @host.client_run_journal_row_body(
    { ..decoded, dispatch_reserved: true, physical_start_claimed: true, },
    local_run_policy_originals=packet,
  ).unwrap()
  assert_true(
    validate_local_saved_submitted_rows(
      rows, plan, preparation, run_key, 9L, advanced, submission_key, 2L, submitted,
    )
    is Ok(_),
  )
}

///|
test "finite row cannot lose replace or renew its saved original packet" {
  let preparation = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(
    preparation,
    created_at="2026-10-13T00:00:00.001Z",
    valid_until="2026-10-14T00:00:00.001Z",
  )
  let policy = submitted_rows_finite_policy(plan)
  let rows = submitted_rows_prepare(
    plan,
    preparation,
    submitted_rows_before(preparation),
    local_policy_original=Some(policy),
  ).unwrap()
  let (run_key, submission_key, _, run, submitted) = local_submitted_run_rows(
    rows, plan, preparation,
  ).unwrap()
  let (decoded, packet) = @host.decode_client_run_journal_row_with_local_policy(
    run,
  ).unwrap()
  let foreign = submitted_rows_finite_policy(
    plan,
    adoption="sha256:" + "e".repeat(64),
  )
  for
    changed in [
      None,
      Some(@utf8.decode(@host.client_local_run_policy_original_body(foreign))),
      Some(
        packet
        .unwrap()
        .replace(old="2026-10-13T00:00:00.001Z", new="2026-10-14T00:00:00.001Z"),
      ),
    ] {
    let changed_run = @host.client_run_journal_row_body(
      decoded,
      local_run_policy_originals=changed,
    ).unwrap()
    assert_true(
      validate_local_saved_submitted_rows(
        rows, plan, preparation, run_key, 9L, changed_run, submission_key, 2L, submitted,
      )
      is Err(CustodyLost),
    )
  }
}

///|
test "finite packet for another nominal Run cannot enter first accept candidate" {
  let preparation = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(
    preparation,
    created_at="2026-10-13T00:00:00.001Z",
    valid_until="2026-10-14T00:00:00.001Z",
  )
  let foreign = submitted_rows_plan(
    preparation,
    created_at="2026-10-13T00:00:00.001Z",
    valid_until="2026-10-14T00:00:00.001Z",
    run_id="another-run",
  )
  assert_true(
    submitted_rows_prepare(
      plan,
      preparation,
      submitted_rows_before(preparation),
      local_policy_original=Some(submitted_rows_finite_policy(foreign)),
    )
    is Err(CustodyLost),
  )
}

///|
test "actual saved row relationship stays bound to original nominal preparation" {
  let value = submitted_rows_preparation("/*😀*/\r\nSELECT 1 AS n")
  let plan = submitted_rows_plan(value)
  let rows = submitted_rows_prepare(plan, value, submitted_rows_before(value)).unwrap()
  let (run_key, submission_key, _, run, submitted) = local_submitted_run_rows(
    rows, plan, value,
  ).unwrap()
  assert_true(
    validate_local_saved_submitted_rows(
      rows, plan, value, run_key, 0L, run, submission_key, 1L, submitted,
    )
    is Ok(_),
  )
  // Later retained state keeps the original immutable admission revision.
  // These are Core relationship fixtures, not physical Store or start facts.
  let run_wire = @utf8.decode(run) catch { _ => "" }
  let later = @utf8.encode(
    run_wire
    .replace(
      old="\"dispatch_reserved\":false",
      new="\"dispatch_reserved\":true",
    )
    .replace(
      old="\"physical_start_claimed\":false",
      new="\"physical_start_claimed\":true",
    ),
  )
  assert_true(
    validate_local_saved_submitted_rows(
      rows, plan, value, run_key, 9L, later, submission_key, 2L, submitted,
    )
    is Ok(_),
  )
}

///|
test "saved row relationship refuses preparing missing NULL and changed original intent" {
  let value = submitted_rows_preparation("/*😀*/\r\nSELECT 1 AS n")
  let plan = submitted_rows_plan(value)
  let before = submitted_rows_before(value)
  let rows = submitted_rows_prepare(plan, value, before).unwrap()
  let (run_key, submission_key, _, run, submitted) = local_submitted_run_rows(
    rows, plan, value,
  ).unwrap()
  let wire = @utf8.decode(submitted) catch { _ => "" }
  for
    body in [
      before,
      b"null",
      b"{}",
      @utf8.encode(wire.replace(old="SELECT 1 AS n", new="SELECT 2 AS n")),
      @utf8.encode(wire.replace(old="original-submit", new="different-submit")),
    ] {
    assert_true(
      validate_local_saved_submitted_rows(
        rows, plan, value, run_key, 0L, run, submission_key, 1L, body,
      )
      is Err(CustodyLost),
    )
  }
}

///|
test "saved row relationship rejects foreign keys and negative physical generations" {
  let value = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(value)
  let rows = submitted_rows_prepare(plan, value, submitted_rows_before(value)).unwrap()
  let (run_key, submission_key, _, run, submitted) = local_submitted_run_rows(
    rows, plan, value,
  ).unwrap()
  for
    (key, revision, reference, generation) in [
      ("foreign-run", 0L, submission_key, 1L),
      (run_key, -1L, submission_key, 1L),
      (run_key, 0L, "foreign-submission", 1L),
      (run_key, 0L, submission_key, -1L),
    ] {
    assert_true(
      validate_local_saved_submitted_rows(
        rows, plan, value, key, revision, run, reference, generation, submitted,
      )
      is Err(CustodyLost),
    )
  }
}

///|
test "saved row relationship refuses equivalent preparations and copied Plan custody" {
  let value = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(value)
  let rows = submitted_rows_prepare(plan, value, submitted_rows_before(value)).unwrap()
  let (run_key, submission_key, _, run, submitted) = local_submitted_run_rows(
    rows, plan, value,
  ).unwrap()
  let equivalent = submitted_rows_preparation("SELECT 1 AS n")
  assert_true(
    validate_local_saved_submitted_rows(
      rows, plan, equivalent, run_key, 0L, run, submission_key, 1L, submitted,
    )
    is Err(ForeignPreparation),
  )
  let copied : LocalRunPlan = { ..plan, }
  assert_true(
    validate_local_saved_submitted_rows(
      rows, copied, value, run_key, 0L, run, submission_key, 1L, submitted,
    )
    is Err(ForeignPreparation),
  )
}

///|
test "original submitted rows bind nominal checked input without starting or admitting" {
  let value = submitted_rows_preparation("/*😀*/\r\nSELECT 1 AS n")
  assert_eq(
    @host.client_submitted_intent_cid(
      @input.local_submitted_preparation_intent(value),
    ),
    "sha256:8c4f70cd1eb0bfe127f3544bceb7fb2d6f1afabdfa158cb5e6208f06f3843749",
  )
  let plan = submitted_rows_plan(value)
  let before = submitted_rows_before(value)
  let rows = submitted_rows_prepare(plan, value, before).unwrap()
  let (run_key, submitted_key, retained, run, submitted) = local_submitted_run_rows(
    rows, plan, value,
  ).unwrap()
  assert_eq(run_key, @host.client_request_scope_cid(plan.request))
  assert_eq(
    submitted_key, "sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267",
  )
  assert_eq(retained, before)
  // Fixed original journal field/phase expectations; no product output is
  // used to choose the flags, initial revision or omitted private originals.
  let run = @json.parse(@utf8.decode(run))
  guard run is Object(run) else { fail("Expected original Run row") }
  for
    field in [
      "dispatch_reserved", "physical_start_claimed", "cancellation_requested",
    ] {
    assert_eq(run.get(field), Some(@json.to_json(false)))
  }
  assert_eq(run.get("checkpoint"), Some(@json.to_json(())))
  assert_eq(run.get("publication_binding"), Some(@json.to_json(())))
  assert_eq(run.get("publication_policy_originals"), None)
  assert_eq(run.get("effect_material_originals"), None)
  assert_eq(
    run.get("version"),
    Some(@json.to_json("actql-native-client-run-row/0.1")),
  )
  let body = @json.parse(@utf8.decode(submitted))
  guard body is Object(body) &&
    body.get("run_admission") is Some(String(admission)) else {
    fail("Expected original candidate admission")
  }
  assert_eq(body.get("phase"), Some(@json.to_json("ready")))
  assert_eq(
    body.get("reference"),
    Some(@json.to_json(submitted_rows_reference_wire)),
  )
  let admission = @json.parse(admission)
  guard admission is Object(admission) else {
    fail("Expected original admission record")
  }
  assert_eq(admission.get("admitted_revision"), Some(@json.to_json("0")))
  assert_eq(
    admission.get("run_definition_cid"),
    Some(@json.to_json(local_run_definition_cid(plan))),
  )
}

///|
test "original submitted rows reject equivalent preparation copies and foreign Plan" {
  let value = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(value)
  let copy = submitted_rows_preparation("SELECT 1 AS n")
  let foreign = submitted_rows_preparation("SELECT 2 AS n")
  let before = submitted_rows_before(value)
  assert_true(
    submitted_rows_prepare(plan, copy, before) is Err(ForeignPreparation),
  )
  assert_true(
    submitted_rows_prepare(submitted_rows_plan(foreign), value, before)
    is Err(ForeignPreparation),
  )
  let rows = submitted_rows_prepare(plan, value, before).unwrap()
  assert_true(
    local_submitted_run_rows(rows, plan, copy) is Err(ForeignPreparation),
  )
  assert_true(
    local_submitted_run_rows(rows, submitted_rows_plan(value), value)
    is Err(ForeignPreparation),
  )
}

///|
test "original submitted rows reject changed retained bytes stale epoch and current denial" {
  let value = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(value)
  let before = submitted_rows_before(value)
  assert_true(submitted_rows_prepare(plan, value, b"{}") is Err(CustodyLost))
  assert_true(
    submitted_rows_prepare(plan, value, before, now=999.0)
    is Err(EpochNotAdmissible(NotYetValid)),
  )
  assert_true(
    submitted_rows_prepare(plan, value, before, now=2000.0)
    is Err(EpochNotAdmissible(Expired)),
  )
  assert_true(
    submitted_rows_prepare(plan, value, before, current=account(Deny))
    is Err(AuthorizationMismatch),
  )
  let rows = submitted_rows_prepare(plan, value, before).unwrap()
  assert_true(
    submitted_rows_prepare(plan, value, rows.submitted) is Err(CustodyLost),
  )
}

///|
test "original submitted rows reject foreign authority reference and changed compiled binding" {
  let value = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(value)
  let input = @input.local_submitted_preparation_input(value)
  let current = account(Allow)
  let before = submitted_rows_before(value)
  for
    wire in [
      submitted_rows_reference_wire.replace(
        old="original-submit",
        new="different-submit",
      ),
      submitted_rows_reference_wire.replace(
        old="sha256:bbbb",
        new="sha256:dddd",
      ),
    ] {
    assert_true(
      prepare_local_submitted_run_rows(
        plan,
        value,
        @host.admit_client_submission_reference_record(wire).unwrap(),
        before,
        permit(input, current),
        current,
        tuple(),
        context_cid(),
        1000.0,
      )
      is Err(ForeignReference),
    )
  }
  let other = submitted_rows_plan(submitted_rows_preparation("SELECT 2 AS n"))
  assert_true(
    submitted_rows_prepare({ ..plan, compiled: other.compiled, }, value, before)
    is Err(Binding(_)),
  )
  assert_true(
    prepare_local_submitted_run_rows(
      plan,
      value,
      @host.admit_client_submission_reference_record(
        submitted_rows_reference_wire,
      ).unwrap(),
      before,
      permit(input, current),
      current,
      tuple(),
      "sha256:" + "f".repeat(64),
      1000.0,
    )
    is Err(AuthorizationMismatch),
  )
}

///|
test "SDK issued CAS candidate keeps the same observation originals as submitted rows" {
  let preparation = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(preparation)
  let policy = submitted_rows_finite_policy(plan)
  let input = @input.local_submitted_preparation_input(preparation)
  let reference = @host.admit_client_submission_reference_record(
    submitted_rows_reference_wire,
  ).unwrap()
  let rows = prepare_local_sdk_submitted_run_rows(
    plan,
    preparation,
    reference,
    submitted_rows_before(preparation),
    permit(input, account(Allow)),
    account(Allow),
    tuple(),
    context_cid(),
    1000.0,
    policy,
  ).unwrap()
  let (_, _, _, submitted_run, _) = local_submitted_run_rows(
    rows, plan, preparation,
  ).unwrap()
  let observation = @host.capture_client_run_observation_originals(
    local_run_compiled(plan),
    local_run_definition(plan),
  ).unwrap()
  let issued : @host.ClientJournalPhysicalRow = {
    key: "issued",
    revision: 23L,
    body: b"0",
  }
  let append = fn(originals : @host.ClientRunObservationOriginals?) {
    @host.prepare_client_run_journal_append(
      local_run_request(plan),
      local_run_definition(plan),
      1024,
      (table, cursor) => {
        Ok(
          if table == "client_run_custody" && cursor == "" {
            Some(issued)
          } else {
            None
          },
        )
      },
      (table, key) => {
        Ok(
          if table == "client_run_custody" && key == "issued" {
            Some(issued)
          } else {
            None
          },
        )
      },
      _ => Err("unexpected saved Run"),
      () => Ok(()),
      "custody",
      local_policy_original=Some(policy),
      run_observation_originals=originals,
    )
  }
  guard append(Some(observation)) is Ok(Append(candidate)) else {
    fail("no original SDK CAS candidate")
  }
  let (key, body, revision, count) = @host.client_run_journal_append_rows(
    candidate,
  )
  assert_eq(key, @host.client_request_scope_cid(local_run_request(plan)))
  assert_eq(body, submitted_run)
  assert_eq(revision, 23L)
  assert_eq(count, b"1")
  guard append(None) is Ok(Append(legacy)) else { fail("no legacy candidate") }
  let (_, old_body, _, _) = @host.client_run_journal_append_rows(legacy)
  assert_true(old_body != submitted_run)
  assert_eq(
    @host.decode_client_run_journal_row_with_observation_originals(old_body).unwrap().2,
    None,
  )
  let other = submitted_rows_plan(
    submitted_rows_preparation("SELECT 2 AS n"),
    run_id="foreign-observation",
  )
  let foreign = @host.capture_client_run_observation_originals(
    local_run_compiled(other),
    local_run_definition(other),
  ).unwrap()
  assert_true(append(Some(foreign)) is Err(InvalidOriginal))
}
