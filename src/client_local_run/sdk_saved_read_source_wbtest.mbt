///|
// Actual Common compilation/Receipt/commit inputs, saved through the existing
// codecs and original row reader. The epoch authenticator, adoption identity
// and Store port are metadata fixtures, not physical Host/funding evidence.
fn sdk_saved_source_snapshot(
  fixture : SDKReadFixture,
  observations? : Bool = true,
) -> @host.ClientSavedSubmissionSnapshot raise {
  let plan = fixture.preflight.intent.plan
  let reference = @host.admit_client_submission_reference_record(
    fixture.reference_wire,
  ).unwrap()
  let original = @host.capture_client_run_observation_originals(
    plan.compiled,
    plan.definition,
  ).unwrap()
  let run : @host.ClientJournalPhysicalRow = {
    key: @host.client_request_scope_cid(plan.request),
    revision: 0L,
    body: @host.client_run_journal_row_body(
      {
        request: plan.request,
        definition: plan.definition,
        dispatch_reserved: true,
        physical_start_claimed: true,
        cancellation_requested: false,
        publication_binding: None,
        publication_policy_originals: None,
        effect_material_originals: None,
        checkpoint: None,
      },
      local_run_policy_originals=Some(
        @utf8.decode(
          @host.client_local_run_policy_original_body(fixture.original),
        ),
      ),
      run_observation_originals=if observations {
        Some(original.wire().unwrap())
      } else {
        None
      },
    ).unwrap(),
  }
  let submitted : @host.ClientJournalPhysicalRow = {
    key: @host.client_submission_reference_record_request_id(reference),
    revision: 0L,
    body: @host.client_submitted_intent_journal_row_body(
      fixture.reference_wire,
      @host.prepare_client_submitted_intent(
        "{\"kind\":\"aql\",\"input\":{\"format\":\"aql\",\"text\":\"SELECT 1 AS n\"},\"parameters\":null}",
        65536, 8192, 64,
      ).unwrap(),
      run_admission=Some((plan.request, local_run_definition_cid(plan), 0L)),
      run_state_observation=Some((0L, None)),
    ).unwrap(),
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
      @host.decode_client_run_journal_row_with_observation_originals(row.body)
      .map(decoded => {
        let value = decoded.0
        let inspection : @host.ClientRunJournalInspection = {
          request: value.request,
          definition: value.definition,
          checkpoint: None,
        }
        inspection
      })
      .map_err(_ => "invalid saved Run")
    },
    "unavailable saved original",
  )
  .unwrap()
  .unwrap()
}

///|
fn sdk_saved_source(
  fixture : SDKReadFixture,
  observations? : Bool = true,
  adoption? : String = "sha256:" + "a".repeat(64),
) -> Result[LocalSDKReadSource, LocalSDKReadOriginalsIssue] raise {
  let (principal, connection, _, _, _, _, _) = @publication.local_sdk_result_read_selection_parameters(
    fixture.selection,
  )
  prepare_local_saved_sdk_read_source(
    sdk_saved_source_snapshot(fixture, observations~),
    fixture.original,
    (source_free_original_policy_cid, source_free_original_policy),
    fixture.account,
    principal,
    connection,
    adoption,
    fixture.owner,
    fixture.view,
  )
}

