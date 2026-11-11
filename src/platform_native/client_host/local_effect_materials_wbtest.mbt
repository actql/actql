///|
// Trusted fixture setup represents an earlier admitted Run. Its historical
// acceptance is not current permission; the public material lookup reads the
// real adopted Account. These Native definitions are compile-only until run.
fn local_original_effect_material_fixture(
  name : String,
  read_run : Bool,
  other_permissions : Bool,
) -> (
  NativeLocalHostConnection,
  NativeClientSubmissionReference,
  NativeClientSubmittedPreparation,
  @host.ClientRequestIdentity,
  @host.ClientEffectAllowedRun,
  @publication.PublicationContract,
  @host.ClientEffectIssuedNormalizationMaterials,
) raise {
  let entries : Array[String] = []
  if read_run {
    entries.push(
      (
        #|{"entry_id":"read-run","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["read"]},"exclusions":[]}
      ),
    )
  }
  if other_permissions {
    entries.push(
      (
        #|{"entry_id":"read-source-and-result","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["connector://crm/main/r#v","result/answer"]},"operation":{"any_of":["read"]},"exclusions":[]}
      ),
    )
    entries.push(
      (
        #|{"entry_id":"submit","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["submit"]},"exclusions":[]}
      ),
    )
  }
  let body = @utf8.encode(
    "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[" +
    entries.join(",") +
    "]}",
  )
  let host = policy_host_fixture(name, account_body=body)
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let authority = host.epoch_authority().unwrap()
  let epoch = authority.issue_epoch(scope, true, 1000.0).unwrap()
  let reference = prepare_native_client_submission_reference(
    epoch, "original-submit",
  ).unwrap()
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    native_client_effect_fixture_document +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = native_client_effect_fixture_preparation(intent)
  let (request, allowed, definition) = native_client_effect_fixture_run(
    preparation,
    reference,
    "original-material-run",
    scope~,
  )
  let journal = host.run_journal().unwrap()
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
  let issued = @host.issue_prepared_client_effect_normalization_materials(
    allowed,
    definition,
    @host.issue_prepared_client_effect_normalization(
      @host.client_effect_compilation_owner(allowed.compilation),
    ).unwrap(),
    request=Some(request),
  ).unwrap()
  (host, reference, preparation, request, allowed, definition, issued)
}

///|
test "Native Host original materials require Run read independently of submit Source and Result permissions" {
  for
    (read_run, other, permitted) in [
      (false, false, false),
      (false, true, false),
      (true, false, true),
      (true, true, true),
    ] {
    let (host, reference, preparation, request, allowed, definition, issued) = local_original_effect_material_fixture(
      "local-material-read-" + read_run.to_string() + "-" + other.to_string(),
      read_run,
      other,
    )
    let journal = host.run_journal().unwrap()
    let before = journal.retained(request).unwrap().unwrap()
    let body = run_record_body(before).unwrap()
    let submission = journal.retained_submission(reference).unwrap().unwrap()
    let capacity = run_journal_custody(journal.database, 8).unwrap()
    for _ in 0..<2 {
      let result = host.bind_submitted_effect_original_materials(
        epoch_test_crypto(),
        "operator",
        "cli",
        reference,
        preparation,
        request,
        allowed,
        definition,
        issued,
        1003.0,
      )
      if permitted {
        let materials = result.unwrap()
        assert_true(physical_equal(materials.compilation, allowed.compilation))
        assert_true(
          physical_equal(
            materials.prepared,
            @host.client_effect_compilation_owner(allowed.compilation),
          ),
        )
      } else {
        assert_true(result is Err(Journal(AuthorizationDenied)))
      }
      assert_eq(
        run_record_body(journal.retained(request).unwrap().unwrap()).unwrap(),
        body,
      )
      assert_eq(
        journal.retained_submission(reference).unwrap().unwrap().revision,
        submission.revision,
      )
      assert_eq(run_journal_custody(journal.database, 8).unwrap(), capacity)
    }
    host.close().unwrap()
  }
}

///|
test "Native Host original material read refuses foreign Host principal connection and closed custody" {
  let (host, reference, preparation, request, allowed, definition, issued) = local_original_effect_material_fixture(
    "local-material-authority", true, true,
  )
  // Both live Hosts retain distinct exclusive Adoption parents.
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_private_root(path).unwrap()
  let state_name = "local-material-foreign-parent"
  parent.create_directory(state_name).unwrap() |> ignore
  parent.close().unwrap()
  let foreign = policy_host_fixture(
    "local-material-foreign-host",
    state_parent=Some(path + "/" + state_name),
  )
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  for (principal, connection) in [("other", "cli"), ("operator", "other")] {
    assert_true(
      host.bind_submitted_effect_original_materials(
        epoch_test_crypto(),
        principal,
        connection,
        reference,
        preparation,
        request,
        allowed,
        definition,
        issued,
        1003.0,
      )
      is Err(Journal(AuthorizationDenied)),
    )
  }
  assert_true(
    foreign.bind_submitted_effect_original_materials(
      epoch_test_crypto(),
      "operator",
      "cli",
      reference,
      preparation,
      request,
      allowed,
      definition,
      issued,
      1003.0,
    )
    is Err(Journal(AuthorizationDenied)),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    before,
  )
  foreign.close().unwrap()
  host.close().unwrap()
  assert_true(
    host.bind_submitted_effect_original_materials(
      epoch_test_crypto(),
      "operator",
      "cli",
      reference,
      preparation,
      request,
      allowed,
      definition,
      issued,
      1003.0,
    )
    is Err(Journal(AuthorizationDenied)),
  )
}

