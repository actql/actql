///|
test "Native original Effect admission forwards the same epoch and acceptance operations" {
  let (host, reference, preparation, request, allowed, definition, issued) = effect_material_original_host_fixture(
    "effect-original-operation-route",
  )
  let calls : Array[String] = []
  let operations = journal_test_operation_access(host.database, calls)
  let accepted = host
    .accept_submitted_effect_material_with_policy(
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
      None,
      None,
      operations=Some(operations),
    )
    .unwrap()
  assert_true(accepted.run_admission is Some(_))
  assert_true(calls.contains("begin"))
  assert_true(calls.contains("commit"))
  assert_true(
    calls.any(value => value.has_prefix("read:client_submission_epoch:")),
  )
  assert_true(
    calls.contains(
      "insert:client_runs:" + @host.client_request_scope_cid(request),
    ),
  )
  let record = host.journal.retained(request).unwrap().unwrap()
  let packet = read_effect_material_original_packet(
    record.effect_material_originals.unwrap(),
  ).unwrap()
  assert_eq(packet.submission_reference, reference.wire)
  assert_eq(
    packet.materials_wire,
    @host.client_effect_issued_normalization_materials_wire(issued),
  )
  assert_false(record.physical_start_claimed)
  host.close().unwrap()
}

///|
test "Native original Effect admission preserves routed write failure without accepting a Run" {
  let (host, reference, preparation, request, allowed, definition, issued) = effect_material_original_host_fixture(
    "effect-original-operation-refusal",
  )
  let before = host.journal.retained_submission(reference).unwrap().unwrap()
  let calls : Array[String] = []
  let original = journal_test_operation_access(host.database, calls)
  let operations = {
    ..original,
    insert: (table, key, body) => {
      if table == "client_runs" {
        calls.push("original Run insert refused")
        Err(@sqlite.Busy)
      } else {
        (original.insert)(table, key, body)
      }
    },
  }
  assert_true(
    host.accept_submitted_effect_material_with_policy(
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
      None,
      None,
      operations=Some(operations),
    )
    is Err(Journal(Physical(@sqlite.Busy))),
  )
  assert_true(calls.contains("original Run insert refused"))
  assert_true(calls.contains("rollback"))
  assert_true(host.journal.retained(request).unwrap() is None)
  let after = host.journal.retained_submission(reference).unwrap().unwrap()
  assert_eq(after.revision, before.revision)
  assert_true(after.run_admission is None)
  host.close().unwrap()
}

