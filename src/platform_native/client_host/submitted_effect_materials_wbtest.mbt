///|
// Actual Native journal callers; compilation is not physical execution evidence.
// The existing authored fixture supplies no Provider or acquisition permission.
fn submitted_original_effect_material_fixture(
  name : String,
) -> (
  @sqlite.Database,
  NativeClientRunJournal,
  NativeClientEpochAuthority,
  NativeClientSubmissionReference,
  NativeClientSubmittedPreparation,
  @host.ClientRequestIdentity,
  @host.ClientEffectAllowedRun,
  @publication.PublicationContract,
  @host.ClientEffectIssuedNormalizationMaterials,
) raise {
  let (database, journal, authority, reference) = submitted_test_setup(name)
  let (intent, preparation, request, allowed, definition) = native_client_effect_fixture_input(
    reference, "original-material-run",
  )
  let scope = "sha256:" + "a".repeat(64)
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  journal
  .accept_submitted_effect_run(
    authority, reference, preparation, request, allowed, definition, scope, true,
    1002.0,
  )
  .unwrap()
  |> ignore
  let prepared = @host.client_effect_compilation_owner(allowed.compilation)
  let issued = @host.issue_prepared_client_effect_normalization_materials(
    allowed,
    definition,
    @host.issue_prepared_client_effect_normalization(prepared).unwrap(),
    request=Some(request),
  ).unwrap()
  (
    database, journal, authority, reference, preparation, request, allowed, definition,
    issued,
  )
}

///|
test "Native original Submission material binding preserves cancelled or started journal facts" {
  for mode in ["accepted", "cancelled", "started"] {
    let (
      database,
      journal,
      authority,
      reference,
      preparation,
      request,
      allowed,
      definition,
      issued,
    ) = submitted_original_effect_material_fixture("submitted-material-" + mode)
    if mode == "cancelled" {
      journal
      .transaction(() => {
        let record = journal.retained(request).unwrap().unwrap()
        journal.save({ ..record, cancellation_requested: true, }).map(_ => ())
      })
      .unwrap()
    } else if mode == "started" {
      claim_native_client_effect_work_start(
        journal,
        request,
        allowed,
        definition,
        () => true,
      ).unwrap()
      |> ignore
    }
    let before = journal.retained(request).unwrap().unwrap()
    let body = run_record_body(before).unwrap()
    let original_submission = journal
      .retained_submission(reference)
      .unwrap()
      .unwrap()
    let capacity = run_journal_custody(database, 8).unwrap()
    let mut retained : @host.ClientEffectRunMaterials? = None
    for _ in 0..<2 {
      let materials = journal
        .bind_submitted_effect_original_materials(
          authority,
          reference,
          preparation,
          request,
          allowed,
          definition,
          issued,
          "sha256:" + "a".repeat(64),
          () => true,
          1003.0,
        )
        .unwrap()
      assert_true(physical_equal(materials.compilation, allowed.compilation))
      assert_true(
        physical_equal(
          materials.prepared,
          @host.client_effect_compilation_owner(allowed.compilation),
        ),
      )
      if retained is Some(original) {
        assert_true(
          physical_equal(
            materials.normalization.unwrap(),
            original.normalization.unwrap(),
          ),
        )
      }
      retained = Some(materials)
      let after = journal.retained(request).unwrap().unwrap()
      assert_eq(after.revision, before.revision)
      assert_eq(run_record_body(after).unwrap(), body)
      assert_eq(
        journal.retained_submission(reference).unwrap().unwrap().revision,
        original_submission.revision,
      )
      assert_eq(run_journal_custody(database, 8).unwrap(), capacity)
    }
    database.close_checked().unwrap()
  }
}

///|
test "Native original material binding rejects different intent Run or physical compilation" {
  let (
    database,
    journal,
    authority,
    reference,
    preparation,
    request,
    allowed,
    definition,
    issued,
  ) = submitted_original_effect_material_fixture("submitted-material-foreign")
  let scope = "sha256:" + "a".repeat(64)
  let before = journal.retained(request).unwrap().unwrap()
  let prepared = @host.client_effect_compilation_owner(allowed.compilation)
  let changed : NativeClientSubmittedPreparation = {
    ..preparation,
    intent_cid: "sha256:" + "f".repeat(64),
  }
  assert_true(
    journal.bind_submitted_effect_original_materials(
      authority,
      reference,
      changed,
      request,
      allowed,
      definition,
      issued,
      scope,
      () => true,
      1003.0,
    )
    is Err(ChangedIntent),
  )
  let different_request = @host.prepare_client_effect_request_identity(
    prepared,
    scope,
    "different-material-caller",
    @host.source_free_caller_input_intent_cid(),
  ).unwrap()
  assert_true(
    journal.bind_submitted_effect_original_materials(
      authority,
      reference,
      preparation,
      different_request,
      allowed,
      definition,
      issued,
      scope,
      () => true,
      1003.0,
    )
    is Err(ChangedIntent),
  )
  let (_, copied_preparation, _, _, _) = native_client_effect_fixture_input(
    reference, "original-material-run",
  )
  assert_true(
    journal.bind_submitted_effect_original_materials(
      authority,
      reference,
      copied_preparation,
      request,
      allowed,
      definition,
      issued,
      scope,
      () => true,
      1003.0,
    )
    is Err(ForeignPreparation),
  )
  let (_, _, different_run) = native_client_effect_fixture_run(
    preparation, reference, "different-material-run",
  )
  assert_true(
    journal.bind_submitted_effect_original_materials(
      authority,
      reference,
      preparation,
      request,
      allowed,
      different_run,
      issued,
      scope,
      () => true,
      1003.0,
    )
    is Err(ForeignRun),
  )
  let (_, equal_template_compilation, _) = native_client_effect_fixture_run(
    preparation, reference, "original-material-run",
  )
  assert_false(
    physical_equal(allowed.compilation, equal_template_compilation.compilation),
  )
  assert_true(
    journal.bind_submitted_effect_original_materials(
      authority,
      reference,
      preparation,
      request,
      equal_template_compilation,
      definition,
      issued,
      scope,
      () => true,
      1003.0,
    )
    is Err(Materials(Normalization(ForeignMaterials))),
  )
  let after = journal.retained(request).unwrap().unwrap()
  assert_eq(after.revision, before.revision)
  assert_eq(run_record_body(after).unwrap(), run_record_body(before).unwrap())
  database.close_checked().unwrap()
}

