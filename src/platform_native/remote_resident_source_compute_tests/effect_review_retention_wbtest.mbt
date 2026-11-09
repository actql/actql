///|
/// Exercise the production retention connection with original real holders,
/// physical Provider evidence and real SQLite/crypto. Store reopening retains
/// the live Ledger and does not establish Host restart or approval acceptance.
fn retained_effect_review_retention_store(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  result : @resident.ResidentEffectResultCapture,
  invocation : @publication.PublicationContract,
  preview : @strategy.CapturedEffectPreviewInputs,
  captured : @publication.PublicationContract,
  authority : String,
  wire : String,
  authoring_cid : String,
  review_work? : @effect_provider.NativeResidentEffectReview? = None,
  approved_row? : Bool = false,
  original_journal_path? : String? = None,
  original_work? : (
    @client.NativeClientEffectSourceWork,
    @client.NativeClientRunJournal,
  )? = None,
  initial_reviewer? : (
    PairedInitialReviewerFixture,
    @client.NativeClientSubmissionReference,
  )? = None,
  original_context? : (
    @resident.ResidentEffectReviewInputContext,
    @dispatch_journal.Journal,
  )? = None,
) -> Unit raise {
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT").unwrap()
  let child = "effect-review-retention-" + @env.now().to_string()
  @filesystem.open_root(root).unwrap().create_directory(child).unwrap()
  |> ignore
  let path = root + "/" + child
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 262144,
    max_nodes: 10000,
    max_depth: 64,
  }
  let initial_host = initial_reviewer is Some((fixture, _)) &&
    fixture.attest_host
  let now = @env.now().reinterpret_as_int64()
  let created_at = if initial_host {
    @values.epoch_milliseconds_timestamp(now).unwrap()
  } else {
    "2026-10-10T00:00:00.000Z"
  }
  let expires_at = if initial_host {
    // Same one-day interval as the original Oct10 -> Oct11 fixture. Only
    // this new actual-time Host case moves the dates, not its finite window.
    @values.epoch_milliseconds_timestamp(now + 86400000L).unwrap()
  } else {
    "2026-10-11T00:00:00.000Z"
  }
  // Test charges are explicit; they are not a production layout declaration.
  let computation_capacity : @resident.ResidentEffectComputationCapacity = {
    contract_bytes: 1048576L,
    control_bytes: 4096L,
    workspace_bytes: 65536L,
    max_utf16_units: 1048576,
    layout: original_computation_fixture_layout(),
  }
  let prepare = (material, secret, bounds) => {
    consumer.prepare_effect_review_retention(
      material, inputs, result, invocation, preview, captured, wire, authoring_cid,
      authority, crypto, secret, "native-original-review-retention", created_at,
      expires_at, bounds,
    )
  }
  println("native-original-review: preparing review retention")
  let baseline = consumer.usage().reserved_retention_bytes
  assert_true(
    prepare({ ..materials, request: None, }, key, limits) is Err(Unavailable),
  )
  assert_true(
    prepare(materials, Bytes::make(31, 0), limits) is Err(InvalidConfiguration),
  )
  assert_true(
    prepare(materials, key, { ..limits, max_depth: 0, })
    is Err(InvalidConfiguration),
  )
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  let retention = match review_work {
    Some(work) => {
      let retained = work
        .prepare_retention(
          crypto, key, "native-original-review-retention", created_at, expires_at,
          limits,
        )
        .unwrap()
      assert_true(
        physical_equal(
          retained,
          work
          .prepare_retention(
            crypto, key, "native-original-review-retention", created_at, expires_at,
            limits,
          )
          .unwrap(),
        ),
      )
      assert_true(
        work.prepare_retention(
          crypto, key, "native-original-review-retention", created_at, "2026-10-12T00:00:00.000Z",
          limits,
        )
        is Err(Unavailable),
      )
      retained
    }
    None => prepare(materials, key, limits).unwrap()
  }
  assert_true(retention.report() is Err(Unavailable))
  assert_true(retention.original_approval_scope() is Err(Unavailable))
  let request = materials.request.unwrap()
  let confirm = () => {
    retention.confirm_original_checkpoint(
      consumer,
      request,
      materials.run_definition,
    )
  }
  assert_true(confirm() is Err(Unavailable))
  assert_true(
    retention.original_review_projection(
      consumer,
      request,
      materials.run_definition,
      () => true,
      65536,
    )
    is Err(Unavailable),
  )
  assert_true(
    retention.original_completion_evidence(
      consumer,
      request,
      materials.run_definition,
      () => true,
      65536,
    )
    is Err(Unavailable),
  )
  let binding : @checkpoint.ResumeBinding = {
    // Use the same original Run admission, including a genuinely adopted
    // Host's context. A legacy literal is not that Host's authority original.
    authorization_context_cid: @publication.run_publication_execution_context(
      @host.client_effect_allowed_run_admission(materials.allowed),
    ),
    environment_binding_cid: retained_compute_cid("b"),
  }
  if original_work is Some((work, journal)) {
    guard journal.lookup(request, true) is Ok(@client.Retained(before)) else {
      fail("original Local review Run missing before persistence")
    }
    assert_true(
      work.wait_review_checkpoint(
        retention,
        @client.native_client_run_record_revision(before),
        binding,
        [],
      )
      is Err(@client.Retention(@resident.Unavailable)),
    )
    guard journal.lookup(request, true) is Ok(@client.Retained(after)) else {
      fail("original Local review Run changed before persistence")
    }
    assert_eq(
      @client.native_client_run_record_revision(after),
      @client.native_client_run_record_revision(before),
    )
    assert_true(@client.native_client_run_checkpoint_state(after) is None)
  }
  assert_true(
    retention.review_projection(() => true, 65536) is Err(Unavailable),
  )
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  let open = () => {
    @store.open_store(sqlite, path, authority, 536870912L, 8L, 262144L).unwrap()
  }
  let mut store = open()
  // Lose each acknowledgement after its real commit. The same retention
  // object resumes all four boundaries without another Provider observation.
  for
    step in [
      "effect-capture-persisted", "effect-preview-persisted", "effect-continuation-persisted",
      "effect-checkpoint-persisted",
    ] {
    let lost = Ref(false)
    store.observe_allocation(actual => {
      if actual == step && !lost.val {
        lost.val = true
        store.close().unwrap() |> ignore
      }
    })
    println("native-original-review: persisting " + step)
    let failed = if original_work is Some(_) {
      retention
      .persist_original_checkpoint(
        store,
        computation_capacity=Some(computation_capacity),
      )
      .map(_ => ())
    } else {
      retention
      .persist(store, computation_capacity=Some(computation_capacity))
      .map(_ => ())
    }
    assert_true(
      lost.val,
      msg=match failed {
        Err(@resident.Capture(@resident.Binding(issue))) =>
          @debug.to_string(issue)
        Err(@resident.Capture(@resident.Capacity(issue))) =>
          @debug.to_string(issue)
        Err(@resident.Capture(@resident.ComputationCapacityMissing)) =>
          "Original computation capacity is missing"
        Err(@resident.Capture(@resident.Unavailable)) => "Capture unavailable"
        Err(@resident.Capture(@resident.Store(_))) => "Capture Store rejected"
        Err(@resident.Preview(_)) =>
          "Preview rejected before commit observation"
        Err(@resident.Preparation(@resident.Unavailable)) =>
          "Checkpoint input unavailable"
        Err(@resident.Preparation(@resident.ForeignCapture)) =>
          "Foreign Checkpoint capture"
        Err(@resident.Preparation(@resident.InvalidLimits)) =>
          "Invalid Checkpoint limits"
        Err(@resident.Preparation(@resident.RunLifetimeUnavailable)) =>
          "Original Run lifetime unavailable"
        Err(@resident.Preparation(@resident.Request(issue))) =>
          @debug.to_string(issue)
        Err(@resident.Preparation(@resident.Keys(issue))) =>
          @debug.to_string(issue)
        Err(@resident.Preparation(@resident.Checkpoint(issue))) =>
          @debug.to_string(issue)
        Err(@resident.Preparation(@resident.RunBinding(@host.Run(_)))) =>
          "Checkpoint checked Run mismatch"
        Err(
          @resident.Preparation(@resident.RunBinding(@host.Checkpoint(issue)))
        ) => @debug.to_string(issue)
        Err(@resident.Preparation(@resident.RunBinding(@host.ForeignSubject))) =>
          "Checkpoint subject mismatch"
        Err(
          @resident.Preparation(@resident.RunBinding(@host.UnsupportedReview))
        ) => "Unsupported Checkpoint review"
        Err(@resident.Preparation(@resident.RunBinding(@host.OriginalLifetime))) =>
          "Checkpoint exceeds original lifetime"
        Err(@resident.Preparation(@resident.Encoding)) =>
          "Checkpoint encoding failed"
        Err(@resident.Preparation(@resident.Capture(_))) =>
          "Checkpoint capture readback failed"
        Err(@resident.Preparation(@resident.Preview(_))) =>
          "Checkpoint Preview readback failed"
        Err(@resident.Checkpoint(@resident.Store(@store.InvalidConfiguration))) =>
          "Checkpoint Store configuration"
        Err(@resident.Checkpoint(@resident.Store(@store.StateCollision))) =>
          "Checkpoint Store collision"
        Err(@resident.Checkpoint(@resident.Store(@store.DigestMismatch))) =>
          "Checkpoint continuation digest mismatch"
        Err(@resident.Checkpoint(@resident.Store(@store.Database(_)))) =>
          "Checkpoint database rejected"
        Err(
          @resident.Checkpoint(@resident.Store(@store.PrivateEvidence(issue)))
        ) => @debug.to_string(issue)
        Err(@resident.Checkpoint(@resident.Capacity(issue))) =>
          @debug.to_string(issue)
        Err(@resident.Checkpoint(@resident.Unavailable)) =>
          "Checkpoint inputs unavailable"
        Err(@resident.Checkpoint(_)) => "Checkpoint custody rejected"
        Err(@resident.Unavailable) => "Review inputs unavailable"
        Err(@resident.InvalidConfiguration) => "Invalid review configuration"
        Err(@resident.EvidenceDenied) => "Review Evidence denied"
        Err(@resident.ProjectionTooLarge) => "Review Evidence exceeds its bound"
        Ok(_) => "Expected durable commit observation was not emitted"
      },
    )
    match step {
      "effect-capture-persisted" =>
        assert_true(failed is Err(Capture(Store(Closed))))
      "effect-preview-persisted" =>
        assert_true(failed is Err(Preview(Store(Closed))))
      _ => assert_true(failed is Err(Checkpoint(Store(Closed))))
    }
    let pending = consumer.usage().reserved_retention_bytes
    assert_true(pending > baseline)
    assert_true(retention.report() is Err(_))
    assert_true(confirm() is Err(_))
    assert_true(retention.review_projection(() => true, 65536) is Err(_))
    store = open()
    retention.restore_store(store).unwrap()
    assert_eq(consumer.usage().reserved_retention_bytes, pending)
  }
  println("native-original-review: persistence fault retries confirmed")
  let report = if original_work is Some(_) {
    retention
    .persist_original_checkpoint(
      store,
      computation_capacity=Some(computation_capacity),
    )
    .unwrap()
    |> ignore
    assert_true(
      retention.report() is Err(@resident.Checkpoint(@resident.Unavailable)),
    )
    None
  } else {
    Some(
      retention
      .persist(store, computation_capacity=Some(computation_capacity))
      .unwrap(),
    )
  }
  let persisted = confirm().unwrap()
  let approval_scope = retention.original_approval_scope().unwrap()
  assert_eq(
    approval_scope.current_for(
      request,
      @publication.publication_contract_identity(materials.run_definition),
      persisted.artifact.checkpoint_cid,
    ),
    Some(@host.client_request_authority_scope_cid(request)),
  )
  assert_eq(
    approval_scope.current_for(
      request,
      @publication.publication_contract_identity(materials.run_definition),
      "sha256:" + "f".repeat(64),
    ),
    None,
  )
  if report is Some(remote_report) {
    assert_eq(
      persisted.artifact.checkpoint_cid,
      @remote.remote_effect_checkpoint_report_checkpoint(remote_report).checkpoint_cid,
    )
  }
  let foreign_run = @host.issue_client_effect_run_definition(
    materials.allowed,
    "local-review-fixture",
    "foreign-original-review",
    "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    retention.confirm_original_checkpoint(consumer, request, foreign_run)
    is Err(Unavailable),
  )
  let foreign_request = @host.prepare_client_effect_request_identity(
    materials.prepared,
    @host.client_request_authority_scope_cid(request),
    "foreign-original-review",
    @host.client_request_input_cid(request),
  ).unwrap()
  assert_eq(
    approval_scope.current_for(
      foreign_request,
      @publication.publication_contract_identity(materials.run_definition),
      persisted.artifact.checkpoint_cid,
    ),
    None,
  )
  assert_eq(
    approval_scope.current_for(
      request,
      @publication.publication_contract_identity(foreign_run),
      persisted.artifact.checkpoint_cid,
    ),
    None,
  )
  assert_true(
    retention.confirm_original_checkpoint(
      consumer,
      foreign_request,
      materials.run_definition,
    )
    is Err(Unavailable),
  )
  assert_true(
    retention.original_review_projection(
      consumer,
      foreign_request,
      materials.run_definition,
      () => true,
      65536,
    )
    is Err(Unavailable),
  )
  assert_true(
    retention.original_review_projection(
      consumer,
      request,
      foreign_run,
      () => true,
      65536,
    )
    is Err(Unavailable),
  )
  assert_true(
    retention.original_completion_evidence(
      consumer,
      foreign_request,
      materials.run_definition,
      () => true,
      65536,
    )
    is Err(Unavailable),
  )
  assert_true(
    retention.original_completion_evidence(
      consumer,
      request,
      foreign_run,
      () => true,
      65536,
    )
    is Err(Unavailable),
  )
  assert_true(
    retention.original_completion_evidence(
      consumer,
      request,
      materials.run_definition,
      () => false,
      65536,
    )
    is Err(EvidenceDenied),
  )
  assert_true(
    retention.original_completion_evidence(
      consumer,
      request,
      materials.run_definition,
      () => true,
      1,
    )
    is Err(ProjectionTooLarge),
  )
  let completion_reads = Ref(0)
  assert_true(
    retention.original_completion_evidence(
      consumer,
      request,
      materials.run_definition,
      () => {
        completion_reads.val += 1
        completion_reads.val < 2
      },
      65536,
    )
    is Err(EvidenceDenied),
  )
  assert_eq(completion_reads.val, 2)
  let completion_before = consumer.usage()
  let completion = retention
    .original_completion_evidence(
      consumer,
      request,
      materials.run_definition,
      () => true,
      65536,
    )
    .unwrap()
  assert_eq(completion.checkpoint_cid, persisted.artifact.checkpoint_cid)
  assert_eq(
    @publication.publication_contract_identity(completion.run_definition),
    @publication.publication_contract_identity(materials.run_definition),
  )
  assert_eq(
    @publication.publication_contract_identity(completion.invocation),
    @publication.publication_contract_identity(invocation),
  )
  assert_eq(
    @publication.publication_contract_identity(completion.computation_receipt),
    @publication.publication_contract_identity(result.receipt),
  )
  assert_eq(
    @publication.publication_contract_identity(completion.result_manifest),
    @publication.publication_contract_identity(result.manifest),
  )
  assert_eq(
    @publication.effect_preview_run_identity(completion.preview),
    @publication.publication_contract_identity(materials.run_definition),
  )
  assert_eq(
    consumer.usage().reserved_retention_bytes,
    completion_before.reserved_retention_bytes,
  )
  if original_work is Some((work, journal)) {
    guard journal.lookup(request, true) is Ok(@client.Retained(before)) else {
      fail("original Local review Run missing")
    }
    let revision = @client.native_client_run_record_revision(before)
    assert_true(
      work.wait_review_checkpoint(retention, revision + 1L, binding, [])
      is Err(@client.Journal(@client.Checkpoint(@client.StaleRevision))),
    )
    assert_true(
      work.wait_review_checkpoint(retention, revision, binding, [
        "foreign-effect",
      ])
      is Err(@client.Journal(@client.Checkpoint(@client.InvalidMaterial))),
    )
    if binding.authorization_context_cid != retained_compute_cid("a") {
      assert_true(
        work.wait_review_checkpoint(
          retention,
          revision,
          { ..binding, authorization_context_cid: retained_compute_cid("a"), },
          [],
        )
        is Err(@client.Journal(@client.Checkpoint(@client.InvalidMaterial))),
      )
      guard journal.lookup(request, true) is Ok(@client.Retained(unchanged)) else {
        fail("mismatched waiting binding lost original Run custody")
      }
      assert_eq(@client.native_client_run_record_revision(unchanged), revision)
    }
    let waiting = match
      work.wait_review_checkpoint(retention, revision, binding, []) {
      Ok(value) => value
      Err(@client.Original(_)) =>
        fail("original Review waiting refused by Work current")
      Err(@client.Retention(_)) =>
        fail("original Review waiting refused by retained Checkpoint")
      Err(@client.Journal(@client.Checkpoint(issue))) => {
        let reason = match issue {
          @client.InvalidMaterial => "InvalidMaterial"
          @client.StaleRevision => "StaleRevision"
          @client.ConflictingResolution => "ConflictingResolution"
          @client.Expired => "Expired"
          @client.NeedsOriginalContinuation => "NeedsOriginalContinuation"
          @client.State(issue) => "State: " + @debug.to_string(issue)
          @client.Signature(_) => "Signature"
          @client.Resume(_) => "Resume"
          @client.Ledger(_) => "Ledger"
          @client.EffectBinding(@host.Checkpoint(issue)) =>
            "EffectCheckpoint: " + @debug.to_string(issue)
          @client.EffectBinding(_) => "EffectBinding"
        }
        fail("original Review waiting Checkpoint refused: " + reason)
      }
      Err(@client.Journal(@client.CapacityExceeded)) =>
        fail("original Review waiting journal capacity exceeded")
      Err(@client.Journal(@client.AuthorizationDenied)) =>
        fail("original Review waiting journal authorization denied")
      Err(@client.Journal(@client.CustodyLost)) =>
        fail("original Review waiting journal custody lost")
      Err(@client.Journal(@client.Fenced)) =>
        fail("original Review waiting journal fenced")
      Err(@client.Journal(@client.TransactionUnknown)) =>
        fail("original Review waiting transaction unknown")
      Err(@client.Journal(@client.Physical(_))) =>
        fail("original Review waiting journal physical failure")
      Err(@client.Journal(_)) => fail("original Review waiting journal refused")
    }
    assert_eq(@client.native_client_run_record_revision(waiting), revision + 1L)
    let state = @client.native_client_run_checkpoint_state(waiting).unwrap()
    assert_eq(state.run_id, "original-local-effect-source-run")
    assert_eq(state.status, @publication.WaitingCheckpoint)
    assert_true(
      work.execute_task(1) is Err(@client.NeedsOriginalReconciliation),
    )
    assert_true(
      work.wait_review_checkpoint(retention, revision + 1L, binding, [])
      is Err(
        @client.Journal(@client.Checkpoint(@client.NeedsOriginalContinuation))
      ),
    )
    let (original_checkpoint, original_wire) = work
      .review_checkpoint(retention, () => true, 65536)
      .unwrap()
    assert_eq(
      original_checkpoint.checkpoint_cid,
      persisted.artifact.checkpoint_cid,
    )
    assert_eq(original_wire, wire)
    assert_true(
      work.review_checkpoint(retention, () => false, 65536)
      is Err(@client.Retention(@resident.EvidenceDenied)),
    )
    guard journal.lookup(request, true) is Ok(@client.Retained(after_read)) else {
      fail("original Local review Run lost after Evidence read")
    }
    assert_eq(
      @client.native_client_run_record_revision(after_read),
      revision + 1L,
    )
    if initial_reviewer is Some((value, reference)) {
      paired_initial_reviewer_signing(
        value,
        reference,
        request,
        approval_scope,
        persisted.artifact,
      )
    }
    // Establish the actual signed answer before the independent custody tests.
    // The new Approved-signature component leaves the Run Resuming without a
    // dispatch claim or business-result assertion; older cases retain rejection.
    if initial_host {
      assert_true(initial_reviewer.unwrap().0.host_applied)
    } else {
      native_local_effect_reject_review(journal, request, persisted.artifact)
    }
    // Historical read authority does not require another execution grant and
    // cannot undo rejection or acquire another Provider-send capability.
    let (rejected_checkpoint, rejected_wire) = work
      .review_checkpoint(retention, () => true, 65536)
      .unwrap()
    assert_eq(
      rejected_checkpoint.checkpoint_cid,
      original_checkpoint.checkpoint_cid,
    )
    assert_eq(rejected_wire, original_wire)
    assert_true(
      work.execute_task(1) is Err(@client.NeedsOriginalReconciliation),
    )
  }
  let project = (authorize, bound) => {
    if report is Some(_) {
      retention
      .review_projection(authorize, bound)
      .map(pair => {
        (@remote.remote_effect_checkpoint_report_checkpoint(pair.0), pair.1)
      })
    } else {
      retention
      .original_review_projection(
        consumer,
        request,
        materials.run_definition,
        authorize,
        bound,
      )
      .map(pair => (pair.0.artifact, pair.1))
    }
  }
  let before_projection = consumer.usage().reserved_retention_bytes
  assert_true(project(() => false, 65536) is Err(EvidenceDenied))
  assert_true(project(() => true, 1) is Err(ProjectionTooLarge))
  let evidence_reads = Ref(0)
  assert_true(
    project(
      () => {
        evidence_reads.val += 1
        evidence_reads.val < 2
      },
      65536,
    )
    is Err(EvidenceDenied),
  )
  assert_eq(evidence_reads.val, 2)
  // Both earlier checks allow this read. Current authority is unavailable
  // only after the final paired Store confirmation, before plaintext returns.
  let final_reads = Ref(0)
  assert_true(
    project(
      () => {
        final_reads.val += 1
        final_reads.val < 3
      },
      65536,
    )
    is Err(EvidenceDenied),
  )
  assert_eq(final_reads.val, 3)
  assert_eq(consumer.usage().reserved_retention_bytes, before_projection)
  if report is Some(report) {
    assert_eq(
      @remote.remote_effect_checkpoint_report_json(retention.report().unwrap()),
      @remote.remote_effect_checkpoint_report_json(report),
    )
  }
  let closing_reads = Ref(0)
  assert_true(
    project(
      () => {
        closing_reads.val += 1
        if closing_reads.val == 2 {
          store.close().unwrap() |> ignore
        }
        true
      },
      65536,
    )
    is Err(_),
  )
  assert_eq(closing_reads.val, 2)
  assert_eq(consumer.usage().reserved_retention_bytes, before_projection)
  assert_true(
    retention.original_completion_evidence(
      consumer,
      request,
      materials.run_definition,
      () => true,
      65536,
    )
    is Err(_),
  )
  store = open()
  retention.restore_store(store).unwrap()
  let (projection_checkpoint, projection_wire) = project(() => true, 65536).unwrap()
  assert_eq(
    retention
    .original_completion_evidence(
      consumer,
      request,
      materials.run_definition,
      () => true,
      65536,
    )
    .unwrap().checkpoint_cid,
    projection_checkpoint.checkpoint_cid,
  )
  assert_eq(
    projection_checkpoint.checkpoint_cid,
    persisted.artifact.checkpoint_cid,
  )
  assert_eq(projection_wire, wire)
  assert_eq(
    projection_checkpoint.checkpoint.review_projection_cid,
    "sha256:" + @sha.hex(@utf8.encode(projection_wire)),
  )
  assert_eq(consumer.usage().reserved_retention_bytes, before_projection)
  if report is Some(report) {
    let (projection_report, remote_wire) = retention
      .review_projection(() => true, 65536)
      .unwrap()
    assert_eq(
      @remote.remote_effect_checkpoint_report_json(projection_report),
      @remote.remote_effect_checkpoint_report_json(report),
    )
    assert_eq(remote_wire, projection_wire)
  }
  let resolution_fixture = if review_work is Some(work) {
    let (original_report, original_wire) = work
      .review_projection(() => true, 65536)
      .unwrap()
    assert_eq(original_wire, projection_wire)
    assert_eq(
      @remote.remote_effect_checkpoint_report_identity(original_report),
      @remote.remote_effect_checkpoint_report_identity(report.unwrap()),
    )
    println("native-original-review: retaining journal report")
    let queued = work
      .persist_and_retain_report(
        store,
        crypto,
        key,
        "native-original-review-retention",
        "2026-10-10T00:00:00.000Z",
        "2026-10-11T00:00:00.000Z",
        limits,
        computation_capacity=Some(computation_capacity),
      )
      .unwrap()
    assert_eq(
      @remote.remote_effect_checkpoint_report_json(queued),
      @remote.remote_effect_checkpoint_report_json(report.unwrap()),
    )
    if original_context is Some((context, journal)) {
      let before_original = store.capacity_usage().unwrap().reserved_bytes
      let read_original = authorize => {
        context.read_original_review_projection(
          journal, store, authority, crypto, key, limits, authorize,
        )
      }
      assert_true(read_original(() => false) is Err(EvidenceDenied))
      let original_reads = Ref(0)
      assert_true(
        read_original(() => {
          original_reads.val += 1
          original_reads.val < 2
        })
        is Err(EvidenceDenied),
      )
      assert_eq(original_reads.val, 2)
      let final_reads = Ref(0)
      assert_true(
        read_original(() => {
          final_reads.val += 1
          final_reads.val < 3
        })
        is Err(EvidenceDenied),
      )
      assert_eq(final_reads.val, 3)
      assert_eq(store.capacity_usage().unwrap().reserved_bytes, before_original)
      assert_eq(consumer.usage().reserved_retention_bytes, before_projection)
      let restored = read_original(() => true).unwrap()
      assert_eq(restored.1, projection_wire)
      assert_eq(
        @remote.remote_effect_checkpoint_report_json(restored.0),
        @remote.remote_effect_checkpoint_report_json(queued),
      )
      assert_true(
        context.read_original_review_projection(
          journal,
          store,
          retained_compute_cid("f"),
          crypto,
          key,
          limits,
          () => true,
        )
        is Err(Store(StateCollision)),
      )
      assert_eq(store.capacity_usage().unwrap().reserved_bytes, before_original)
      assert_eq(consumer.usage().reserved_retention_bytes, before_projection)
      // A current authorization read can retire/close custody. Recheck after
      // that boundary instead of returning previously read private bytes.
      let close_reads = Ref(0)
      assert_true(
        read_original(() => {
          close_reads.val += 1
          if close_reads.val == 2 {
            store.close().unwrap() |> ignore
          }
          true
        })
        is Err(Store(Closed)),
      )
      assert_eq(close_reads.val, 2)
      store = open()
      retention.restore_store(store).unwrap()
      assert_eq(read_original(() => true).unwrap().1, projection_wire)
      assert_eq(store.capacity_usage().unwrap().reserved_bytes, before_original)
    }
    let (upload_context, upload_journal) = original_context.unwrap()
    retained_holder_upload_original_review(
      work,
      original_journal_path.unwrap(),
      store,
      {
        crypto,
        key,
        checkpoint_id: "native-original-review-retention",
        created_at,
        expires_at,
        limits,
        report_url: @env.get_env_var(
          "ACTQL_TEST_EFFECT_REVIEW_REPORT_FIXTURE_URL",
        ).unwrap(),
        artifact_url: @env.get_env_var(
          "ACTQL_TEST_EFFECT_REVIEW_UPLOAD_FIXTURE_URL",
        ).unwrap(),
        access: (_, _) => {
          abort("confirmed review repeated a Provider observation")
        },
      },
      upload_context,
      upload_journal,
      authority,
    )
    Some(retained_holder_admit_resolution(work, report.unwrap()))
  } else {
    None
  }
  if approved_row ||
    @env.get_env_var("ACTQL_TEST_NATIVE_EFFECT_APPROVED_ROW") == Some("1") {
    retained_holder_write_row(
      review_work.unwrap(),
      report.unwrap(),
      resolution_fixture.unwrap(),
      invocation,
      original_journal_path.unwrap(),
      consumer,
      result,
    )
  }
  let report_wire = report.map(@remote.remote_effect_checkpoint_report_json)
  let checkpoint = persisted.artifact
  let holding = checkpoint.checkpoint_cid
  let inspection = sqlite
    .open_database(path + "/.actql-publication.sqlite3", 262144L)
    .unwrap()
  let continuation = inspection
    .read("effect_continuation_custody", holding)
    .unwrap()
  let checkpoint_record = inspection
    .read("effect_checkpoint_custody", holding)
    .unwrap()
  let continuation_bytes = crypto
    .open_private_evidence(
      key,
      "continuation_record",
      checkpoint.checkpoint.continuation_state_cid,
      continuation.body,
    )
    .unwrap()
  assert_eq(
    checkpoint.checkpoint.continuation_state_cid,
    "sha256:" + @sha.hex(continuation_bytes),
  )
  let doubled = @checkpoint.seal_checkpoint(
    {
      ..checkpoint.checkpoint,
      continuation_state_cid: "sha256:" +
      @sha.hex(@sha.digest(continuation_bytes)),
    },
    limits,
  ).unwrap()
  let before_rejected_continuation = store.capacity_usage().unwrap().reserved_bytes
  assert_true(
    store.prepare_effect_checkpoint_custody(
      doubled,
      @utf8.decode(continuation_bytes),
      authority,
      crypto,
      key,
    )
    is Err(DigestMismatch),
  )
  assert_eq(
    store.capacity_usage().unwrap().reserved_bytes,
    before_rejected_continuation,
  )
  assert_false(@utf8.decode(continuation.body).contains("Count__c"))
  let reserved = consumer.usage().reserved_retention_bytes
  let physical_reserved = store.capacity_usage().unwrap().reserved_bytes
  assert_true(reserved > baseline)
  for _ in 0..<2 {
    if report_wire is Some(expected) {
      assert_eq(
        @remote.remote_effect_checkpoint_report_json(
          retention
          .persist(store, computation_capacity=Some(computation_capacity))
          .unwrap(),
        ),
        expected,
      )
    } else {
      assert_eq(
        retention
        .persist_original_checkpoint(
          store,
          computation_capacity=Some(computation_capacity),
        )
        .unwrap().artifact.checkpoint_cid,
        checkpoint.checkpoint_cid,
      )
    }
    assert_eq(consumer.usage().reserved_retention_bytes, reserved)
    assert_eq(store.capacity_usage().unwrap().reserved_bytes, physical_reserved)
    let current = inspection
      .read("effect_continuation_custody", holding)
      .unwrap()
    assert_eq(current.body, continuation.body)
    assert_eq(current.revision, continuation.revision)
    let current = inspection.read("effect_checkpoint_custody", holding).unwrap()
    assert_eq(current.body, checkpoint_record.body)
    assert_eq(current.revision, checkpoint_record.revision)
  }
  // Retirement is independently confirmed by each existing custody owner.
  // Loss at a later boundary must not reopen earlier retired owners or return
  // the failed owner's reservation before its durable terminal is confirmed.
  for
    step in [
      "effect-checkpoint-terminal-saved", "effect-preview-terminal-saved", "effect-capture-terminal-saved",
    ] {
    let lost = Ref(false)
    let pending = Ref(0L)
    store.observe_allocation(actual => {
      if actual == step && !lost.val {
        lost.val = true
        pending.val = consumer.usage().reserved_retention_bytes
        store.close().unwrap() |> ignore
      }
    })
    match review_work {
      Some(work) =>
        if step == "effect-checkpoint-terminal-saved" {
          let (wire, authentication, reviewers, keys) = resolution_fixture.unwrap()
          // A reentrant trusted clock can begin retirement. Admission must
          // recheck the actual holder after the callback, without dropping
          // the pending original retention owner or returning capacity.
          let cleanup_failed = Ref(false)
          let cleanup_observation = Ref("cleanup callback not reached")
          assert_true(
            work.admit_resolution(
              wire,
              authentication,
              reviewers,
              keys,
              () => true,
              () => {
                let cleanup = work.retry_cleanup()
                cleanup_failed.val = cleanup is Err(Retention(_))
                cleanup_observation.val = match cleanup {
                  Err(Retention(_)) => "retention cleanup pending"
                  Err(Journal(StateCollision)) => "journal custody collision"
                  Err(Journal(Closed)) => "journal closed"
                  Err(Journal(Physical(_))) => "journal physical failure"
                  Err(Journal(_)) => "journal custody rejected"
                  Err(Unavailable) => "review custody unavailable"
                  Err(_) => "review cleanup rejected"
                  Ok(_) => "review cleanup succeeded"
                }
                "2026-10-10T00:01:00.000Z"
              },
            )
            is Err(AuthorityDenied),
            msg=cleanup_observation.val[:],
          )
          assert_true(cleanup_failed.val)
        } else {
          assert_true(work.retry_cleanup() is Err(Retention(_)))
        }
      None => assert_true(retention.retry_cleanup() is Err(_))
    }
    // The adapter must retain its exact input context and public Result when
    // any existing retirement owner is unconfirmed. No capacity is returned.
    assert_eq(consumer.request_for_effect_review(inputs), materials.request)
    assert_true(result.output.result_schema_wire() is Ok(_))
    assert_true(lost.val)
    assert_true(pending.val > baseline)
    assert_eq(consumer.usage().reserved_retention_bytes, pending.val)
    assert_true(retention.report() is Err(Unavailable))
    assert_true(confirm() is Err(Unavailable))
    store = open()
    retention.restore_store(store).unwrap()
    assert_eq(consumer.usage().reserved_retention_bytes, pending.val)
    assert_true(
      retention.persist(store, computation_capacity=Some(computation_capacity))
      is Err(Unavailable),
    )
    assert_true(
      retention.persist_original_checkpoint(
        store,
        computation_capacity=Some(computation_capacity),
      )
      is Err(Unavailable),
    )
  }
  assert_true(retention.retry_cleanup().unwrap())
  assert_eq(
    approval_scope.current_for(
      request,
      @publication.publication_contract_identity(materials.run_definition),
      persisted.artifact.checkpoint_cid,
    ),
    None,
  )
  assert_false(retention.retry_cleanup().unwrap())
  assert_true(retention.restore_store(store) is Err(Unavailable))
  assert_true(retention.report() is Err(Unavailable))
  assert_true(confirm() is Err(Unavailable))
  assert_true(
    retention.review_projection(() => true, 65536) is Err(Unavailable),
  )
  assert_eq(consumer.usage().reserved_retention_bytes, baseline)
  assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(consumer.request_for_effect_review(inputs), materials.request)
  for table in ["effect_continuation_custody", "effect_checkpoint_custody"] {
    let terminal = inspection.read(table, holding).unwrap()
    assert_eq(terminal.revision, 1L)
    assert_false(@utf8.decode(terminal.body).contains("ciphertext"))
  }
  inspection.close()
  store.close().unwrap() |> ignore
  println(
    "native-effect-review-retention: original capture, Preview and Checkpoint resume and retire through existing custody owners",
  )
}