///|
// Exact original setup remains preparing until the new Host entry atomically
// accepts its Run and packet. No Source, Provider or physical work is installed.
// These Native test definitions do not establish execution by compilation.
fn effect_material_original_host_fixture(
  name : String,
  document? : String = native_client_effect_fixture_document,
) -> (
  NativeLocalHostConnection,
  NativeClientSubmissionReference,
  NativeClientSubmittedPreparation,
  @host.ClientRequestIdentity,
  @host.ClientEffectAllowedRun,
  @publication.PublicationContract,
  @host.ClientEffectIssuedNormalizationMaterials,
) raise {
  let host = policy_host_fixture(name)
  let crypto = epoch_test_crypto()
  let scope = host.authority_scope_cid("operator", "cli", crypto).unwrap()
  let authority = host.epoch_authority().unwrap()
  let epoch = authority.issue_epoch(scope, true, 1000.0).unwrap()
  let reference = prepare_native_client_submission_reference(
    epoch, "original-submit",
  ).unwrap()
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" + document + ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = native_client_effect_fixture_preparation(intent)
  let (request, allowed, definition) = native_client_effect_fixture_run(
    preparation,
    reference,
    "original-effect-materials",
    scope~,
  )
  host.journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
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
test "Native Host commits original Effect packet and Submission Run together then reads exact bytes after reopen" {
  let name = "local-effect-original-reopen"
  let (host, reference, preparation, request, allowed, definition, issued) = effect_material_original_host_fixture(
    name,
  )
  let before = host.journal.retained_submission(reference).unwrap().unwrap()
  assert_true(before.run_admission is None)
  assert_true(host.journal.retained(request).unwrap() is None)
  let accepted = host
    .accept_submitted_effect_material_original(
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
    )
    .unwrap()
  let record = host.journal.retained(request).unwrap().unwrap()
  assert_true(record.effect_material_originals is Some(_))
  assert_eq(accepted.run_admission.unwrap().revision, record.revision)
  assert_false(record.dispatch_reserved)
  assert_false(record.physical_start_claimed)
  assert_false(record.cancellation_requested)
  let wire = @host.client_effect_issued_normalization_materials_wire(issued)
  let raw = run_record_body(record).unwrap()
  let revision = record.revision
  for _ in 0..<2 {
    assert_eq(
      host
      .accept_submitted_effect_material_original(
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
      .unwrap().revision,
      accepted.revision,
    )
    let original = host
      .lookup_submitted_effect_material_original(
        epoch_test_crypto(),
        "operator",
        "cli",
        reference,
        request,
        1003.0,
      )
      .unwrap()
    assert_eq(native_client_retained_effect_materials_wire(original), wire)
    assert_eq(
      native_client_retained_effect_materials_request(original),
      request,
    )
    assert_eq(
      @publication.publication_contract_identity(
        native_client_retained_effect_materials_run(original),
      ),
      @publication.publication_contract_identity(definition),
    )
    assert_eq(
      native_client_retained_effect_materials_cid(original),
      local_adoption_digest(epoch_test_crypto(), @utf8.encode(wire)).unwrap(),
    )
    assert_eq(
      run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
      raw,
    )
    assert_eq(run_journal_custody(host.database, 8).unwrap().0, 1)
  }
  let packet = read_effect_material_original_packet(
    record.effect_material_originals.unwrap(),
  ).unwrap()
  // A different packet must not replace accepted custody, even if its outer
  // Run/request/intent remain equal. Exercise the same private commit seam.
  assert_true(
    host.journal.accept_original_submitted_run(
      host.epoch,
      reference,
      preparation.intent_cid,
      request,
      definition,
      host.authority_scope_cid("operator", "cli", epoch_test_crypto()).unwrap(),
      true,
      effect_material_originals=Some(
        effect_material_original_packet_wire({
          ..packet,
          materials_wire: packet.materials_wire + " ",
        }).unwrap(),
      ),
    )
    is Err(ChangedEffectMaterialOriginal),
  )
  assert_eq(
    run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
    raw,
  )
  host.close().unwrap()
  let reopened = policy_host_fixture(name, existing=true)
  let restored_reference = admit_native_client_submission_reference(
    reference.wire,
  ).unwrap()
  let restored = reopened
    .lookup_submitted_effect_material_original(
      epoch_test_crypto(),
      "operator",
      "cli",
      restored_reference,
      request,
      1004.0,
    )
    .unwrap()
  assert_eq(native_client_retained_effect_materials_wire(restored), wire)
  let record = reopened.journal.retained(request).unwrap().unwrap()
  assert_eq(record.revision, revision)
  assert_eq(run_record_body(record).unwrap(), raw)
  assert_false(record.dispatch_reserved)
  assert_false(record.physical_start_claimed)
  reopened.close().unwrap()
}

///|
test "Native original packet commit loss never creates a partial Run packet or new submission" {
  for reply_lost in [false, true] {
    let name = "local-effect-original-commit-" + reply_lost.to_string()
    let (host, reference, preparation, request, allowed, definition, issued) = effect_material_original_host_fixture(
      name,
    )
    // Existing physical SQLite injection: the first commit is the epoch
    // watermark, the next is the original Run/packet/Submission transaction.
    submitted_test_fail_commit_after(host.database, 1, reply_lost)
    assert_true(
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
      )
      is Err(Journal(TransactionUnknown)),
    )
    assert_true(host.database.transaction_fenced())
    if !reply_lost {
      host.database.rollback().unwrap()
    }
    host.close().unwrap()
    let reopened = policy_host_fixture(name, existing=true)
    let original = reopened.journal
      .retained_submission(reference)
      .unwrap()
      .unwrap()
    assert_eq(original.run_admission is Some(_), reply_lost)
    if reply_lost {
      let packet = reopened
        .lookup_submitted_effect_material_original(
          epoch_test_crypto(),
          "operator",
          "cli",
          reference,
          request,
          1003.0,
        )
        .unwrap()
      assert_eq(
        native_client_retained_effect_materials_wire(packet),
        @host.client_effect_issued_normalization_materials_wire(issued),
      )
      let record = reopened.journal.retained(request).unwrap().unwrap()
      assert_false(record.dispatch_reserved)
      assert_false(record.physical_start_claimed)
      assert_eq(run_journal_custody(reopened.database, 8).unwrap().0, 1)
    } else {
      assert_true(reopened.journal.retained(request).unwrap() is None)
      assert_true(
        reopened.lookup_submitted_effect_material_original(
          epoch_test_crypto(),
          "operator",
          "cli",
          reference,
          request,
          1003.0,
        )
        is Err(MissingRunAdmission),
      )
      assert_eq(run_journal_custody(reopened.database, 8).unwrap().0, 0)
    }
    assert_eq(reopened.journal.submitted_intent_custody().unwrap().0, 1)
    reopened.close().unwrap()
  }
}

///|
test "Native original material admission refuses missing accepted custody even before physical start" {
  let (host, reference, preparation, request, allowed, definition, issued) = local_original_effect_material_fixture(
    "local-effect-original-no-backfill", true, true,
  )
  let before = run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap()
  assert_true(
    host.lookup_submitted_effect_material_original(
      epoch_test_crypto(),
      "operator",
      "cli",
      reference,
      request,
      1003.0,
    )
    is Err(Journal(MissingEffectMaterialOriginal)),
  )
  assert_true(
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
      1003.0,
    )
    is Err(Journal(MissingEffectMaterialOriginal)),
  )
  let record = host.journal.retained(request).unwrap().unwrap()
  assert_eq(run_record_body(record).unwrap(), before)
  assert_false(record.dispatch_reserved)
  assert_false(record.physical_start_claimed)
  assert_false(
    (@utf8.decode(before) catch { _ => fail("invalid original") }).contains(
      "effect_material_originals",
    ),
  )
  host.close().unwrap()
}

