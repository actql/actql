///|
// Actual checked Run/Manifest and original-row codecs. Physical epoch/current,
// SQL COMMIT and installed Python remain outside this portable Owner fixture.
fn sdk_state_snapshot(
  fixture : SDKReadFixture,
  body : Bytes,
  revision : Int64,
) -> @host.ClientSavedSubmissionSnapshot {
  let plan = fixture.preflight.intent.plan
  let reference = @host.admit_client_submission_reference_record(
    submitted_rows_reference_wire,
  ).unwrap()
  let run : @host.ClientJournalPhysicalRow = {
    key: @host.client_request_scope_cid(plan.request),
    revision: 0L,
    body: @host.client_run_journal_row_body({
      request: plan.request,
      definition: plan.definition,
      dispatch_reserved: false,
      physical_start_claimed: false,
      cancellation_requested: false,
      publication_binding: None,
      publication_policy_originals: None,
      effect_material_originals: None,
      task_materials_cid: None,
      checkpoint: None,
    }).unwrap(),
  }
  let submitted : @host.ClientJournalPhysicalRow = {
    key: @host.client_submission_reference_record_request_id(reference),
    revision,
    body,
  }
  @host.read_client_saved_submission(
    reference,
    (table, key) => {
      if table == "client_runs" && key == run.key {
        Ok(Some(run))
      } else if table == "client_submitted_intents" && key == submitted.key {
        Ok(Some(submitted))
      } else {
        Ok(None)
      }
    },
    row => {
      match @host.decode_client_run_journal_row(row.body) {
        Ok(value) =>
          Ok({
            request: value.request,
            definition: value.definition,
            checkpoint: None,
            task_materials_cid: value.task_materials_cid,
          })
        Err(_) => Err("invalid original Run")
      }
    },
    "original custody unavailable",
  )
  .unwrap()
  .unwrap()
}

///|
fn sdk_state_initial_body(
  fixture : SDKReadFixture,
  issued? : Bool = true,
) -> Bytes {
  let plan = fixture.preflight.intent.plan
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"aql\",\"text\":\"SELECT 1 AS n\"},\"parameters\":null}",
    65536, 8192, 64,
  ).unwrap()
  @host.client_submitted_intent_journal_row_body(
    submitted_rows_reference_wire,
    intent,
    run_admission=Some((plan.request, local_run_definition_cid(plan), 0L)),
    run_state_observation=if issued { Some((0L, None)) } else { None },
  ).unwrap()
}

///|
fn sdk_state_materials(
  fixture : SDKReadFixture,
) -> @publication.ObservedResultReadMaterials {
  let (_, _, _, name, _, _, _) = @publication.local_sdk_result_read_selection_parameters(
    fixture.selection,
  )
  fixture.owner.observed_result_read_materials(fixture.view, name, 8).unwrap()
}

///|
test "SDK state first acceptance issues its zero marker in the original ready row" {
  let preparation = submitted_rows_preparation("SELECT 1 AS n")
  let plan = submitted_rows_plan(preparation)
  let before = submitted_rows_before(preparation)
  let original = submitted_rows_prepare(plan, preparation, before).unwrap()
  let (_, _, preparing, _, ready) = local_submitted_run_rows(
    original, plan, preparation,
  ).unwrap()
  assert_eq(preparing, before)
  let retained = @host.decode_client_submitted_journal_row(ready).unwrap()
  assert_eq(retained.run_state_observation, Some((0L, None)))
  assert_true(retained.run_state_original is None)
  assert_eq(retained.run_admission.unwrap().2, 0L)
}

///|
test "SDK state uses explicitly issued original counter and exact committed row" {
  let fixture = sdk_read_fixture()
  let plan = fixture.preflight.intent.plan
  let materials = sdk_state_materials(fixture)
  let raw = fixture.owner
    .observed_run_state_wire(
      fixture.view,
      "2026-10-13T00:00:03.000Z",
      65536,
      4096,
      32,
    )
    .unwrap()
  assert_true(!raw.contains("\"revision\""))
  let before = sdk_state_snapshot(fixture, sdk_state_initial_body(fixture), 6L)
  let update = @host.prepare_client_saved_run_state_update(
    before,
    plan.request,
    plan.definition,
    materials.manifest,
    raw,
  ).unwrap()
  let (_, prior, revision, body) = @host.client_saved_run_state_update_row(
    update,
  )
  assert_eq(prior, 6L)
  assert_eq(revision, 7L)
  let decoded = @host.decode_client_submitted_journal_row(body).unwrap()
  assert_eq(decoded.run_state_observation.unwrap().0, 0L)
  assert_true(decoded.run_state_observation.unwrap().1 is Some(_))
  assert_eq(decoded.run_admission.unwrap().2, 0L)
  assert_true(
    @host.confirm_client_saved_run_state_update(update, before) is Err(_),
  )
  let committed = sdk_state_snapshot(fixture, body, revision)
  let wire = @host.confirm_client_saved_run_state_update(update, committed).unwrap()
  assert_true(wire.contains("\"revision\":0"))
  assert_eq(@publication.run_wait_ready(wire, None, 65536, 8192, 64), Ok(true))
  assert_true(
    @host.confirm_client_saved_run_state_update(
      update,
      sdk_state_snapshot(fixture, body, revision + 1L),
    )
    is Err(_),
  )
  (fixture.cleanup)()
}