///|
test "saved SDK read source preserves original evidence and delivery formulas without a new plan" {
  let fixture = sdk_read_fixture(bound_scope=true)
  let source = sdk_saved_source(fixture).unwrap()
  let (_, _, _, name, format, _, _) = @publication.local_sdk_result_read_selection_parameters(
    fixture.selection,
  )
  let at = "2026-10-13T00:00:03.000Z"
  let attempt = "same-saved-read"
  let saved = prepare_local_sdk_read_originals_for_source(
    source,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    name,
    format,
    attempt,
    at,
    16,
  ).unwrap()
  let live = prepare_local_sdk_read_originals(
    fixture.preflight,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    name,
    format,
    attempt,
    at,
    16,
  ).unwrap()
  for ordinal in 0..<3 {
    assert_eq(
      local_sdk_read_original(saved, ordinal).unwrap(),
      local_sdk_read_original(live, ordinal).unwrap(),
    )
  }
  let (key, body) = local_sdk_read_evidence_packet(saved).unwrap()
  fn read(
    table : String,
    wanted : String,
  ) -> Result[@host.ClientJournalPhysicalRow?, String] {
    if table == "client_local_read_evidence" && wanted == key {
      Ok(Some({ key, revision: 0L, body, }))
    } else {
      Ok(None)
    }
  }
  let grant = issue_local_sdk_read_grant_for_source(
    source,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    name,
    format,
    attempt,
    at,
    16,
    read,
    () => Ok(()),
  ).unwrap()
  let original_grant = issue_local_sdk_read_grant_from_store(
    fixture.preflight,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    name,
    format,
    attempt,
    at,
    16,
    read,
    () => Ok(()),
  ).unwrap()
  assert_eq(
    @publication.publication_contract_json(grant),
    @publication.publication_contract_json(original_grant),
  )
  let delivery = prepare_local_sdk_read_delivery_for_source(
    source,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    name,
    format,
    attempt,
    at,
    16,
    read,
    () => Ok(()),
  ).unwrap()
  let original_delivery = prepare_local_sdk_read_delivery_from_store(
    fixture.preflight,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    name,
    format,
    attempt,
    at,
    16,
    read,
    () => Ok(()),
  ).unwrap()
  for ordinal in 0..<3 {
    assert_eq(
      local_sdk_read_delivery_original(delivery, ordinal).unwrap(),
      local_sdk_read_delivery_original(original_delivery, ordinal).unwrap(),
    )
  }
  (fixture.cleanup)()
}

///|
test "saved SDK source refuses missing old originals foreign adoption and expired read" {
  let fixture = sdk_read_fixture(bound_scope=true)
  assert_true(
    sdk_saved_source(fixture, observations=false) is Err(InvalidOriginal),
  )
  assert_true(
    sdk_saved_source(fixture, adoption="sha256:" + "d".repeat(64))
    is Err(InvalidOriginal),
  )
  let source = sdk_saved_source(fixture).unwrap()
  let (_, _, _, name, format, _, _) = @publication.local_sdk_result_read_selection_parameters(
    fixture.selection,
  )
  assert_true(
    prepare_local_sdk_read_originals_for_source(
      source,
      fixture.account,
      fixture.original,
      fixture.selection,
      "sha256:" + "a".repeat(64),
      fixture.owner,
      fixture.view,
      name,
      format,
      "expired-original",
      "2026-10-14T00:00:00.001Z",
      16,
    )
    is Err(Expired),
  )
  (fixture.cleanup)()
}

///|
test "saved SDK source cannot replace or revive its nominal stored view" {
  let fixture = sdk_read_fixture(bound_scope=true)
  let other = sdk_read_fixture(bound_scope=true)
  let source = sdk_saved_source(fixture).unwrap()
  let (_, _, _, name, format, _, _) = @publication.local_sdk_result_read_selection_parameters(
    fixture.selection,
  )
  assert_true(
    prepare_local_sdk_read_originals_for_source(
      source,
      fixture.account,
      fixture.original,
      fixture.selection,
      "sha256:" + "a".repeat(64),
      other.owner,
      other.view,
      name,
      format,
      "foreign-view",
      "2026-10-13T00:00:03.000Z",
      16,
    )
    is Err(InvalidOriginal),
  )
  fixture.owner.cancel()
  assert_true(
    prepare_local_sdk_read_originals_for_source(
      source,
      fixture.account,
      fixture.original,
      fixture.selection,
      "sha256:" + "a".repeat(64),
      fixture.owner,
      fixture.view,
      name,
      format,
      "closed-view",
      "2026-10-13T00:00:03.000Z",
      16,
    )
    is Err(StoredChain(_)),
  )
  (fixture.cleanup)()
  (other.cleanup)()
}
