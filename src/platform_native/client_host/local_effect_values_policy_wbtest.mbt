///|
// Static phases only. Never render an issue payload, original wire or key.
fn[T, E] effect_values_policy_test_ok(
  value : Result[T, E],
  phase : String,
) -> T raise {
  match value {
    Ok(value) => value
    Err(_) => fail("Effect Values policy fixture: " + phase)
  }
}

///|
let effect_values_policy_test_account : Bytes = b"{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"effect-values-test\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":[\"read\",\"submit\"]},\"exclusions\":[]}]}"

///|
// Each Host has its own private parent/lock. The ordinary product assembler
// supplies the selected 45KB-class Run original; library paths are the actual
// pinned diagnostic inputs, never invented installation paths. No Run starts.
fn effect_values_policy_test_host(
  name : String,
  existing? : Bool = false,
  account? : Bytes = effect_values_policy_test_account,
  wrong_policy_cid? : Bool = false,
) -> NativeLocalHostConnection raise {
  let base = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let path = base + "/" + name
  if !existing {
    let parent = effect_values_policy_test_ok(
      @filesystem.open_private_root(base),
      "parent.open",
    )
    effect_values_policy_test_ok(parent.create_directory(name), "parent.child")
    |> ignore
    effect_values_policy_test_ok(parent.close(), "parent.close")
    let originals = effect_values_policy_test_ok(
      @host.client_local_product_originals(
        path,
        @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
        @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
        "2026-10-10T00:00:00.000Z",
        @host.client_local_product_assets(),
      ),
      "product.originals",
    )
    let run = originals.iter().find_first(pair => pair.0 == "run.json").unwrap().1
    assert_true(run.length() > 8192 && run.length() <= 65536)
    let run = if wrong_policy_cid {
      let text = @utf8.decode(run) catch { _ => fail("run.utf8") }
      @utf8.encode(
        text.replace(
          old="\"result_policy_cid\":\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\"",
          new="\"result_policy_cid\":\"sha256:570e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\"",
        ),
      )
    } else {
      run
    }
    let root = effect_values_policy_test_ok(
      @filesystem.open_private_root(path),
      "originals.root",
    )
    for (name, body) in [("account.original", account), ("selected.run", run)] {
      let writer = effect_values_policy_test_ok(
        root.create_writer(name + ".stage", 65536L),
        "original.writer",
      )
      effect_values_policy_test_ok(writer.append(body), "original.append")
      effect_values_policy_test_ok(writer.seal(name), "original.seal") |> ignore
    }
    effect_values_policy_test_ok(root.close(), "originals.close")
  }
  let adoption = effect_values_policy_test_ok(
    begin_native_local_host_adoption(
      path,
      "host",
      path,
      "account.original",
      "operator",
      epoch_test_crypto(),
      existing_only=existing,
      configuration_files=["selected.run"],
    ),
    "adoption",
  )
  effect_values_policy_test_ok(
    adoption.open_journal(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    ),
    "journal.open",
  )
}