///|
test "Native current authority is rechecked before returning original material custody" {
  for denied_at in 1..<=3 {
    let (
      database,
      journal,
      authority,
      reference,
      preparation,
      request,
      allowed,
      definition,
      issued,
    ) = submitted_original_effect_material_fixture(
      "submitted-material-denied-" + denied_at.to_string(),
    )
    let before = journal.retained(request).unwrap().unwrap()
    let mut calls = 0
    assert_true(
      journal.bind_submitted_effect_original_materials(
        authority,
        reference,
        preparation,
        request,
        allowed,
        definition,
        issued,
        "sha256:" + "a".repeat(64),
        () => {
          calls += 1
          calls != denied_at
        },
        1003.0,
      )
      is Err(Journal(AuthorizationDenied)),
    )
    assert_eq(calls, denied_at)
    let after = journal.retained(request).unwrap().unwrap()
    assert_eq(after.revision, before.revision)
    assert_eq(run_record_body(after).unwrap(), run_record_body(before).unwrap())
    database.close_checked().unwrap()
  }
}

///|
test "Native material binding distinguishes retained preparation from unresolved Submission history" {
  for recorded in [false, true] {
    let (database, journal, authority, reference) = submitted_test_setup(
      "submitted-material-preparing-" + recorded.to_string(),
    )
    let (intent, preparation, request, allowed, definition) = native_client_effect_fixture_input(
      reference, "original-material-run",
    )
    if recorded {
      journal
      .record_submitted_intent(
        authority,
        reference,
        intent,
        "sha256:" + "a".repeat(64),
        true,
        1001.0,
      )
      .unwrap()
      |> ignore
    }
    let prepared = @host.client_effect_compilation_owner(allowed.compilation)
    let issued = @host.issue_prepared_client_effect_normalization_materials(
      allowed,
      definition,
      @host.issue_prepared_client_effect_normalization(prepared).unwrap(),
      request=Some(request),
    ).unwrap()
    let outcome = journal.bind_submitted_effect_original_materials(
      authority,
      reference,
      preparation,
      request,
      allowed,
      definition,
      issued,
      "sha256:" + "a".repeat(64),
      () => true,
      1003.0,
    )
    if recorded {
      assert_true(outcome is Err(MissingRunAdmission))
    } else {
      assert_true(outcome is Err(UnresolvedHistory))
    }
    assert_true(journal.lookup(request, true) is Ok(UnresolvedHistory))
    assert_eq(run_journal_custody(database, 8).unwrap().0, 0)
    database.close_checked().unwrap()
  }
}

///|
test "Native material binding does not overwrite cancellation accepted between its lookups" {
  let (
    database,
    journal,
    authority,
    reference,
    preparation,
    request,
    allowed,
    definition,
    issued,
  ) = submitted_original_effect_material_fixture(
    "submitted-material-concurrent-cancel",
  )
  let before = journal.retained(request).unwrap().unwrap()
  let mut calls = 0
  let materials = journal
    .bind_submitted_effect_original_materials(
      authority,
      reference,
      preparation,
      request,
      allowed,
      definition,
      issued,
      "sha256:" + "a".repeat(64),
      () => {
        calls += 1
        if calls == 2 {
          journal
          .transaction(() => {
            let record = journal.retained(request).unwrap().unwrap()
            journal
            .save({ ..record, cancellation_requested: true, })
            .map(_ => ())
          })
          .unwrap()
        }
        true
      },
      1003.0,
    )
    .unwrap()
  let after = journal.retained(request).unwrap().unwrap()
  assert_eq(calls, 3)
  assert_true(after.cancellation_requested)
  assert_false(after.dispatch_reserved)
  assert_false(after.physical_start_claimed)
  assert_eq(after.revision, before.revision + 1L)
  assert_eq(materials.request, Some(request))
  assert_true(
    claim_native_client_effect_work_start(
      journal,
      request,
      materials.allowed,
      materials.run_definition,
      () => true,
    )
    is Err(NeedsOriginalReconciliation),
  )
  assert_eq(
    journal.retained(request).unwrap().unwrap().revision,
    after.revision,
  )
  database.close_checked().unwrap()
}
