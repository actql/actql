///|
// Common nominal rows/materials and an admitted saved read. Physical Store
// authenticity and current write transactions remain separate Host obligations.
fn publication_binding_saved_snapshot(
  plan : LocalRunPlan,
  run : @host.ClientJournalPhysicalRow,
  submitted : @host.ClientJournalPhysicalRow,
  wire : String,
) -> @host.ClientSavedSubmissionSnapshot {
  let record = @host.decode_client_submitted_journal_row(submitted.body).unwrap()
  let chunks = @host.client_task_material_original_chunks(run.key, wire).unwrap()
  @host.read_client_saved_submission(
    record.reference,
    (table, key) => {
      if table == "client_runs" && key == run.key {
        Ok(Some(run))
      } else if table == "client_submitted_intents" && key == submitted.key {
        Ok(Some(submitted))
      } else if table == "client_task_run_materials" {
        let mut found : @host.ClientJournalPhysicalRow? = None
        for (chunk_key, body) in chunks {
          if key == chunk_key {
            found = Some({ key, revision: 0L, body: @utf8.encode(body), })
          }
        }
        Ok(found)
      } else {
        Ok(None)
      }
    },
    row => {
      let (encoding, _, _) = @host.decode_client_run_journal_row_with_observation_originals(
        row.body,
      ).unwrap()
      @host.validate_client_run_binding(
        encoding.request,
        plan.prepared,
        plan.compiled,
        encoding.definition,
      ).unwrap()
      Ok({
        request: encoding.request,
        definition: encoding.definition,
        checkpoint: None,
        task_materials_cid: encoding.task_materials_cid,
      })
    },
    "missing saved custody",
  )
  .unwrap()
  .unwrap()
}

///|
test "saved snapshot publication binding uses original restored material without submitted candidates" {
  let (plan, _, _, run, submitted, store, material, current) = publication_binding_fixture(
    finite=true,
  )
  let wire = export_local_run_materials(
    plan,
    environment(),
    environment_wire,
    None,
  ).unwrap()
  let cid = @host.client_task_material_original_cid(wire).unwrap()
  let (encoding, finite, _) = @host.decode_client_run_journal_row_with_observation_originals(
    run.body,
  ).unwrap()
  let observation = Some(
    @host.capture_client_run_observation_originals(
      plan.compiled,
      plan.definition,
    )
    .unwrap()
    .wire()
    .unwrap(),
  )
  let run = {
    ..run,
    body: @host.client_run_journal_row_body(
      {
        ..encoding,
        task_materials_cid: Some(cid),
        publication_policy_originals: Some(
          @host.issue_client_run_policy_originals(
            plan.prepared,
            compiled=plan.compiled,
          ).unwrap(),
        ),
      },
      local_run_policy_originals=finite,
      run_observation_originals=observation,
    ).unwrap(),
  }
  let snapshot = publication_binding_saved_snapshot(plan, run, submitted, wire)
  let account = @authorization.admit_account_configuration_json(
    publication_binding_account_wire,
  ).unwrap()
  let decoded = restore_local_run_materials(
    wire,
    local_run_definition_cid(plan),
  ).unwrap()
  let retained = @host.bind_client_saved_submission_task_materials(
    snapshot, decoded,
  ).unwrap()
  let preparation = @input.restore_local_submitted_input(retained).unwrap()
  let input = @input.local_submitted_preparation_input(preparation)
  let restored = restore_source_free_local_run_from_materials(
    input,
    decoded,
    local_run_definition_cid(plan),
    plan.request,
    @host.client_request_authority_scope_cid(plan.request),
    permit(input, account),
    account,
    tuple(),
    context_cid(),
    "sha256:" + "c".repeat(64),
  ).unwrap()
  let restored = restore_source_free_local_run_policy_original(
    restored, retained,
  ).unwrap()
  assert_false(physical_equal(restored, plan))
  assert_true(
    validate_local_saved_snapshot_rows(restored, snapshot, run, submitted)
    is Ok(_),
  )
  guard prepare_local_saved_run_publication_binding(
      restored,
      snapshot,
      material,
      store,
      "local",
      "sha256:" + "d".repeat(64),
      21UL,
      29UL,
      run,
      submitted,
    )
    is Ok(Append(step)) else {
    fail("missing saved original binding candidate")
  }
  let (_, _, body) = local_run_publication_binding_rows(step)
  let saved = { ..run, revision: 1L, body, }
  let original = confirm_local_run_publication_binding(step, saved, submitted).unwrap()
  let (bound, policy, observations) = @host.decode_client_run_journal_row_with_observation_originals(
    body,
  ).unwrap()
  let started = {
    ..saved,
    revision: 3L,
    body: @host.client_run_journal_row_body(
      { ..bound, dispatch_reserved: true, physical_start_claimed: true, },
      local_run_policy_originals=policy,
      run_observation_originals=observations,
    ).unwrap(),
  }
  assert_true(
    validate_local_run_publication_binding_original(
      original, started, submitted,
    )
    is Ok(_),
  )
  let cold = publication_binding_saved_snapshot(
    restored, started, submitted, wire,
  )
  assert_true(
    prepare_local_saved_run_publication_binding(
      restored,
      cold,
      material,
      store,
      "local",
      "sha256:" + "d".repeat(64),
      21UL,
      29UL,
      started,
      submitted,
    )
    is Ok(Retained(_)),
  )
  assert_true(
    prepare_local_saved_run_publication_binding(
      restored,
      cold,
      material,
      Ref(0),
      "local",
      "sha256:" + "d".repeat(64),
      21UL,
      29UL,
      started,
      submitted,
    )
    is Err(Current(@host.ForeignStore)),
  )
  let reset = { ..started, revision: 4L, body: saved.body, }
  assert_true(
    validate_local_saved_snapshot_rows(restored, cold, reset, submitted)
    is Err(CustodyLost),
  )
  current.val = @host.NotAdopted
  assert_true(
    prepare_local_saved_run_publication_binding(
      restored,
      cold,
      material,
      store,
      "local",
      "sha256:" + "d".repeat(64),
      21UL,
      29UL,
      started,
      submitted,
    )
    is Err(Current(@host.NotAdopted)),
  )
}