///|
fn effect_values_policy_test_prepared(
  host : NativeLocalHostConnection,
  nonce : String,
  principal? : String = "operator",
  connection? : String = "cli",
  created_at? : String = "2026-10-10T00:00:00.000Z",
  valid_until? : String = "2026-10-11T00:00:00.000Z",
) -> (
  NativeClientSubmissionReference,
  NativeClientSubmittedPreparation,
  @host.ClientRequestIdentity,
  @host.ClientEffectAllowedRun,
  @publication.PublicationContract,
  @host.ClientEffectIssuedNormalizationMaterials,
) raise {
  let scope = effect_values_policy_test_ok(
    host.authority_scope_cid(principal, connection, epoch_test_crypto()),
    "scope",
  )
  let epoch = effect_values_policy_test_ok(
    host.epoch.issue_epoch(scope, true, 1000.0),
    "epoch",
  )
  let reference = effect_values_policy_test_ok(
    prepare_native_client_submission_reference(epoch, nonce),
    "reference",
  )
  let intent = effect_values_policy_test_ok(
    @host.prepare_client_submitted_intent(
      "{\"kind\":\"program\",\"input\":" +
      native_client_effect_fixture_document +
      ",\"parameters\":null}",
      65536,
      8192,
      64,
    ),
    "intent",
  )
  let preparation = native_client_effect_fixture_preparation(intent)
  guard preparation.preparation is EffectComputation(prepared) else {
    fail("preparation.Effect")
  }
  let normalization = effect_values_policy_test_ok(
    @host.issue_prepared_client_effect_normalization(prepared),
    "normalization",
  )
  let compilation = effect_values_policy_test_ok(
    @host.issue_prepared_client_effect_compilation(
      prepared,
      effect_original_restore_manifests(),
      @host.client_standard_values_sequence_limits(),
      32,
      64,
      100000,
      10000,
      100,
      normalization=Some(normalization),
    ),
    "compilation",
  )
  let configuration = effect_values_policy_test_ok(
    host.configuration(),
    "configuration",
  )
  let allowed = effect_values_policy_test_ok(
    @host.issue_client_effect_allowed_run(
      compilation,
      scope,
      configuration.configuration_cid(),
      valid_until,
    ),
    "allowed",
  )
  let definition = effect_values_policy_test_ok(
    @host.issue_client_effect_run_definition(
      allowed, "local-test", nonce, created_at, valid_until,
    ),
    "definition",
  )
  let request = effect_values_policy_test_ok(
    @host.prepare_client_effect_request_identity(
      prepared,
      scope,
      reference.request_id,
      @host.source_free_caller_input_intent_cid(),
    ),
    "request",
  )
  let issued = effect_values_policy_test_ok(
    @host.issue_prepared_client_effect_normalization_materials(
      allowed,
      definition,
      normalization,
      request=Some(request),
    ),
    "materials",
  )
  effect_values_policy_test_ok(
    host.journal.record_submitted_intent(
      host.epoch,
      reference,
      intent,
      scope,
      true,
      1001.0,
    ),
    "intent.save",
  )
  |> ignore
  (reference, preparation, request, allowed, definition, issued)
}

///|
fn effect_values_policy_test_accept(
  host : NativeLocalHostConnection,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  issued : @host.ClientEffectIssuedNormalizationMaterials,
  file? : String? = Some("selected.run"),
) -> Result[
  NativeClientSubmittedIntentRecord,
  NativeClientSubmittedEffectMaterialsIssue,
] {
  host.accept_submitted_effect_material_original(
    epoch_test_crypto(),
    "operator",
    "cli",
    reference,
    preparation,
    request,
    allowed,
    definition,
    issued,
    1002.0,
    source_free_run_file=file,
  )
}

///|
fn effect_values_policy_test_lookup(
  host : NativeLocalHostConnection,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
) -> Result[
  @publication.CapturedEffectDependencyBody,
  NativeClientSubmittedEffectMaterialsIssue,
] {
  host.lookup_submitted_effect_values_policy_original(
    epoch_test_crypto(),
    "operator",
    "cli",
    reference,
    request,
    1101.0,
  )
}

///|
test "Effect Values policy commits with its original packet once and reopens under current read" {
  let name = "values-policy-atomic-original"
  let host = effect_values_policy_test_host(name)
  defer host.close() |> ignore
  let (reference, preparation, request, allowed, definition, issued) = effect_values_policy_test_prepared(
    host, "original-operation",
  )
  let first = effect_values_policy_test_ok(
    effect_values_policy_test_accept(
      host, reference, preparation, request, allowed, definition, issued,
    ),
    "first.accept",
  )
  let row = effect_values_policy_test_ok(
    host.journal.retained(request),
    "first.row",
  ).unwrap()
  let original_body = effect_values_policy_test_ok(
    run_record_body(row),
    "first.body",
  )
  assert_true(row.effect_material_originals is Some(_))
  assert_true(row.publication_policy_originals is Some(_))
  assert_false(
    row.dispatch_reserved ||
    row.physical_start_claimed ||
    row.cancellation_requested,
  )
  assert_eq(first.run_admission.unwrap().revision, row.revision)
  // Lost response reconciliation uses the saved original before considering a
  // candidate filename. It neither constructs another policy nor changes time.
  let repeated = effect_values_policy_test_ok(
    effect_values_policy_test_accept(
      host,
      reference,
      preparation,
      request,
      allowed,
      definition,
      issued,
      file=Some("not-a-current-policy-candidate"),
    ),
    "repeat.saved",
  )
  assert_eq(repeated.revision, first.revision)
  assert_eq(
    effect_values_policy_test_ok(
      run_record_body(host.journal.retained(request).unwrap().unwrap()),
      "repeat.body",
    ),
    original_body,
  )
  let body = effect_values_policy_test_ok(
    effect_values_policy_test_lookup(host, reference, request),
    "read.original",
  )
  assert_eq(
    @publication.captured_effect_dependency_body_cid(body),
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
  )
  effect_values_policy_test_ok(host.close(), "close.before-restart")
  let reopened = effect_values_policy_test_host(name, existing=true)
  defer reopened.close() |> ignore
  let restored = effect_values_policy_test_ok(
    effect_values_policy_test_lookup(reopened, reference, request),
    "restart.read",
  )
  assert_eq(
    @publication.captured_effect_dependency_body_json(restored),
    @publication.captured_effect_dependency_body_json(body),
  )
  assert_eq(
    effect_values_policy_test_ok(
      run_record_body(reopened.journal.retained(request).unwrap().unwrap()),
      "restart.row",
    ),
    original_body,
  )
  effect_values_policy_test_ok(reopened.close(), "restart.close")
}

