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
test "SDK read identity projection borrows the existing live and saved originals" {
  let fixture = sdk_read_fixture(bound_scope=true)
  defer (fixture.cleanup)()
  let live = local_sdk_read_source(fixture.preflight)
  let saved = sdk_saved_source(fixture).unwrap()
  for source in [live, saved] {
    let (request, definition) = local_sdk_read_source_run_identity(source)
    assert_true(physical_equal(request, source.request()))
    assert_true(physical_equal(definition, source.definition()))
  }
  let (request, definition) = local_sdk_read_source_run_identity(saved)
  let snapshot = sdk_saved_source_snapshot(fixture)
  let row = @host.client_saved_submission_run_row(snapshot).unwrap()
  let (decoded, _, _) = @host.decode_client_run_journal_row_with_retained_identity(
    row.body,
    request,
    definition,
  ).unwrap()
  assert_true(physical_equal(decoded.request, request))
  assert_true(physical_equal(decoded.definition, definition))
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

///|
test "saved SDK source rejects a later valid finite Policy with another adoption" {
  let fixture = sdk_read_fixture(bound_scope=true)
  let source = sdk_saved_source(fixture).unwrap()
  let plan = fixture.preflight.intent.plan
  let at = @host.client_local_run_policy_original_issued_at(fixture.original)
  let bootstrap = @host.client_local_product_sdk_bootstrap_originals(
    "/private/local", at,
  ).unwrap()
  let foreign_adoption = "sha256:" + "d".repeat(64)
  // This is genuinely admitted metadata for the same request/definition and
  // retention, rather than an invalid JSON body or an altered policy deadline.
  // It must not replace the exact original already retained in the Run row.
  let foreign = @host.bind_client_local_run_policy_original(
    bootstrap.profile,
    @host.admit_client_submission_reference_record(fixture.reference_wire).unwrap(),
    plan.request,
    plan.definition,
    @host.client_local_run_policy_original_retention(fixture.original),
    at,
    foreign_adoption,
    @publication.local_sdk_result_read_selection_cid(fixture.selection),
  ).unwrap()
  let (_, _, _, name, format, _, _) = @publication.local_sdk_result_read_selection_parameters(
    fixture.selection,
  )
  assert_true(
    prepare_local_sdk_read_originals_for_source(
      source,
      fixture.account,
      foreign,
      fixture.selection,
      foreign_adoption,
      fixture.owner,
      fixture.view,
      name,
      format,
      "foreign-finite-original",
      "2026-10-13T00:00:03.000Z",
      16,
    )
    is Err(InvalidOriginal),
  )
  (fixture.cleanup)()
}

///|
// Existing schema, framing, sink and terminal Owners, using only the saved
// read origin. The Store supplier is a typed double, not a physical COMMIT.
test "saved SDK source reaches existing payload codecs and terminal observation" {
  let fixture = sdk_read_fixture(bound_scope=true)
  defer (fixture.cleanup)()
  let source = sdk_saved_source(fixture).unwrap()
  let (key, packet) = sdk_delivery_evidence(fixture)
  let first : LocalSDKReadDeliveryPreparation = prepare_local_sdk_read_delivery_for_source(
    source,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    "answer",
    "jsonl",
    "sdk-read-original",
    "2026-10-13T00:00:04.000Z",
    16,
    (table, _) => {
      let result : Result[@host.ClientJournalPhysicalRow?, String] = if table ==
        "client_local_read_evidence" {
        Ok(Some({ key, revision: 0L, body: packet, }))
      } else {
        Ok(None)
      }
      result
    },
    () => Ok(()),
  ).unwrap()
  let rows = sdk_payload_codec_rows(fixture)
  let read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, String] = (
    table,
    key,
  ) => Ok(rows.get(table + "|" + key))
  let encoding = prepare_local_sdk_payload_encoding_for_source(
    source,
    fixture.account,
    fixture.original,
    fixture.selection,
    "sha256:" + "a".repeat(64),
    fixture.owner,
    fixture.view,
    first,
    "answer",
    "jsonl",
    "sdk-read-original",
    "2026-10-13T00:00:05.000Z",
    16,
    65536,
    65536,
    read,
    () => Ok(()),
  ).unwrap()
  let (ordinal, binding) = encoding
    .stored_payload_ordinals(fixture.owner, fixture.view, "answer", 16, 256)
    .unwrap()
  let selected = fixture.owner
    .observed_result_read_materials(fixture.view, "answer", 16)
    .unwrap()
  let names = @publication.manifest_result_names(
    fixture.owner.view_contract(fixture.view, 2).unwrap(),
  ).unwrap()
  assert_eq(names[ordinal], "answer")
  assert_eq(
    local_sdk_saved_result_coordinates(
      source,
      fixture.account,
      fixture.owner,
      fixture.view,
      "answer",
    ).unwrap(),
    (ordinal, binding),
  )
  assert_eq(
    @publication.publication_contract_identity(
      fixture.owner.view_binding(fixture.view, binding).unwrap(),
    ),
    selected.read.durable_result_binding_cid,
  )
  assert_true(
    encoding.stored_payload_ordinals(
      fixture.owner,
      fixture.view,
      "foreign",
      16,
      256,
    )
    is Err(_),
  )
  assert_eq(encoding.feed(b"[{\"n\":1}]", true), Ok(b"{\"n\":1}\n"))
  assert_eq(encoding.confirm_chunk(), Ok(8L))
  let terminal = encoding
    .prepare_terminal_for_source(
      source,
      fixture.account,
      fixture.original,
      fixture.selection,
      "sha256:" + "a".repeat(64),
      fixture.owner,
      fixture.view,
      "answer",
      "jsonl",
      "sdk-read-original",
      "2026-10-13T00:00:06.000Z",
      16,
      read,
      () => Ok(()),
    )
    .unwrap()
  assert_true(terminal.storage_from_store(read, () => Ok(())) is Ok(_))
  assert_true(
    terminal.observe_for_source(
      source,
      fixture.account,
      fixture.original,
      fixture.selection,
      "sha256:" + "a".repeat(64),
      fixture.owner,
      fixture.view,
      "answer",
      "jsonl",
      "sdk-read-original",
      16,
      read,
      () => Ok(()),
    )
    is Err(UnresolvedOriginal),
  )
  sdk_terminal_saved_rows(rows, terminal)
  assert_true(
    terminal.observe_for_source(
      source,
      fixture.account,
      fixture.original,
      fixture.selection,
      "sha256:" + "a".repeat(64),
      fixture.owner,
      fixture.view,
      "answer",
      "jsonl",
      "sdk-read-original",
      16,
      read,
      () => Ok(()),
    )
    is Ok(_),
  )
  assert_true(
    @publication.publication_contract_json(terminal.receipt).contains(
      sdk_payload_expected_delivery_hash,
    ),
  )
}
