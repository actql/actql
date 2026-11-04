///|
/// Independently installed physical Provider policy, shared by refusal and
/// success cases. This fixture is not Cloud approval authority.
fn retained_holder_review_policy(
  holder : @resident.ResidentRetainedConsumer,
  journal : @dispatch_journal.Journal,
  inputs : @strategy.CapturedEffectInputs,
  invocation : @publication.PublicationContract,
  mapped_create? : Bool = false,
) -> @effect_provider.NativeResidentEffectReviewPolicy raise {
  let dispatch = @resident.resident_retained_consumer_request(holder)
  let mut result_index = -1
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    if @strategy.captured_effect_local_result_matches_member(inputs, index, 0) {
      result_index = index
    }
  }
  assert_true(result_index >= 0)
  let binding = {
    ..(if mapped_create {
      native_mapped_create_binding()
    } else {
      provider_binding()
    }),
    run_invocation_cid: @publication.publication_contract_identity(invocation),
    dispatch_request_cid: @remote.dispatch_request_identity(dispatch),
  }
  let catalog = if mapped_create {
    native_mapped_create_catalog(binding)
  } else {
    provider_catalog(binding)
  }
  {
    stage: 1,
    effect_id: "save",
    result_index,
    mapping: if mapped_create {
      native_mapped_create_mapping()
    } else {
      provider_mapping()
    },
    projection: @catalog.prepare_write_projection(
      catalog,
      binding,
      "ActQL_Test_Record__c",
      if mapped_create {
        @catalog.WriteCreate
      } else {
        @catalog.WriteUpdateById
      },
      ["Count__c"],
      1,
    ).unwrap(),
    catalog,
    api_version: "v66.0",
    runtime_bundle_cid: @remote.dispatch_request_execution_scope(dispatch)[2],
    source_binding_cid: holder
    .effect_source_binding_cid(journal, inputs)
    .unwrap(),
    store_authority_cid: retained_compute_cid("a"),
    retention: retained_compute_effect_retention(),
    retention_dependencies: [
      "retention_contract", "metadata_retention_policy", "clock_contract",
    ].map(kind => {
      @publication.admit_hashed_effect_dependency_body(
        kind,
        retained_effect_retention_dependency_cid(kind),
        retained_effect_retention_dependency_wire(kind),
        65536,
        4096,
        64,
      ).unwrap()
    }),
    dependency_limits: {
      max_entries: 100,
      max_total_bytes: 65536,
      max_depth: 64,
      max_references: 1000,
    },
    preview_limits: {
      max_work: 10000,
      max_wire_bytes: 65536,
      max_nodes: 10000,
      max_depth: 64,
      plan: {
        max_work: 10000,
        max_fields: 100,
        max_bytes: 65536,
        max_nodes: 10000,
        max_depth: 64,
      },
    },
    export_limits: resident_compute_limits(),
    dispatch_limits: { max_bytes: 4096, max_nodes: 32, max_depth: 8, },
    body_limits: { max_bytes: 1024, max_nodes: 32, max_depth: 5, },
    request_limits: {
      max_path_bytes: 1024,
      max_target_bytes: 128,
      max_body_bytes: 1024,
    },
    observation_limits: {
      max_bytes: 1024,
      max_nodes: 32,
      max_depth: 5,
      max_identity_bytes: 1024,
    },
    max_rows: 1,
    max_fields: 100,
    max_capture_workspace_entries: 10000,
    max_work: 10000,
    max_utf16_units: 10000,
  }
}

