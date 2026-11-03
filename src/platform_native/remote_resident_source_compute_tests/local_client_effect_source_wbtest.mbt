// Actual Native Source/Effect computation for an accepted original Submission.
// This is a Host connection test, not public CLI ingress or Provider apply.

///|
// This component fixture has no original normalization custody. Absence is
// explicit, not an empty journal or proof of completion-free applicability.
fn local_client_effect_source_materials(
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request : @host.ClientRequestIdentity,
) -> @host.ClientEffectRunMaterials {
  {
    normalization: None,
    prepared: @host.client_effect_compilation_owner(allowed.compilation),
    compilation: allowed.compilation,
    allowed,
    run_definition: definition,
    request: Some(request),
  }
}

///|
fn local_client_effect_source_original(
  root : String,
  name : String,
  adopted_host? : @client.NativeLocalHostConnection? = None,
) -> (
  @sqlite.Database?,
  @client.NativeClientRunJournal,
  @client.NativeClientSubmissionReference,
  @host.ClientRequestIdentity,
  @host.ClientEffectAllowedRun,
  @publication.PublicationContract,
) raise {
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let database = if adopted_host is Some(_) {
    None
  } else {
    Some(sqlite.open_database(root + "/" + name + ".sqlite3", 131072L).unwrap())
  }
  let (journal, authority, scope) = match adopted_host {
    Some(host) => {
      assert_true(
        host.authorize({
          principal: "operator",
          connection: "cli",
          resource: "run",
          operation: "submit",
        })
        is Ok(@authorization.Allow(_)),
      )
      (
        host.run_journal().unwrap(),
        host.epoch_authority().unwrap(),
        host.authority_scope_cid("operator", "cli", crypto).unwrap(),
      )
    }
    None => {
      let database = database.unwrap()
      // Independently authored initial custody in this test-owned fresh DB only.
      // No production adoption/grant or Submission/Run receipt is synthesized.
      // The real epoch Owner issues and authenticates every reference below.
      database.begin_immediate().unwrap()
      database.install_client_run_definition_schema(8L).unwrap()
      let key = @base64.encode(crypto.random_bytes(32).unwrap())
      database
      .insert(
        "client_submission_epoch",
        "authority",
        @utf8.encode(
          "{\"authentication_key\":\"" +
          key +
          "\",\"observed_at\":0,\"version\":\"actql-native-submission-epoch-custody/0.1\"}",
        ),
      )
      .unwrap()
      |> ignore
      database.insert("client_run_custody", "issued", b"0").unwrap() |> ignore
      database.insert("client_cancel_custody", "issued", b"0").unwrap()
      |> ignore
      database
      .insert("client_submitted_intent_custody", "issued", b"0")
      .unwrap()
      |> ignore
      database.insert("client_submitted_intent_usage", "retained", b"0:0").unwrap()
      |> ignore
      database.commit().unwrap()
      let journal = @client.open_native_client_run_journal(database, 8).unwrap()
      let authority = @client.open_native_client_epoch_authority(
        database, crypto, 100.0,
      ).unwrap()
      (journal, authority, "sha256:" + "a".repeat(64))
    }
  }
  let epoch = authority
    .issue_epoch(
      scope,
      true,
      if adopted_host is Some(_) {
        @env.now().to_double()
      } else {
        1000.0
      },
    )
    .unwrap()
  let reference = @client.prepare_native_client_submission_reference(
    epoch, "original-local-effect-source-submit",
  ).unwrap()
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    resident_native_effect_document +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  journal
  .record_submitted_intent(
    authority,
    reference,
    intent,
    scope,
    true,
    if adopted_host is Some(_) {
      @env.now().to_double()
    } else {
      1001.0
    },
  )
  .unwrap()
  |> ignore
  let environment = @host.admit_client_check_environment(
    resident_effect_source_environment,
    resident_effect_source_bundle_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let preparation = @client.prepare_native_client_submitted_program(
    intent,
    environment,
    None,
    [],
    retained_compute_effect_limits(),
  ).unwrap()
  guard @client.native_client_submitted_preparation(preparation)
    is @client.EffectComputation(prepared) else {
    abort("original submitted Source Effect was not prepared")
  }
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @host.client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @host.issue_client_effect_allowed_run(
    compilation,
    scope,
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_effect_run_definition(
    allowed, "native-client-effect-fixture", "original-local-effect-source-run",
    "2026-10-10T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @host.prepare_client_effect_request_identity(
    prepared,
    scope,
    @client.native_client_submission_request_id(reference),
    @host.source_free_caller_input_intent_cid(),
  ).unwrap()
  let accepted = journal
    .accept_submitted_effect_run(
      authority,
      reference,
      preparation,
      request,
      allowed,
      definition,
      scope,
      true,
      if adopted_host is Some(_) {
        @env.now().to_double()
      } else {
        1002.0
      },
    )
    .unwrap()
  assert_eq(
    @client.native_client_submitted_run_definition_cid(
      @client.native_client_submitted_run_admission(accepted).unwrap(),
    ),
    @publication.publication_contract_identity(definition),
  )
  (database, journal, reference, request, allowed, definition)
}

///|
test "Native original accepted Effect Run acquires once computes its Result and retains cleanup pins" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    abort("Native Client Effect Source requires its actual DuckDB fixture")
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "native-client-effect-source-" + @env.now().to_string() + ".duckdb"
  let root = @filesystem.open_root(root_path).unwrap()
  let path = root_path + "/" + name
  resident_compute_database(library, path)
  let (database, journal, _, request, allowed, definition) = local_client_effect_source_original(
    root_path, name,
  )
  let configured = resident_compute_configuration(library, path)
  let configuration : @resident.ResidentSourceComputeConfiguration = {
    ..configured,
    source: {
      ..configured.source,
      ledger: {
        ..configured.source.ledger,
        retained_bytes: 536870912L,
        execution_bytes: 536870912L,
      },
    },
  }
  let mut acquisitions = 0
  let mut consumers = 0
  let mut cleanups = 0
  let mut authorized = true
  let mut now = "2026-10-10T00:00:01.000Z"
  assert_true(
    @client.open_native_client_effect_source_work(
      journal,
      request,
      allowed,
      definition,
      local_client_effect_source_materials(allowed, definition, request),
      configuration,
      name,
      () => "2099-01-01T00:00:00.000Z",
      () => true,
    )
    is Err(@client.OriginalRunNotCurrent),
  )
  assert_true(
    @client.open_native_client_effect_source_work(
      journal,
      request,
      allowed,
      definition,
      local_client_effect_source_materials(allowed, definition, request),
      configuration,
      name,
      () => "2026-10-10T00:00:01.000Z",
      () => false,
    )
    is Err(@client.NativeClientSourceWorkIssue::AuthorizationDenied),
  )
  let work = @client.open_native_client_effect_source_work(
    journal,
    request,
    allowed,
    definition,
    local_client_effect_source_materials(allowed, definition, request),
    configuration,
    name,
    () => now,
    () => authorized,
    observe=event => {
      match event {
        @resident.AcquisitionEntered => acquisitions += 1
        @resident.ConsumerEntered(_) => consumers += 1
        @resident.CleanupCompleted => cleanups += 1
        _ => ()
      }
      true
    },
  ).unwrap()
  assert_eq(acquisitions, 1)
  assert_eq(consumers, 0)
  let before_original_capture = work.usage()
  // This accepted legacy fixture deliberately has no original normalization
  // custody. Even actual acquisition cannot substitute an empty journal.
  assert_true(
    work.prepare_original_capture_context(
      retained_compute_effect_retention(),
      resident_compute_limits(),
      65536,
      4096,
      64,
    )
    is Err(@client.Normalization(@host.MissingOriginalJournal)),
  )
  assert_eq(work.usage(), before_original_capture)
  assert_eq(acquisitions, 1)
  assert_eq(consumers, 0)
  // Reclaiming the original file proves the consumer uses retained input.
  resident_compute_reclaim(root, name)
  authorized = false
  // Current authorization is checked before exposing missing original custody.
  assert_true(
    work.prepare_original_capture_context(
      retained_compute_effect_retention(),
      resident_compute_limits(),
      65536,
      4096,
      64,
    )
    is Err(@client.Original(@client.AuthorizationDenied)),
  )
  assert_true(
    work.execute_task(1)
    is Err(@client.NativeClientSourceWorkIssue::AuthorizationDenied),
  )
  assert_true(
    work.owner_for_capture()
    is Err(@client.NativeClientSourceWorkIssue::AuthorizationDenied),
  )
  assert_eq(consumers, 0)
  authorized = true
  now = "2099-01-01T00:00:00.000Z"
  assert_true(work.execute_task(1) is Err(@client.OriginalRunNotCurrent))
  assert_true(work.owner_for_capture() is Err(@client.OriginalRunNotCurrent))
  assert_true(
    work.prepare_result_export(resident_compute_limits())
    is Err(@client.OriginalRunNotCurrent),
  )
  assert_eq(consumers, 0)
  now = "2026-10-10T00:00:02.000Z"
  work.execute_task(1).unwrap()
  assert_eq(consumers, 1)
  let output = work.prepare_result_export(resident_compute_limits()).unwrap()
  let rows = StringBuilder()
  while output.next().unwrap() is Some(chunk) {
    rows.write_string(chunk)
  }
  rows.write_string(output.finish().unwrap())
  assert_eq(rows.to_string(), "[{\"id\":3}]")
  assert_eq(output.result_fields().unwrap(), ["id"])
  assert_eq(
    output.result_schema_wire().unwrap(),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  output.cancel()
  let owner = work.owner_for_capture().unwrap()
  let inputs = @strategy.pin_captured_effect_sources(
    owner.effect_run().unwrap(),
    4,
  ).unwrap()
  assert_false(work.close())
  assert_true(work.usage().held_bytes > 0L)
  assert_eq(cleanups, 0)
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_false(@strategy.release_captured_effect_inputs(inputs))
  authorized = false
  assert_true(work.close())
  assert_true(work.close())
  assert_eq(cleanups, 1)
  assert_eq(work.usage().held_bytes, 0L)
  assert_eq(work.usage().reserved_transfer_bytes, 0L)
  assert_eq(work.usage().reserved_retention_bytes, 0L)
  assert_eq(work.usage().reserved_execution_bytes, 0L)
  authorized = true
  assert_true(
    work.owner_for_capture() is Err(@client.Work(@resident.Unavailable)),
  )
  assert_true(
    @client.open_native_client_effect_source_work(
      journal,
      request,
      allowed,
      definition,
      local_client_effect_source_materials(allowed, definition, request),
      configuration,
      name,
      () => "2026-10-10T00:00:03.000Z",
      () => true,
    )
    is Err(@client.NeedsOriginalReconciliation),
  )
  assert_eq(acquisitions, 1)
  assert_eq(consumers, 1)
  database.unwrap().close_checked().unwrap()
}

///|
test "Native original Effect captures its real acquired producer and local import without Remote dispatch" {
  native_local_effect_capture_acceptance(false)
}

///|
test "Native original Local Effect persists waiting rejects explicitly and retries cleanup" {
  native_local_effect_capture_acceptance(true)
}

///|
fn native_local_effect_capture_acceptance(
  review : Bool,
  initial_reviewer? : PairedInitialReviewerFixture? = None,
) -> Unit raise {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    abort("Native Client Effect capture requires actual DuckDB")
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "native-client-effect-capture-" +
    @env.now().to_string() +
    ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let (database, journal, reference, request, allowed, definition) = local_client_effect_source_original(
    root_path,
    name,
    adopted_host=initial_reviewer.map(value => value.host),
  )
  let configured = resident_compute_configuration(library, path)
  let configuration : @resident.ResidentSourceComputeConfiguration = {
    ..configured,
    source: {
      ..configured.source,
      ledger: {
        ..configured.source.ledger,
        retained_bytes: 536870912L,
        execution_bytes: 536870912L,
      },
    },
  }
  let mut acquisitions = 0
  let mut computations = 0
  let mut authorized = true
  let prepared = @host.client_effect_compilation_owner(allowed.compilation)
  let original_bound = @host.bind_client_effect_compiled_run(
    prepared, allowed, definition,
  ).unwrap()
  let original_materials : @host.ClientEffectRunMaterials = {
    normalization: None,
    prepared,
    compilation: allowed.compilation,
    allowed,
    run_definition: definition,
    request: Some(request),
  }
  let other_definition = @host.issue_client_effect_run_definition(
    allowed, "native-client-effect-fixture", "foreign-review-materials-run", "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  for
    foreign_materials in [
      { ..original_materials, run_definition: other_definition, },
      { ..original_materials, request: None, },
    ] {
    assert_true(
      @client.open_native_client_effect_source_work(
        journal,
        request,
        allowed,
        definition,
        foreign_materials,
        configuration,
        name,
        () => "2026-10-10T00:00:01.000Z",
        () => authorized,
        observe=event => {
          if event is @resident.AcquisitionEntered {
            acquisitions += 1
          }
          true
        },
      )
      is Err(@client.Work(@resident.ForeignEffectMaterials)),
    )
    assert_eq(acquisitions, 0)
    let refused = @resident.open_resident_effect_source_compute(
      original_bound,
      configuration,
      name,
      materials=foreign_materials,
      observe=event => {
        match event {
          @resident.AcquisitionEntered => acquisitions += 1
          @resident.ConsumerEntered(_) => computations += 1
          _ => ()
        }
        true
      },
    )
    guard refused is Err((@resident.ForeignEffectMaterials, pending)) else {
      fail("foreign Local review materials must be refused before acquisition")
    }
    assert_true(
      @output.retry_native_remote_standard_input_failure_cleanup(pending),
    )
  }
  assert_eq(acquisitions, 0)
  assert_eq(computations, 0)
  let work = @client.open_native_client_effect_source_work(
    journal,
    request,
    allowed,
    definition,
    local_client_effect_source_materials(allowed, definition, request),
    configuration,
    name,
    () => {
      if initial_reviewer is Some(fixture) && fixture.attest_host {
        @values.epoch_milliseconds_timestamp(@env.now().reinterpret_as_int64()).unwrap_or(
          "",
        )
      } else {
        "2026-10-10T00:00:01.000Z"
      }
    },
    () => authorized,
    observe=event => {
      match event {
        @resident.AcquisitionEntered => acquisitions += 1
        @resident.ConsumerEntered(_) => computations += 1
        _ => ()
      }
      true
    },
  ).unwrap()
  work.execute_task(1).unwrap()
  resident_compute_reclaim(root, name)
  let normalization = @publication.seal_run_evidence_value(
    "normalization_journal",
    "{\"version\":\"actql-normalization-journal/0.1\",\"rule_catalog_cid\":\"sha256:" +
    "d".repeat(64) +
    "\",\"entries\":[]}",
    65536,
    4096,
    64,
  ).unwrap()
  let before = work.usage()
  // Budget-exhaustion counterexamples have their own original Run. They
  // must not consume the review acceptance Run's finite attempt allowance.
  if !review {
    assert_true(
      work.prepare_capture_context(
        retained_compute_effect_retention(),
        normalization,
        resident_compute_limits(),
        65536,
        4096,
        64,
        max_work=0,
      )
      is Err(@client.Capture(@resident.InvalidLimits)),
    )
    assert_eq(work.usage(), before)
    let limited = work.prepare_capture_context(
      retained_compute_effect_retention(),
      normalization,
      resident_compute_limits(),
      65536,
      4096,
      64,
      max_work=1,
    )
    assert_true(
      limited
      is Err(@client.Capture(@resident.Pins(@strategy.PreviewWorkLimit))),
      msg=match limited {
        Err(@client.Capture(@resident.Invocation(@resident.Invocation(issue)))) =>
          @debug.to_string(issue)
        Err(@client.Capture(@resident.Invocation(@resident.ForeignRun))) =>
          "Foreign original Run"
        Err(@client.Capture(@resident.Invocation(@resident.Unavailable))) =>
          "Original Source unavailable"
        Err(
          @client.Capture(
            @resident.Invocation(@resident.Observation(@resident.Unavailable))
          )
        ) => "Source observation unavailable"
        Err(
          @client.Capture(
            @resident.Invocation(@resident.Observation(@resident.Identity(_)))
          )
        ) => "Source identity unavailable"
        Err(
          @client.Capture(
            @resident.Invocation(@resident.Observation(@resident.Logical(_)))
          )
        ) => "Source logical input refused"
        Err(
          @client.Capture(
            @resident.Invocation(
              @resident.Observation(@resident.Evidence(issue))
            )
          )
        ) => @debug.to_string(issue)
        Err(@client.Original(_)) => "Original journal or authorization refused"
        Err(@client.Capture(@resident.Source(_))) => "Source evidence refused"
        _ => "Unexpected capture budget result"
      },
    )
    assert_eq(work.usage().held_bytes, before.held_bytes)
    assert_eq(
      work.usage().reserved_retention_bytes,
      before.reserved_retention_bytes,
    )
    assert_eq(
      work.usage().reserved_execution_bytes,
      before.reserved_execution_bytes,
    )
  }
  let foreign = @host.issue_client_effect_run_definition(
    allowed, "native-client-effect-fixture", "foreign-local-effect-capture-run",
    "2026-10-10T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let owner = work.owner_for_capture().unwrap()
  assert_true(
    owner.prepare_local_effect_capture_context(
      {
        normalization: None,
        prepared: @host.client_effect_compilation_owner(allowed.compilation),
        compilation: allowed.compilation,
        allowed,
        run_definition: foreign,
        request: Some(request),
      },
      request,
      "2026-10-10T00:00:01.000Z",
      "2026-10-10T00:00:01.000Z",
      retained_compute_effect_retention(),
      normalization,
      resident_compute_limits(),
      4,
      10000,
      65536,
      4096,
      64,
      () => true,
    )
    is Err(@resident.Invocation(@resident.ForeignRun)),
  )
  assert_eq(work.usage().held_bytes, before.held_bytes)
  assert_eq(acquisitions, 1)
  assert_eq(computations, 1)
  let capture = work
    .prepare_capture_context(
      retained_compute_effect_retention(),
      normalization,
      resident_compute_limits(),
      65536,
      4096,
      64,
    )
    .unwrap()
  let facts = capture.facts().unwrap()
  // The preparation fence retains this same started Work and actual capture.
  // Identity projection does not obtain an issuer/read grant or enter Provider
  // I/O. These are matching Native definitions until physically executed.
  let retained_revision = match journal.lookup(request, true) {
    Ok(@client.Retained(record)) =>
      @client.native_client_run_record_revision(record)
    _ => abort("original preparation Work missing")
  }
  let fence = work
    .prepare_observation_fence(capture, 1, "save", 10000, 65536, 4096, 64)
    .unwrap()
  let fence_identity = fence.identity().unwrap()
  let fields = @credential.local_preparation_fence_fields(fence_identity)
  assert_eq(
    fields.client_request_intent_cid,
    @host.client_request_intent_cid(request),
  )
  assert_eq(
    fields.client_request_scope_cid,
    @host.client_request_scope_cid(request),
  )
  assert_eq(
    fields.run_invocation_cid,
    @publication.publication_contract_identity(facts.invocation),
  )
  assert_eq(
    fields.unit_definition_cid,
    @host.client_effect_local_invocation_unit_definition_cid(
      @host.client_effect_local_artifact_invocation(facts.consumer),
    ),
  )
  let checked_occurrence = @host.issue_source_free_client_effect_local_identity(
    facts.materials.prepared,
    facts.inputs,
    0,
    facts.consumer,
    10000,
    65536,
    4096,
    64,
  ).unwrap()
  assert_eq(
    fields.operation_occurrence_cid,
    @host.client_effect_local_identity_cid(checked_occurrence),
  )
  for (stage, effect) in [(0, "save"), (1, "foreign")] {
    assert_true(
      work.prepare_observation_fence(
        capture, stage, effect, 10000, 65536, 4096, 64,
      )
      is Err(@client.Member(@host.InvalidMember)),
    )
  }
  assert_true(
    work.prepare_observation_fence(capture, 1, "save", 0, 65536, 4096, 64)
    is Err(@client.Member(@host.InvalidMember)),
  )
  assert_true(
    work.prepare_observation_fence(capture, 1, "save", 10000, 1, 4096, 64)
    is Err(@client.Occurrence(@host.Encoding)),
  )
  authorized = false
  assert_true(
    fence.identity() is Err(@client.Original(@client.AuthorizationDenied)),
  )
  assert_true(
    work.prepare_observation_fence(capture, 1, "save", 10000, 65536, 4096, 64)
    is Err(@client.Original(@client.AuthorizationDenied)),
  )
  authorized = true
  assert_eq(
    @credential.local_preparation_fence_cid(fence.identity().unwrap()),
    @credential.local_preparation_fence_cid(fence_identity),
  )
  guard journal.lookup(request, true) is Ok(@client.Retained(after_fence)) else {
    fail("fence observation lost the original Run")
  }
  assert_eq(
    @client.native_client_run_record_revision(after_fence),
    retained_revision,
  )
  assert_eq(acquisitions, 1)
  assert_eq(computations, 1)
  assert_eq(facts.materials.request, Some(request))
  // Review must retain the accepted request, not require a Remote receiver.
  assert_eq(owner.request_for_effect_review(facts.inputs), Some(request))
  let review_materials = owner.effect_materials_for_capture().unwrap()
  assert_true(
    physical_equal(review_materials.prepared, facts.materials.prepared),
  )
  assert_eq(review_materials.request, Some(request))
  assert_true(
    owner.effect_review_input_binding(facts.materials, facts.inputs, request)
    is Ok(
      @resident.Acquired(
        "connector://crm/main/r#v",
        "sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"
      )
    ),
  )
  assert_true(
    owner.effect_review_input_binding(
      { ..facts.materials, run_definition: foreign, },
      facts.inputs,
      request,
    )
    is Err(@resident.ForeignCapture),
  )
  let other_request = @host.prepare_client_effect_request_identity(
    facts.materials.prepared,
    @host.client_request_authority_scope_cid(request),
    "other-local-review-request",
    @host.client_request_input_cid(request),
  ).unwrap()
  assert_true(
    owner.effect_review_input_binding(
      facts.materials,
      facts.inputs,
      other_request,
    )
    is Err(@resident.ForeignCapture),
  )
  assert_true(
    owner.effect_review_input_binding(
      { ..facts.materials, request: Some(other_request), },
      facts.inputs,
      request,
    )
    is Err(@resident.ForeignCapture),
  )
  assert_eq(
    @publication.publication_contract_identity(facts.materials.run_definition),
    @publication.publication_contract_identity(definition),
  )
  // Producer and Effect input contain different rows. Their checked Artifact
  // custody must remain distinct even though both Results are named "r".
  assert_true(facts.producer_index != facts.consumer_index)
  assert_eq(
    @execution.completed_relation_export_measurement(
      @host.client_effect_local_relation_export_receipt(facts.producer),
    ).row_count,
    3,
  )
  assert_eq(
    @execution.completed_relation_export_measurement(
      @host.client_effect_local_relation_export_receipt(facts.consumer),
    ).row_count,
    1,
  )
  assert_true(
    @host.client_effect_local_artifact_definition_cid(facts.producer) !=
    @host.client_effect_local_artifact_definition_cid(facts.consumer),
  )
  let dependencies : Array[@host.ClientEffectDependencyCapture] = []
  for
    (artifact, index, expected) in [
      (
        facts.producer,
        facts.producer_index,
        "{\"sort\":\"relation\",\"value\":[{\"id\":1},{\"id\":2},{\"id\":3}]}",
      ),
      (
        facts.consumer,
        facts.consumer_index,
        "{\"sort\":\"relation\",\"value\":[{\"id\":3}]}",
      ),
    ] {
    let dependency = owner
      .capture_effect_dependency(
        facts.materials,
        facts.inputs,
        artifact,
        index,
        resident_compute_limits(),
        65536,
        4096,
        64,
      )
      .unwrap()
    assert_eq(
      @host.client_effect_dependency_capture_bodies(dependency)
      .filter(body => {
        @publication.captured_effect_dependency_body_kind(body) ==
        "relation_value"
      })
      .map(@publication.captured_effect_dependency_body_json),
      [expected],
    )
    dependencies.push(dependency)
  }
  assert_true(
    owner.capture_effect_dependency(
      facts.materials,
      facts.inputs,
      facts.producer,
      facts.consumer_index,
      resident_compute_limits(),
      65536,
      4096,
      64,
    )
    is Err(@resident.ForeignInput),
  )
  assert_true(
    owner.capture_effect_dependency(
      facts.materials,
      facts.inputs,
      facts.consumer,
      facts.producer_index,
      resident_compute_limits(),
      65536,
      4096,
      64,
    )
    is Err(@resident.ForeignInput),
  )
  assert_eq(acquisitions, 1)
  assert_eq(computations, 1)
  assert_eq(facts.result.output.result_fields().unwrap(), ["id"])
  assert_eq(
    facts.result.output.result_schema_wire().unwrap(),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  let replay = facts.result.output.replay().unwrap()
  let rows = StringBuilder()
  while replay.next().unwrap() is Some(chunk) {
    rows.write_string(chunk)
  }
  rows.write_string(replay.finish().unwrap())
  assert_eq(rows.to_string(), "[{\"id\":3}]")
  replay.cancel()
  @publication.validate_run_publication_chain(
    definition,
    facts.invocation,
    [facts.result.definition],
    [facts.result.artifact],
    facts.result.manifest,
    65536,
    4096,
    64,
  ).unwrap()
  |> ignore
  assert_eq(@strategy.captured_effect_local_result_count(facts.inputs), 2)
  assert_true(
    @host.client_effect_imported_scope_json(facts.imported).contains(
      "actql-acquisition-scope/0.1",
    ),
  )
  let consumer_manifest = @host.issue_client_effect_local_manifest(
    facts.materials.prepared,
    @host.client_effect_imported_invocation(facts.imported),
    [facts.consumer],
    65536,
    4096,
    64,
  ).unwrap()
  // Reuse the existing checked Preview, full capture and persistence fault
  // fixtures. Protocol target metadata is explicit; no Provider write occurs.
  let stop_custodies : Array[
    (@resident.ResidentEffectSourceCustody, @store.Store),
  ] = []
  retained_effect_preview_inputs(
    owner,
    facts.materials,
    facts.inputs,
    facts.invocation,
    facts.consumer,
    facts.consumer_index,
    stop_custodies,
    consumer_manifest,
    facts.imported,
    facts.acquired,
    facts.acquired_bodies,
    dependencies,
    facts.result,
    original_work=if review { Some((work, journal)) } else { None },
    initial_reviewer=initial_reviewer.map(value => (value, reference)),
  )
  authorized = false
  assert_true(
    fence.identity() is Err(@client.Original(@client.AuthorizationDenied)),
  )
  assert_true(capture.facts() is None)
  assert_false(work.close())
  assert_eq(stop_custodies.length(), if review { 0 } else { 1 })
  for (custody, store) in stop_custodies {
    assert_true(custody.begin_payload() is Err(@resident.Unavailable))
    assert_true(custody.confirm_payload() is Err(@resident.Unavailable))
    assert_true(custody.open_reader() is Err(@resident.Unavailable))
    assert_true(custody.retry_cleanup().unwrap())
    assert_false(custody.retry_cleanup().unwrap())
    assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
    assert_true(store.close().unwrap())
  }
  assert_true(capture.close())
  assert_true(capture.close())
  authorized = true
  assert_true(fence.identity() is Err(_))
  assert_true(
    work.prepare_observation_fence(capture, 1, "save", 10000, 65536, 4096, 64)
    is Err(_),
  )
  assert_true(owner.request_for_effect_review(facts.inputs) is None)
  assert_true(
    owner.effect_review_input_binding(facts.materials, facts.inputs, request)
    is Err(@resident.Unavailable),
  )
  assert_true(work.close())
  assert_true(owner.effect_materials_for_capture() is None)
  assert_eq(acquisitions, 1)
  assert_eq(computations, 1)
  assert_eq(work.usage().held_bytes, 0L)
  assert_eq(work.usage().reserved_retention_bytes, 0L)
  assert_eq(work.usage().reserved_execution_bytes, 0L)
  if initial_reviewer is Some(value) {
    assert_true(value.restored)
    assert_true(
      value.binding
      .unwrap()
      .restore_initial_resolution_candidate("paired-initial-reviewer")
      is Err(_),
    )
    value.host.close().unwrap()
    value.crypto.close_checked().unwrap()
    return
  }
  database.unwrap().close_checked().unwrap()
  // Reopening the actual original journal is not a new process claim. The
  // original rejected Run and its Checkpoint state must survive unchanged.
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let reopened = sqlite
    .open_database(root_path + "/" + name + ".sqlite3", 131072L)
    .unwrap()
  let journal = @client.open_native_client_run_journal(reopened, 8).unwrap()
  guard journal.lookup(request, true) is Ok(@client.Retained(restored)) else {
    fail("original Local review Run missing after journal reopen")
  }
  assert_eq(
    @publication.publication_contract_identity(
      @client.native_client_run_definition(restored),
    ),
    @publication.publication_contract_identity(definition),
  )
  if review {
    assert_eq(
      @client.native_client_run_checkpoint_state(restored).unwrap().status,
      @publication.Cancelled,
    )
  } else {
    assert_true(@client.native_client_run_checkpoint_state(restored) is None)
  }
  assert_false(journal.claim_physical_start(request, true).unwrap())
  reopened.close_checked().unwrap()
}