///|
test "Effect Values accepted missing policy stays missing without installation backfill" {
  let host = effect_values_policy_test_host("values-policy-missing")
  defer host.close() |> ignore
  let (reference, preparation, request, allowed, definition, issued) = effect_values_policy_test_prepared(
    host, "legacy-accepted",
  )
  effect_values_policy_test_ok(
    effect_values_policy_test_accept(
      host,
      reference,
      preparation,
      request,
      allowed,
      definition,
      issued,
      file=None,
    ),
    "legacy.accept",
  )
  |> ignore
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  let refused = effect_values_policy_test_accept(
    host, reference, preparation, request, allowed, definition, issued,
  )
  let read = effect_values_policy_test_lookup(host, reference, request)
  let after = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  effect_values_policy_test_ok(host.close(), "missing.close")
  assert_true(refused is Err(Journal(CustodyLost)))
  assert_true(
    read is Err(Journal(PublicationPolicy(@checked.MissingDependency))),
  )
  assert_eq(after, before)
}

///|
test "Effect Values policy refuses unselected files and invalid selected CID before first admission" {
  for wrong_cid in [false, true] {
    let host = effect_values_policy_test_host(
      if wrong_cid {
        "values-policy-wrong-cid"
      } else {
        "values-policy-unselected"
      },
      wrong_policy_cid=wrong_cid,
    )
    let (reference, preparation, request, allowed, definition, issued) = effect_values_policy_test_prepared(
      host, "refused-selection",
    )
    let result = effect_values_policy_test_accept(
      host,
      reference,
      preparation,
      request,
      allowed,
      definition,
      issued,
      file=Some(if wrong_cid { "selected.run" } else { "unselected.run" }),
    )
    let run = host.journal.retained(request).unwrap()
    let submission = host.journal
      .retained_submission(reference)
      .unwrap()
      .unwrap()
    effect_values_policy_test_ok(host.close(), "invalid.close")
    assert_true(result is Err(Journal(CustodyLost)))
    assert_true(run is None)
    assert_true(submission.run_admission is None)
  }
}

///|
test "Effect Values original read is independent of submit and observes closed current Host" {
  let account = @utf8.encode(
    (@utf8.decode(effect_values_policy_test_account) catch {
      _ => fail("account.utf8")
    }).replace(old="[\"read\",\"submit\"]", new="[\"submit\"]"),
  )
  let host = effect_values_policy_test_host(
    "values-policy-submit-only",
    account~,
  )
  defer host.close() |> ignore
  let (reference, preparation, request, allowed, definition, issued) = effect_values_policy_test_prepared(
    host, "submit-not-read",
  )
  effect_values_policy_test_ok(
    effect_values_policy_test_accept(
      host, reference, preparation, request, allowed, definition, issued,
    ),
    "submit.allowed",
  )
  |> ignore
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  let denied = effect_values_policy_test_lookup(host, reference, request)
  let after = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  effect_values_policy_test_ok(host.close(), "denied.close")
  let closed = effect_values_policy_test_lookup(host, reference, request)
  assert_true(denied is Err(Journal(AuthorizationDenied)))
  assert_true(closed is Err(Journal(AuthorizationDenied)))
  assert_eq(after, before)
}