///|
test "SDK state clock-only observation preserves original wire without another write" {
  let fixture = sdk_read_fixture()
  let plan = fixture.preflight.intent.plan
  let materials = sdk_state_materials(fixture)
  let raw = fixture.owner
    .observed_run_state_wire(
      fixture.view,
      "2026-10-13T00:00:03.000Z",
      65536,
      4096,
      32,
    )
    .unwrap()
  let initial = sdk_state_snapshot(fixture, sdk_state_initial_body(fixture), 6L)
  let first = @host.prepare_client_saved_run_state_update(
    initial,
    plan.request,
    plan.definition,
    materials.manifest,
    raw,
  ).unwrap()
  let (_, _, revision, body) = @host.client_saved_run_state_update_row(first)
  let committed = sdk_state_snapshot(fixture, body, revision)
  let original = @host.confirm_client_saved_run_state_update(first, committed).unwrap()
  let later = fixture.owner
    .observed_run_state_wire(
      fixture.view,
      "2026-10-13T00:00:04.000Z",
      65536,
      4096,
      32,
    )
    .unwrap()
  let same = @host.prepare_client_saved_run_state_update(
    committed,
    plan.request,
    plan.definition,
    materials.manifest,
    later,
  ).unwrap()
  let (_, prior, next, retained) = @host.client_saved_run_state_update_row(same)
  assert_eq((prior, next, retained), (revision, revision, body))
  assert_eq(
    @host.confirm_client_saved_run_state_update(same, committed).unwrap(),
    original,
  )
  (fixture.cleanup)()
}

///|
test "SDK state refuses historical counter absence and foreign Run without repair" {
  let fixture = sdk_read_fixture()
  let plan = fixture.preflight.intent.plan
  let materials = sdk_state_materials(fixture)
  let raw = fixture.owner
    .observed_run_state_wire(
      fixture.view,
      "2026-10-13T00:00:03.000Z",
      65536,
      4096,
      32,
    )
    .unwrap()
  let legacy = sdk_state_snapshot(
    fixture,
    sdk_state_initial_body(fixture, issued=false),
    6L,
  )
  assert_true(
    @host.prepare_client_saved_run_state_update(
      legacy,
      plan.request,
      plan.definition,
      materials.manifest,
      raw,
    )
    is Err(@host.OriginalUnavailable),
  )
  let fresh = sdk_state_snapshot(fixture, sdk_state_initial_body(fixture), 6L)
  assert_true(
    @host.prepare_client_saved_run_state_update(
      fresh,
      plan.request,
      plan.definition,
      materials.manifest,
      raw.replace(old="sdk-original-run", new="foreign-run"),
    )
    is Err(_),
  )
  (fixture.cleanup)()
}

///|
test "SDK state semantic change advances only the same observation counter" {
  let fixture = sdk_read_fixture()
  let plan = fixture.preflight.intent.plan
  let materials = sdk_state_materials(fixture)
  let raw = fixture.owner
    .observed_run_state_wire(
      fixture.view,
      "2026-10-13T00:00:03.000Z",
      65536,
      4096,
      32,
    )
    .unwrap()
  let initial = sdk_state_snapshot(fixture, sdk_state_initial_body(fixture), 6L)
  let first = @host.prepare_client_saved_run_state_update(
    initial,
    plan.request,
    plan.definition,
    materials.manifest,
    raw,
  ).unwrap()
  let (_, _, revision, body) = @host.client_saved_run_state_update_row(first)
  let committed = sdk_state_snapshot(fixture, body, revision)
  // Metadata-only candidate. No expiration or physical availability is issued
  // by this portable counter; the actual caller supplies its original facts.
  let names = @publication.manifest_result_names(materials.manifest).unwrap()
  let changed = @publication.issue_succeeded_run_state_wire(
    @publication.run_definition_run_id(plan.definition).unwrap(),
    "2026-10-13T00:00:04.000Z",
    names,
    names,
    names.map(_ => "unavailable"),
    names.map(_ => "retention_expired"),
    names.map(_ => "2026-10-13T00:00:04.000Z"),
    65536,
    8192,
    64,
  ).unwrap()
  let second = @host.prepare_client_saved_run_state_update(
    committed,
    plan.request,
    plan.definition,
    materials.manifest,
    changed,
  ).unwrap()
  let (_, prior, next, updated) = @host.client_saved_run_state_update_row(
    second,
  )
  assert_eq((prior, next), (7L, 8L))
  let record = @host.decode_client_submitted_journal_row(updated).unwrap()
  assert_eq(record.run_state_observation.unwrap().0, 1L)
  assert_eq(record.run_admission.unwrap().2, 0L)
  assert_true(
    @host.confirm_client_saved_run_state_update(second, committed) is Err(_),
  )
  let after = sdk_state_snapshot(fixture, updated, next)
  let wire = @host.confirm_client_saved_run_state_update(second, after).unwrap()
  assert_true(wire.contains("\"revision\":1"))
  (fixture.cleanup)()
}