///|
test "Native packet admission refuses changed intent or physical preparation without accepting a Run" {
  let (host, reference, preparation, request, allowed, definition, issued) = effect_material_original_host_fixture(
    "local-effect-original-foreign",
  )
  let changed = { ..preparation, intent_cid: "sha256:" + "f".repeat(64), }
  assert_true(
    host.accept_submitted_effect_material_original(
      epoch_test_crypto(),
      "operator",
      "cli",
      reference,
      changed,
      request,
      allowed,
      definition,
      issued,
      1002.0,
    )
    is Err(Journal(ChangedIntent)),
  )
  let intent = host.journal.retained_submission(reference).unwrap().unwrap().intent
  let copied = native_client_effect_fixture_preparation(intent)
  assert_true(
    host.accept_submitted_effect_material_original(
      epoch_test_crypto(),
      "operator",
      "cli",
      reference,
      copied,
      request,
      allowed,
      definition,
      issued,
      1002.0,
    )
    is Err(ForeignPreparation),
  )
  assert_true(host.journal.retained(request).unwrap() is None)
  assert_true(
    host.journal.retained_submission(reference).unwrap().unwrap().run_admission
    is None,
  )
  assert_eq(run_journal_custody(host.database, 8).unwrap().0, 0)
  host.close().unwrap()
}

///|
test "Native original packet lookup refuses tampering foreign context and replaced adopted authority" {
  for mutation in ["wire", "cid", "intent", "request", "run", "reference"] {
    let name = "local-effect-original-tamper-" + mutation
    let (host, reference, preparation, request, allowed, definition, issued) = effect_material_original_host_fixture(
      name,
    )
    host
    .accept_submitted_effect_material_original(
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
    )
    .unwrap()
    |> ignore
    let before = host.journal.retained(request).unwrap().unwrap()
    let packet = read_effect_material_original_packet(
      before.effect_material_originals.unwrap(),
    ).unwrap()
    let changed = match mutation {
      "wire" => { ..packet, materials_wire: packet.materials_wire + " ", }
      "cid" => { ..packet, materials_cid: "sha256:" + "f".repeat(64), }
      "intent" => { ..packet, intent_cid: "sha256:" + "f".repeat(64), }
      "request" => { ..packet, request_scope_cid: "sha256:" + "f".repeat(64), }
      "run" => { ..packet, run_definition_cid: "sha256:" + "f".repeat(64), }
      _ => { ..packet, submission_reference: "{}", }
    }
    host.journal
    .transaction(() => {
      host.journal
      .save({
        ..before,
        effect_material_originals: Some(
          effect_material_original_packet_wire(changed).unwrap(),
        ),
      })
      .map(_ => ())
    })
    .unwrap()
    let corrupted = run_record_body(
      host.journal.retained(request).unwrap().unwrap(),
    ).unwrap()
    assert_true(
      host.lookup_submitted_effect_material_original(
        epoch_test_crypto(),
        "operator",
        "cli",
        reference,
        request,
        1003.0,
      )
      is Err(Journal(CustodyLost)),
    )
    assert_eq(
      run_record_body(host.journal.retained(request).unwrap().unwrap()).unwrap(),
      corrupted,
    )
    assert_false(before.dispatch_reserved)
    assert_false(before.physical_start_claimed)
    host.close().unwrap()
  }
  let name = "local-effect-original-current"
  let (host, reference, preparation, request, allowed, definition, issued) = effect_material_original_host_fixture(
    name,
  )
  host
  .accept_submitted_effect_material_original(
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
  )
  .unwrap()
  |> ignore
  let parent = host.session.source_root
  let account = name + ".account.json"
  parent
  .reclaim_generation(
    account,
    parent.inspect_generation(account).unwrap().unwrap(),
  )
  .unwrap()
  let writer = parent.create_writer(name + ".replaced", 4096L).unwrap()
  writer.append(policy_account_original).unwrap()
  writer.seal(account).unwrap() |> ignore
  assert_true(
    host.lookup_submitted_effect_material_original(
      epoch_test_crypto(),
      "operator",
      "cli",
      reference,
      request,
      1003.0,
    )
    is Err(Journal(AuthorizationDenied)),
  )
  host.close().unwrap()
}