///|
test "Effect Values original policy cannot join another retained request or foreign Host" {
  let host = effect_values_policy_test_host("values-policy-foreign-request")
  defer host.close() |> ignore
  let (reference, preparation, request, allowed, definition, issued) = effect_values_policy_test_prepared(
    host, "first",
  )
  effect_values_policy_test_ok(
    effect_values_policy_test_accept(
      host, reference, preparation, request, allowed, definition, issued,
    ),
    "foreign.first",
  )
  |> ignore
  let (
    second_ref,
    second_preparation,
    second_request,
    second_allowed,
    second_definition,
    second_issued,
  ) = effect_values_policy_test_prepared(host, "second")
  effect_values_policy_test_ok(
    effect_values_policy_test_accept(
      host, second_ref, second_preparation, second_request, second_allowed, second_definition,
      second_issued,
    ),
    "foreign.second",
  )
  |> ignore
  let mismatch = effect_values_policy_test_lookup(
    host, reference, second_request,
  )
  let other = effect_values_policy_test_host("values-policy-other-host")
  let foreign = effect_values_policy_test_lookup(other, reference, request)
  effect_values_policy_test_ok(other.close(), "foreign.other.close")
  effect_values_policy_test_ok(host.close(), "foreign.close")
  assert_true(mismatch is Err(ChangedIntent))
  assert_true(foreign is Err(_))
}

///|
test "Effect Values selected file replacement of identical bytes never becomes a new original" {
  let host = effect_values_policy_test_host("values-policy-replacement")
  defer host.close() |> ignore
  let (reference, preparation, request, allowed, definition, issued) = effect_values_policy_test_prepared(
    host, "replaced-selection",
  )
  let file = local_run_policy_selected(host, "selected.run").unwrap()
  let root = host.session.source_root
  root.reclaim_generation(file.name, file.generation).unwrap()
  let writer = root.create_writer("replacement.stage", 65536L).unwrap()
  writer.append(file.body).unwrap()
  writer.seal(file.name).unwrap() |> ignore
  let refused = effect_values_policy_test_accept(
    host, reference, preparation, request, allowed, definition, issued,
  )
  let retained = host.journal.retained(request).unwrap()
  effect_values_policy_test_ok(host.close(), "replacement.close")
  assert_true(refused is Err(Journal(AuthorizationDenied)))
  assert_true(retained is None)
}

///|
test "Effect Values original policy and packet roll back together at terminal current denial" {
  let host = effect_values_policy_test_host("values-policy-tx-deny")
  defer host.close() |> ignore
  let (reference, preparation, request, _, definition, issued) = effect_values_policy_test_prepared(
    host, "rollback-operation",
  )
  let material_wire = @host.client_effect_issued_normalization_materials_wire(
    issued,
  )
  let packet : NativeClientEffectMaterialOriginalPacket = {
    intent_cid: preparation.intent_cid,
    materials_cid: "sha256:" + @sha.hex(@utf8.encode(material_wire)),
    materials_wire: material_wire,
    request_scope_cid: @host.client_request_scope_cid(request),
    run_definition_cid: @publication.publication_contract_identity(definition),
    submission_reference: reference.wire,
  }
  let wire = effect_material_original_packet_wire(packet).unwrap()
  let (policy, _) = host
    .select_effect_values_policy_originals(
      reference, request, definition, "selected.run",
    )
    .unwrap()
  let calls : Ref[Int] = Ref(0)
  let refused = host.journal.accept_original_submitted_run(
    host.epoch,
    reference,
    preparation.intent_cid,
    request,
    definition,
    @host.client_request_authority_scope_cid(request),
    true,
    effect_material_originals=Some(wire),
    publication_policy_originals=Some(policy),
    current_fence=Some(() => {
      calls.val += 1
      calls.val < 4
    }),
  )
  let run = host.journal.retained(request).unwrap()
  let submission = host.journal.retained_submission(reference).unwrap().unwrap()
  let count = run_journal_custody(host.database, 8).unwrap().0
  effect_values_policy_test_ok(host.close(), "rollback.close")
  assert_eq(calls.val, 4)
  assert_true(refused is Err(AuthorizationDenied))
  assert_true(run is None)
  assert_true(submission.run_admission is None)
  assert_eq(count, 0)
}