///|
/// Real original holders through the production Provider/review connection.
/// Credential authorization is separately installed by the physical fixture;
/// journal report custody is real, while Cloud commit/approval/write remain
/// separate and unverified here.
fn retained_holder_provider_review(
  holder : @resident.ResidentRetainedConsumer,
  journal : @dispatch_journal.Journal,
  consumer : @resident.ResidentSourceCompute,
  source_owner : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  dispatch : @remote.DispatchRequest,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  producer : @resident.ResidentEffectProducerCapture,
  receiver : @host.ClientEffectLocalResultArtifact,
  imported : @host.ClientEffectImportedEvidence,
  root_index : Int,
  root_path : String,
  name : String,
  owned_context : @resident.ResidentEffectReviewInputContext,
  normalization : @publication.RunEvidenceValue,
  prepare_context : () -> Result[
    @resident.ResidentEffectReviewInputContext,
    @resident.ResidentEffectReviewInputFailure,
  ],
) -> Unit raise {
  let mark = (phase : String) => {
    @filesystem.open_root(root_path)
    .unwrap()
    .create_directory(name + ".review-" + phase)
    .unwrap()
    |> ignore
  }
  let request = consumer.request_for_effect_review(inputs).unwrap()
  assert_eq(Some(request), materials.request)
  let policy = retained_holder_review_policy(
    holder, journal, inputs, invocation,
  )
  // The create connection cannot reinterpret this genuine update member,
  // export a different input, or acquire Provider authority from it.
  let create_before = consumer.usage().reserved_retention_bytes
  assert_true(
    @effect_provider.prepare_native_resident_effect_created_targets(
      consumer,
      materials,
      inputs,
      policy.stage,
      policy.effect_id,
      policy.result_index,
      policy.mapping,
      policy.projection,
      policy.api_version,
      policy.export_limits,
      policy.body_limits,
      policy.request_limits,
      policy.max_rows,
      policy.max_fields,
      policy.max_work,
      policy.max_utf16_units,
      policy.preview_limits.max_wire_bytes,
    )
    is Err(ForeignMapping),
  )
  assert_eq(consumer.usage().reserved_retention_bytes, create_before)
  let work = @effect_provider.prepare_native_resident_effect_review_from_context(
    holder, journal, owned_context, normalization, policy,
  ).unwrap()
  let owned_result = work.result_capture().unwrap()
  assert_eq(
    owned_result.output.result_schema_wire().unwrap(),
    retained_effect_expected_schema(true),
  )
  assert_eq(owned_result.output.row_count().unwrap(), 1)
  let actual_read = owned_result.output.replay().unwrap()
  let actual_rows = StringBuilder()
  while actual_read.next().unwrap() is Some(chunk) {
    actual_rows.write_string(chunk)
  }
  actual_rows.write_string(actual_read.finish().unwrap())
  assert_eq(actual_rows.to_string(), retained_effect_expected_rows(true))
  // An independent context cannot bypass the unchanged public export pin
  // ceiling, and its retirement must leave the adopted Result/input live.
  let congested = prepare_context().unwrap()
  assert_true(
    congested.capture_result(journal, normalization, 65536, 4096, 64)
    is Err(Native(Export(Retain(Physical(HoldingLimit))))),
  )
  assert_true(congested.close())
  assert_true(owned_context.facts(journal) is Some(_))
  assert_true(owned_result.output.result_schema_wire() is Ok(_))
  let prepare = (material, policy) => {
    @effect_provider.prepare_native_resident_effect_review(
      holder, journal, material, inputs, producer, receiver, imported, root_index,
      owned_result, invocation, observation, policy,
    )
  }
  let before = consumer.usage().reserved_retention_bytes
  // A well-formed fixture CID cannot stand in for the original consumer edge.
  assert_true(
    prepare(materials, {
      ..policy,
      source_binding_cid: retained_compute_cid("e"),
    })
    is Err(Unavailable),
  )
  assert_true(
    prepare({ ..materials, request: None, }, policy) is Err(Unavailable),
  )
  assert_true(
    prepare(materials, { ..policy, result_index: root_index, })
    is Err(Unavailable),
  )
  assert_true(
    prepare(materials, {
      ..policy,
      runtime_bundle_cid: retained_compute_cid("f"),
    })
    is Err(Unavailable),
  )
  assert_true(
    prepare(materials, { ..policy, max_work: 0, }) is Err(InvalidLimits),
  )
  assert_true(
    prepare(materials, { ..policy, max_capture_workspace_entries: 0, })
    is Err(InvalidLimits),
  )
  guard policy.catalog.binding is @catalog.SiteCatalog(original_site_binding) else {
    fail("expected the original Site Catalog fixture binding")
  }
  // A valid Catalog with the same Resource shape is still foreign to the
  // original holder. Reject before taking another completed-output export or
  // allowing the Provider access callback to run.
  for
    foreign in [
      { ..original_site_binding, site_key: "foreign-site", },
      { ..original_site_binding, site_generation: 2, },
      {
        ..original_site_binding,
        run_invocation_cid: retained_compute_cid("f"),
      },
      {
        ..original_site_binding,
        dispatch_request_cid: retained_compute_cid("f"),
      },
    ] {
    assert_true(
      prepare(materials, { ..policy, catalog: provider_catalog(foreign), })
      is Err(Unavailable),
    )
    assert_eq(consumer.usage().reserved_retention_bytes, before)
  }
  assert_eq(consumer.usage().reserved_retention_bytes, before)
  assert_true(work.complete() is Err(Unavailable))
  let facts = resident_provider_observe(
    consumer,
    materials,
    inputs,
    producer.acquired,
    dispatch,
    request,
    root_path,
    name,
    original_invocation=Some(invocation),
    review=Some(work),
  ).unwrap()
  mark("provider-observed")
  let capture_progress : Array[
    (@resident.ResidentEffectRunCapturePhase, Int64, Int64),
  ] = []
  let complete = match
    work.complete(
      phase_observe=phase => {
        mark(phase)
        if !(work.complete() is Err(Unavailable)) {
          abort("original review: reentrant completion accepted")
        }
      },
      capture_progress=(phase, advances, logical_work) => {
        capture_progress.push((phase, advances, logical_work))
        let name = match phase {
          Preparing => "preparing"
          Prepared => "prepared"
          Advancing => "advancing"
          Completed => "completed"
        }
        // A partial marker survives a killed Native test even if its output
        // was buffered. It contains no private projection or credential.
        mark(
          "capture-" +
          name +
          "-" +
          advances.to_string() +
          "-" +
          logical_work.to_string(),
        )
        // Only fixed phase names and counters, never original private bodies.
        println(
          "native-effect-capture-progress " +
          name +
          " " +
          advances.to_string() +
          " " +
          logical_work.to_string(),
        )
        if !(work.complete() is Err(Unavailable)) {
          abort("original review: reentrant capture completion accepted")
        }
      },
    ) {
    Ok(value) => value
    Err(Preview(_)) => abort("original review: Preview owner refused")
    Err(Contract(_)) => abort("original review: artifact contract refused")
    Err(Source(_)) => abort("original review: Source evidence refused")
    Err(Dependency(_)) => abort("original review: dependency capture refused")
    Err(Manifest(_)) => abort("original review: manifest refused")
    Err(Inventory(_)) => abort("original review: inventory refused")
    Err(Capture(Context(ForeignInput))) =>
      abort("original review: Captured Run foreign context")
    Err(Capture(Context(Plan(_)))) =>
      abort("original review: Captured Run plan refused")
    Err(Capture(Context(Proof(_)))) =>
      abort("original review: Captured Run proof refused")
    Err(Capture(Context(Encoding))) =>
      abort("original review: Captured Run encoding refused")
    Err(Capture(Capture(CaptureIssuanceEncoding))) =>
      abort("original review: Captured Run issuance budget or encoding")
    Err(Capture(Capture(CaptureIssuanceInventoryMismatch(_)))) =>
      abort("original review: Captured Run inventory mismatch")
    Err(Capture(Capture(_))) =>
      abort("original review: Captured Run issuance refused")
    Err(Capture(Unavailable)) =>
      abort("original review: Captured Run unavailable")
    Err(_) => abort("original review: completion unavailable")
  }
  mark("captured")
  assert_true(capture_progress.length() >= 4)
  assert_true(capture_progress[0].0 is Preparing)
  assert_true(capture_progress[1].0 is Prepared)
  assert_eq(capture_progress[0].1, 0L)
  assert_eq(capture_progress[1].2, 0L)
  let last_progress = capture_progress[capture_progress.length() - 1]
  assert_true(last_progress.0 is Completed)
  assert_true(last_progress.1 > 0L && last_progress.2 > 0L)
  for index = 2; index < capture_progress.length(); index = index + 1 {
    let previous = capture_progress[index - 1]
    let observed = capture_progress[index]
    assert_true(observed.1 >= previous.1 && observed.2 >= previous.2)
    assert_true(observed.2 <= observed.1 * 16L)
  }
  let progress_count = capture_progress.length()
  // A cached completion never advances or issues another Captured Run.
  work
  .complete(capture_progress=(_, _, _) => abort("cached capture advanced"))
  .unwrap()
  |> ignore
  assert_eq(capture_progress.length(), progress_count)
  println("native-original-review: captured completion confirmed")
  // The streaming issuer no longer retains whole evidence buffers. Refuse
  // zero workspace before its fixed owner slots, without assuming the row
  // export's separate 100-entry bound must fail at an old internal phase.
  assert_eq(policy.export_limits.max_result_workspace_entries, 100)
  assert_true(
    consumer.capture_effect_run(
      materials,
      inputs,
      owned_result,
      invocation,
      complete.preview.preview,
      [complete.preview.proof.unwrap()],
      [complete.source],
      [complete.local_source],
      complete.inventory,
      complete.preview.authoring,
      policy.max_fields,
      policy.max_work,
      policy.preview_limits.max_wire_bytes,
      policy.preview_limits.max_nodes,
      policy.preview_limits.max_depth,
      0,
    )
    is Err(Capture(CaptureIssuanceEncoding)),
  )
  mark("small-budget-refused")
  assert_eq(complete.preview.keys.length(), 1)
  assert_true(
    complete.preview.wire.contains(
      "\"before\":{\"state\":\"present\",\"value\":{\"Count__c\":7}}",
    ),
  )
  assert_eq(
    @publication.effect_preview_row_intended_changes_wire(
      @strategy.captured_effect_preview_ledger_identity(
        complete.preview.preview,
      ),
      0,
      0,
    ),
    Some("{\"state\":\"present\",\"value\":{\"Count__c\":3}}"),
  )
  assert_true(
    @publication.publication_contract_json(complete.captured).contains(
      "\"answer\":" + retained_effect_expected_rows(true),
    ),
  )
  assert_eq(
    @publication.publication_contract_identity(
      work.complete().unwrap().captured,
    ),
    @publication.publication_contract_identity(complete.captured),
  )
  assert_eq(facts.runtime_bundle_cid, policy.runtime_bundle_cid)
  // A genuine second observation of the retained Source must not replace
  // the original journal fact. It reads the held capture, never the Source.
  let (refreshed, refreshed_bodies) = retained_compute_acquired_evidence(
    source_owner,
  ).unwrap()
  assert_false(
    @publication.run_evidence_value_identity(
      @host.client_effect_acquired_observation(refreshed),
    ) ==
    @publication.run_evidence_value_identity(
      @host.client_effect_acquired_observation(producer.acquired),
    ),
  )
  assert_true(
    @host.issue_client_effect_capture_inventory(
      materials,
      inputs,
      0,
      complete.source,
      complete.manifest,
      complete.artifact,
      imported,
      refreshed,
      refreshed_bodies.0,
      refreshed_bodies.1,
      complete.dependencies,
      [],
      {
        max_entries: 100,
        max_total_bytes: 65536,
        max_depth: 64,
        max_references: 1000,
      },
      10000,
      64,
    )
    is Err(ForeignInput),
  )
  mark("retention-start")
  // This production connection already issued the full Captured Run. Reuse
  // that Owner result; the independent common-capture cases cover reissuance.
  retained_effect_review_retention_store(
    consumer,
    materials,
    inputs,
    owned_result,
    invocation,
    complete.preview.preview,
    complete.captured,
    @publication.captured_effect_source_store_authority_cid(complete.source),
    complete.preview.wire,
    @publication.run_evidence_value_identity(complete.preview.authoring),
    review_work=Some(work),
    original_journal_path=Some(
      root_path + "/" + name + ".runtime/execution.sqlite3",
    ),
    original_context=Some((owned_context, journal)),
  )
  let saved = journal
    .effect_checkpoint_report(dispatch, {
      max_wire_bytes: 262144,
      max_nodes: 10000,
      max_depth: 64,
    })
    .unwrap()
  assert_eq(saved.1, Some(@remote.RemoteEffectCheckpointReply::Accepted))
  assert_eq(
    @remote.dispatch_request_identity(
      @remote.remote_effect_checkpoint_report_dispatch(saved.0),
    ),
    @remote.dispatch_request_identity(dispatch),
  )
  assert_eq(
    @remote.remote_effect_checkpoint_report_checkpoint(saved.0).checkpoint.required_artifact_cid,
    @publication.effect_preview_semantic_identity(
      @strategy.captured_effect_preview_ledger_identity(
        complete.preview.preview,
      ),
    ),
  )
  assert_true(work.retry_cleanup().unwrap())
  assert_false(work.retry_cleanup().unwrap())
  assert_true(work.complete() is Err(Unavailable))
  assert_true(consumer.request_for_effect_review(inputs) is None)
  assert_true(owned_context.facts(journal) is None)
  assert_true(work.result_capture() is None)
  println(
    if @env.get_env_var("ACTQL_TEST_NATIVE_EFFECT_APPROVED_ROW") == Some("1") {
      "native-effect-original-review: original signed approval, one physical write and common row terminal; no Cloud commit, public approval, restart or formal Run release"
    } else {
      "native-effect-original-review: production review and exact journal report retained; no Cloud commit, approval or write"
    },
  )
}