///|
test "Native Host material authority rechecks adopted Account generation at every journal fence" {
  for loss_at in 1..<4 {
    let name = "local-material-current-" + loss_at.to_string()
    let (host, reference, preparation, request, allowed, definition, issued) = local_original_effect_material_fixture(
      name, true, true,
    )
    let authority = native_local_policy_authority_for(
      host,
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      ReadRunMaterials,
    ).unwrap()
    let journal = host.journal
    let before = run_record_body(journal.retained(request).unwrap().unwrap()).unwrap()
    let calls = Ref(0)
    // Private test injection replaces the actual adopted Account file, not the
    // decision result. The public Host API accepts no caller permission callback.
    let current = () => {
      calls.val += 1
      if calls.val == loss_at {
        let parent = host.session.source_root
        let account = name + ".account.json"
        let generation = parent.inspect_generation(account).unwrap().unwrap()
        parent.reclaim_generation(account, generation).unwrap()
        let writer = parent.create_writer(name + ".replacement", 4096L).unwrap()
        writer.append(policy_account_original).unwrap()
        writer.seal(account).unwrap() |> ignore
      }
      authority.current_for(journal, request)
    }
    assert_true(
      journal.bind_submitted_effect_original_materials(
        host.epoch,
        reference,
        preparation,
        request,
        allowed,
        definition,
        issued,
        authority.scope,
        current,
        1003.0,
      )
      is Err(Journal(AuthorizationDenied)),
    )
    assert_eq(calls.val, loss_at)
    assert_eq(
      run_record_body(journal.retained(request).unwrap().unwrap()).unwrap(),
      before,
    )
    assert_true(
      host.bind_submitted_effect_original_materials(
        epoch_test_crypto(),
        "operator",
        "cli",
        reference,
        preparation,
        request,
        allowed,
        definition,
        issued,
        1003.0,
      )
      is Err(Journal(AuthorizationDenied)),
    )
    host.close().unwrap()
  }
}

///|
test "Native Run material read does not substitute for existing submit or named Result Policy authorization" {
  let (host, _, _, request, _, _, _) = local_original_effect_material_fixture(
    "local-material-read-only", true, false,
  )
  let crypto = epoch_test_crypto()
  assert_true(
    native_local_policy_authority_for(
      host,
      crypto,
      "operator",
      "cli",
      request,
      ReadRunMaterials,
    )
    is Ok(_),
  )
  assert_true(
    native_local_policy_authority(
      host,
      crypto,
      "operator",
      "cli",
      request,
      None,
    )
    is Err(AuthorizationDenied),
  )
  for result in ["answer", "", "x".repeat(129)] {
    assert_true(
      native_local_policy_authority(
        host,
        crypto,
        "operator",
        "cli",
        request,
        Some(result),
      )
      is Err(AuthorizationDenied),
    )
  }
  host.close().unwrap()
  let all = policy_host_fixture("local-material-old-purpose")
  let scope = all.authority_scope_cid("operator", "cli", crypto).unwrap()
  let (request, _, _, _) = journal_test_run("purpose", "purpose-run", scope~)
  assert_true(
    native_local_policy_authority(all, crypto, "operator", "cli", request, None)
    is Ok(_),
  )
  assert_true(
    native_local_policy_authority(
      all,
      crypto,
      "operator",
      "cli",
      request,
      Some("answer"),
    )
    is Ok(_),
  )
  assert_true(
    native_local_policy_authority(
      all,
      crypto,
      "operator",
      "cli",
      request,
      Some("other"),
    )
    is Err(AuthorizationDenied),
  )
  all.close().unwrap()
}

///|
test "Native Host material authority cannot authorize changed intent or a copied physical preparation" {
  let (host, reference, preparation, request, allowed, definition, issued) = local_original_effect_material_fixture(
    "local-material-original-only", true, true,
  )
  let original = run_record_body(
    host.journal.retained(request).unwrap().unwrap(),
  ).unwrap()
  let changed = { ..preparation, intent_cid: "sha256:" + "f".repeat(64), }
  assert_true(
    host.bind_submitted_effect_original_materials(
      epoch_test_crypto(),
      "operator",
      "cli",
      reference,
      changed,
      request,
      allowed,
      definition,
      issued,
      1003.0,
    )
    is Err(ChangedIntent),
  )
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    native_client_effect_fixture_document +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let copied = native_client_effect_fixture_preparation(intent)
  assert_true(
    host.bind_submitted_effect_original_materials(
      epoch_test_crypto(),
      "operator",
      "cli",
      reference,
      copied,
      request,
      allowed,
      definition,
      issued,
      1003.0,
    )
    is Err(ForeignPreparation),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    original,
  )
  host.close().unwrap()
}