///|
test "Native packet record budget exhaustion rolls back Run admission without increasing the existing cap" {
  let document = native_client_effect_fixture_document.replace(
    old="e\\u0301\\r\\n",
    new="\\\\".repeat(12000),
  )
  let (host, reference, preparation, request, allowed, definition, issued) = effect_material_original_host_fixture(
    "local-effect-original-record-cap",
    document~,
  )
  let before = host.journal.retained_submission(reference).unwrap().unwrap()
  assert_true(
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
    )
    is Err(Journal(CapacityExceeded)),
  )
  assert_eq(
    host.journal.retained_submission(reference).unwrap().unwrap().revision,
    before.revision,
  )
  assert_true(
    host.journal.retained_submission(reference).unwrap().unwrap().run_admission
    is None,
  )
  assert_true(host.journal.retained(request).unwrap() is None)
  assert_eq(run_journal_custody(host.database, 8).unwrap().0, 0)
  host.close().unwrap()
}

///|
test "Native first original packet acceptance rechecks current authority before both durable writes" {
  for deny_at in 1..<4 {
    let name = "local-effect-original-fence-" + deny_at.to_string()
    let (host, reference, preparation, request, allowed, definition, issued) = effect_material_original_host_fixture(
      name,
    )
    let authority = native_local_policy_authority_for(
      host,
      epoch_test_crypto(),
      "operator",
      "cli",
      request,
      SubmitOriginals,
    ).unwrap()
    let materials = @host.bind_prepared_client_effect_original_materials(
      allowed,
      definition,
      issued,
      request=Some(request),
    ).unwrap()
    let wire = effect_material_original_packet_wire({
      intent_cid: preparation.intent_cid,
      materials_cid: @host.client_effect_normalization_materials_cid(materials).unwrap(),
      materials_wire: @host.client_effect_issued_normalization_materials_wire(
        issued,
      ),
      request_scope_cid: @host.client_request_scope_cid(request),
      run_definition_cid: @publication.publication_contract_identity(definition),
      submission_reference: reference.wire,
    }).unwrap()
    let count = Ref(0)
    let current = () => {
      count.val += 1
      if count.val == deny_at {
        let parent = host.session.source_root
        let account = name + ".account.json"
        parent
        .reclaim_generation(
          account,
          parent.inspect_generation(account).unwrap().unwrap(),
        )
        .unwrap()
      }
      authority.current_for(host.journal, request)
    }
    // The public Host method has no caller fence. This private injection uses
    // the actual installed Account file and same existing transaction helper.
    assert_true(
      host.journal.accept_original_submitted_run(
        host.epoch,
        reference,
        preparation.intent_cid,
        request,
        definition,
        authority.scope,
        true,
        effect_material_originals=Some(wire),
        current_fence=Some(current),
      )
      is Err(AuthorizationDenied),
    )
    assert_eq(count.val, deny_at)
    assert_true(host.journal.retained(request).unwrap() is None)
    assert_true(
      host.journal.retained_submission(reference).unwrap().unwrap().run_admission
      is None,
    )
    assert_eq(run_journal_custody(host.database, 8).unwrap().0, 0)
    host.close().unwrap()
  }
}
