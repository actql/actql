// Actual producer Runtime output, not a synthetic completion record. Public
// Cloud delivery remains separate acceptance. The optional consumer branch
// uses the exact Runtime manifest and bytes through an independent Transfer.

///|
fn acquisition_runtime_case(
  through_consumer : Bool,
  effect? : Bool = false,
  completion_free? : Bool = false,
  completion_free_review? : Bool = false,
  mapped_create_write? : Bool = false,
  provider? : Bool = false,
  parent_ack_failure? : Bool = false,
  revoke_effect_at_start? : Bool = false,
  expire_effect_at_start? : Bool = false,
  expire_effect_before_start? : Bool = false,
  fail_effect_capture_cleanup? : Bool = false,
  chain? : Bool = false,
  cancel_chain_tail? : Bool = false,
  through_resident? : Bool = false,
  through_consumer_holder? : Bool = false,
  cancel_consumer_before_start? : Bool = false,
  cancel_consumer_after_borrow? : Bool = false,
  consumer_output_unavailable? : Bool = false,
  cancel_receiver? : Bool = false,
  deny_after_admission? : Bool = false,
  consumer_start_expiry? : Bool = false,
  producer_cleanup_at_handoff? : Bool = false,
  cleanup_after_preparation? : Bool = false,
  cancel_producer_before_handoff? : Bool = false,
) -> Unit raise {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let sqlite = @sqlite.load_library(
    retained_runtime_required_env("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"),
  ).unwrap()
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "acquisition-runtime-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  resident_compute_database(library, path)
  let document = if chain {
    retained_native_chain_document
  } else {
    resident_compute_document
  }
  let prepared = resident_compute_prepared(document~)
  let configuration = resident_compute_configuration(library, path)
  let source = {
    ..configuration.source,
    retained_output_root: Some(root_path),
    ledger: {
      ..configuration.source.ledger,
      retained_bytes: 536870912L,
      execution_bytes: 536870912L,
    },
  }
  let configuration = { ..configuration, source, }
  let (compilation, allowed, definition, caller) = retained_compute_run(
    prepared,
  )
  let materials : @host.ClientRunMaterials = {
    prepared,
    compilation: @host.Tasks(compilation),
    admission: @host.client_compiled_run_admission(allowed),
    run_definition: definition,
  }
  let budget = @remote.prepare_remote_dispatch_budget(1048576L, 1048576L).unwrap()
  let selected = retained_compute_selection(
    bundle_cid=retained_runtime_required_env(
      "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID",
    ),
    budget_cid=@remote.remote_dispatch_budget_cid(budget),
  )
  let site = @site.create_site(
    selected.site_key,
    selected.site_generation,
    selected.runtime_bundle_cid,
    4,
    4,
    536870912L,
    536870912L,
  ).unwrap()
  if completion_free_review {
    assert_true(
      completion_free &&
      effect &&
      through_consumer &&
      through_consumer_holder &&
      !provider,
    )
  }
  let finite = if completion_free {
    assert_true(effect && !provider)
    Some(
      native_completion_free_effect_fixture(
        authoring=if completion_free_review {
          Some(native_mapped_create_authoring())
        } else {
          None
        },
      ),
    )
  } else {
    None
  }
  let effect_pair = if finite is Some(value) {
    Some((value.0, value.1))
  } else if effect {
    Some(retained_compute_effect_materials(provider~))
  } else {
    None
  }
  let dispatch = match effect_pair {
    Some((materials, caller)) =>
      @host.prepare_client_effect_source_dispatch(
        materials.allowed,
        materials.run_definition,
        caller,
        1,
        "actual-producer",
        selected,
      ).unwrap()
    None =>
      @host.prepare_client_task_dispatch(
        prepared,
        compilation,
        materials.admission,
        definition,
        caller,
        0,
        1,
        "actual-producer",
        selected,
      ).unwrap()
  }
  let binding = match effect_pair {
    Some(pair) =>
      @host.prepare_client_effect_source_input_binding(
        pair.0.compilation,
        request=if completion_free { Some(pair.1) } else { None },
      ).unwrap()
    None => @host.prepare_client_task_input_binding(prepared, 0).unwrap()
  }
  let (bundles, active, journal) = retained_runtime_owners(
    sqlite, site, root_path, name,
  )
  let execution : @resident.ResidentExecution = {
    site,
    active_runtime: active,
    operation_capability_cid: selected.grant_cid,
    issuer_capability_cid: selected.evidence_issuer_capability_cid,
    bundles,
    budgets: [budget],
    installed_contracts: configuration.installed_contracts,
    values_body: configuration.values_body,
    fixed_ms: 1L,
    per_row_ms: 0L,
    per_wire_byte_ms: 0L,
    per_pair_ms: 0L,
    limits: {
      finalization_quantum: 256,
      max_finalization_rounds: 100,
      row_decode: retained_compute_input_limits().wire,
      bridge_max_entries: 100,
      bridge_max_name_bytes: 10000,
      output: {
        output_export: resident_compute_limits(),
        max_manifest_bytes: 4096,
        max_retained_bytes: 1048576L,
      },
    },
    source: Some(source),
  }
  let acquisitions = Ref(0)
  let captures = Ref(0)
  let entries = Ref(0)
  if !effect {
    assert_true(
      @resident.install_resident_acquisition_task_executor(
        materials,
        compilation,
        binding,
        dispatch,
        execution,
        { ..source, source_ref: "connector://another/source#v", },
        () => "2026-10-05T00:00:00.000Z",
      )
      is Err(@resident.ForeignInput),
    )
  }
  let (effect_environment, effect_environment_cid, effect_document) = if provider {
    resident_provider_environment()
  } else {
    (
      resident_effect_source_environment, resident_effect_source_bundle_cid, resident_native_effect_document,
    )
  }
  let environment = @host.admit_client_check_environment(
    effect_environment,
    effect_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let wire = match effect_pair {
    Some(_) if finite is Some(value) => value.2
    Some(pair) =>
      @host.issue_client_effect_run_materials(
        pair.0.allowed,
        pair.0.run_definition,
        environment,
        effect_environment,
        effect_document,
        None,
        retained_compute_effect_limits(),
        request=pair.0.request,
      ).unwrap()
    None =>
      @host.issue_client_task_run_materials(
        prepared,
        compilation,
        materials.admission,
        definition,
        environment,
        resident_effect_source_environment,
        document,
        None,
      ).unwrap()
  }
  let envelope = @remote.remote_poll_dispatch_materials_json(
    dispatch, binding, wire,
  ).unwrap()
  if !parent_ack_failure {
    journal.retain_dispatch_envelope(dispatch, envelope).unwrap()
    journal.accept(dispatch).unwrap() |> ignore
  }
  let admission : @resident.ResidentRunAdmission = {
    source: Some((source.source_ref, source.source_contract_cid)),
    expressions: { text_time: false, veca: false, },
    operations: {
      rela: true,
      sga: false,
      tea: false,
      calendar: false,
      text_rank: false,
    },
    manifests: @host.admit_client_compilation_manifests(
      @environment.compiler_grammar_manifest_wire(),
      @environment.compiler_barrier_contract_manifest_wire(),
      10000,
      1000,
      20,
    ).unwrap(),
    limits: {
      preparation: @host.client_standard_program_preparation_limits(),
      sequence: @host.client_standard_values_sequence_limits(),
      max_sequence_steps: 1000,
      max_sequence_work: 1000,
      max_evidence_bytes: 1000000,
      max_evidence_nodes: 100000,
      max_evidence_depth: 100,
    },
  }
  let allow_effect_cleanup = Ref(!fail_effect_capture_cleanup)
  let original_effect_source : Ref[@resident.ResidentSourceCompute?] = Ref(None)
  let original_effect_producer : Ref[@resident.ResidentEffectProducerExecuted?] = Ref(
    None,
  )
  let (runtime, completion) = if effect {
    let delegations = Ref(0)
    let clocks = Ref(0)
    let delegation : @resident_protocol.ResidentSiteDelegation = {
      coordinator_authority: retained_compute_cid("c"),
      site_key: selected.site_key,
      runtime_bundle_cid: selected.runtime_bundle_cid,
      connector_registration: selected.connector_registration,
      connector_revision: selected.connector_revision,
      strategy_revision: selected.strategy_revision,
      grant_cid: selected.grant_cid,
      evidence_issuer_capability_cid: selected.evidence_issuer_capability_cid,
      budget_cids: [selected.budget_cid],
    }
    if parent_ack_failure {
      let http = @http.load_library(
        retained_runtime_required_env("ACTQL_TEST_NATIVE_HTTP_LIBRARY"),
      ).unwrap()
      // A real closed client deterministically refuses the HTTP ACK after
      // the existing SQLite journal has accepted the original envelope.
      let client = http
        .create_authenticated_client(
          root_path + "/unused-ca",
          @http.Bearer(root_path + "/unused-bearer"),
          4096L,
          100,
          100,
        )
        .unwrap()
      assert_true(client.close())
      let queue = @resident_protocol.ResidentAcceptedQueue::new(1).unwrap()
      let polled = @remote.admit_remote_poll_dispatch_json(envelope).unwrap()
      assert_true(
        @resident.resident_dispatch_execution_family(admission, polled)
        is Ok(@host.EffectComputation),
      )
      let offer = fn(generation : Int) {
        @resident.accept_resident_effect_source_dispatch(
          journal,
          client,
          "https://localhost/observations",
          delegation,
          generation,
          queue,
          admission,
          retained_compute_effect_limits(),
          polled,
          "2026-10-09T00:00:00.000Z",
          configuration.installed_contracts,
          configuration.values_body,
          configuration.source.fragment_contract_body,
        )
      }
      assert_true(offer(2) is Ok(@resident.Refused(_)))
      let attempt = @remote.dispatch_request_attempt_identity(dispatch).unwrap()
      assert_eq(journal.dispatch_envelope(attempt).unwrap(), None)
      assert_false(queue.contains(attempt))
      assert_true(
        offer(1) is Err(@resident.Host(@resident.Client(Http(@http.Closed)))),
      )
      let saved = journal.require(dispatch).unwrap()
      assert_true(@remote.dispatch_record_state(saved).0 is @remote.Accepted)
      assert_eq(journal.start_claimant(dispatch).unwrap(), None)
      assert_eq(journal.dispatch_envelope(attempt).unwrap(), Some(envelope))
      assert_false(queue.contains(attempt))
      assert_true(offer(1) is Err(_))
      assert_eq(
        @remote.dispatch_record_durable_json(journal.require(dispatch).unwrap()).unwrap(),
        @remote.dispatch_record_durable_json(saved).unwrap(),
      )
      assert_false(queue.contains(attempt))
      assert_eq(entries.val, 0)
      assert_eq(acquisitions.val, 0)
      assert_true(
        bundles
        .release(@bundle.native_active_runtime_process_hold_id(active))
        .unwrap(),
      )
      assert_true(journal.close())
      assert_true(bundles.close().unwrap())
      return
    }
    let outcome = @resident.execute_resident_effect_source_attempt(
      journal,
      execution,
      admission,
      retained_compute_effect_limits(),
      configuration,
      () => {
        delegations.val += 1
        if revoke_effect_at_start && delegations.val > 1 {
          { ..delegation, coordinator_authority: retained_compute_cid("0"), }
        } else {
          delegation
        }
      },
      @remote.dispatch_request_attempt_identity(dispatch).unwrap(),
      "original-effect-producer-holder",
      () => {
        clocks.val += 1
        if expire_effect_before_start ||
          (expire_effect_at_start && clocks.val > 1) {
          "2099-01-01T00:00:00.000Z"
        } else {
          "2026-10-09T00:00:00.000Z"
        }
      },
      Some(_ => {
        entries.val += 1
        true
      }),
      source_observe=event => {
        match event {
          AcquisitionEntered => acquisitions.val += 1
          ProducerCaptured => {
            captures.val += 1
            if fail_effect_capture_cleanup {
              return false
            }
          }
          CleanupCompleted => return allow_effect_cleanup.val
          _ => ()
        }
        true
      },
    )
    if fail_effect_capture_cleanup {
      guard outcome is Err(failure) else {
        fail("unrecorded capture completed")
      }
      assert_true(
        failure.issue
        is @resident.Compute(
          @resident.ObservationUnrecorded(@resident.ProducerCaptured)
        ),
      )
      assert_true(failure.cleanup_issue is Some(_))
      guard failure.pending_runtime is Some(owner) else {
        fail("pending cleanup Owner was lost")
      }
      assert_eq(entries.val, 1)
      assert_eq(acquisitions.val, 1)
      assert_eq(captures.val, 1)
      assert_true(owner.close() is Err(_))
      let (_, _, cleanup, _, _) = @remote.dispatch_record_state(
        journal.require(dispatch).unwrap(),
      )
      assert_false(cleanup is @remote.CleanupReleased)
      assert_true(owner.retains_dispatch_resources())
      allow_effect_cleanup.val = true
      assert_true(owner.close().unwrap())
      assert_false(owner.close().unwrap())
      let (_, _, cleanup, _, _) = @remote.dispatch_record_state(
        journal.require(dispatch).unwrap(),
      )
      assert_true(cleanup is @remote.CleanupReleased)
      assert_eq(acquisitions.val, 1)
      assert_eq(entries.val, 1)
      for index in [2, 3, 4, 5, 6, 7, 8] {
        assert_eq(@site.site_status(site)[index], 0L)
      }
      assert_true(journal.close())
      assert_true(bundles.close().unwrap())
      return
    }
    if revoke_effect_at_start ||
      expire_effect_at_start ||
      expire_effect_before_start {
      guard outcome is Err(failure) else {
        fail("expired/revoked producer executed")
      }
      assert_true(
        failure.issue
        is @resident.Host(
          @resident.Runtime(@runtime.StartAuthorizationRejected)
        ),
      )
      assert_true(failure.pending_runtime is None)
      assert_eq(entries.val, 0)
      assert_eq(acquisitions.val, 0)
      assert_eq(captures.val, 0)
      let (_, _, cleanup, _, _) = @remote.dispatch_record_state(
        journal.require(dispatch).unwrap(),
      )
      assert_true(cleanup is @remote.CleanupReleased)
      for index in [2, 3, 4, 5, 6, 7, 8] {
        assert_eq(@site.site_status(site)[index], 0L)
      }
      assert_true(journal.close())
      assert_true(bundles.close().unwrap())
      return
    }
    let owned = match outcome {
      Ok(value) => value
      Err(failure) => {
        // Preserve the original failure/custody classification in a failed
        // fixture instead of aborting before the typed boundary is observable.
        // This diagnostic neither retries the attempt nor confirms cleanup.
        let boundary = match failure.issue {
          @resident.Dispatch(@resident.Materials(_)) => "dispatch-materials"
          @resident.Dispatch(@resident.Dispatch(_)) => "dispatch-binding"
          @resident.Dispatch(@resident.Source(_)) => "dispatch-source"
          @resident.Dispatch(@resident.Refused(_)) => "dispatch-refused"
          @resident.Host(@resident.Runtime(issue)) =>
            match issue {
              Closed => "runtime-closed"
              InvalidConfiguration => "runtime-configuration"
              RegistrationCollision => "runtime-registration"
              RuntimeUnsupported => "runtime-unsupported"
              BudgetUnsupported => "runtime-budget"
              SiteUnavailable => "runtime-site"
              CapacityRejected => "runtime-capacity"
              AcceptanceUnconfirmed => "runtime-acceptance"
              DispatchAlreadyStarted => "runtime-already-started"
              OperationRejected => "runtime-operation"
              HoldingRejected => "runtime-holding"
              SettlementRejected => "runtime-settlement"
              CustodyRejected => "runtime-custody"
              OutputRejected => "runtime-output"
              OutputReaderUnavailable => "runtime-reader-unavailable"
              OutputReaderClosed => "runtime-reader-closed"
              OutputReaderIncomplete => "runtime-reader-incomplete"
              OutputReaderChunkExceeded => "runtime-reader-chunk"
              OutputReaderPhysical(_) => "runtime-reader-physical"
              Physical(_) => "runtime-physical"
              ExecutorEntryUnrecorded => "runtime-entry-unrecorded"
              StartAuthorizationRejected => "runtime-authorization"
              StartClaimLost(_) => "runtime-claim-lost"
              StartCancelled => "runtime-cancelled"
              CleanupPending(_) => "runtime-cleanup"
              CompletedRestorationPending => "runtime-restoration"
              CompletedMaterialUnavailable(_) => "runtime-material"
              Protocol(_) => "runtime-protocol"
              Journal(_) => "runtime-journal"
              Bundle(_) => "runtime-bundle"
            }
          @resident.Host(@resident.Source(_)) => "host-source"
          @resident.Host(_) => "host"
          @resident.Compute(@resident.Source(@resident.Acquisition(issue))) =>
            match issue {
              @local.InvalidSource => "compute-source-invalid-source"
              @local.InvalidContracts => "compute-source-contracts"
              @local.Preparation => "compute-source-sql-preparation"
              @local.Registration => "compute-source-registration"
              @local.Candidate => "compute-source-candidate"
              @local.Selection => "compute-source-selection"
            }
          @resident.Compute(@resident.Source(@resident.Query(_))) =>
            "compute-source-query"
          @resident.Compute(@resident.Source(@resident.Binding(_))) =>
            "compute-source-binding"
          @resident.Compute(@resident.Source(@resident.ForeignInput)) =>
            "compute-source-foreign-input"
          @resident.Compute(@resident.Source(_)) => "compute-source"
          @resident.Compute(@resident.UnsupportedGraph) => "compute-graph"
          @resident.Compute(@resident.Capacity(_)) => "compute-capacity"
          @resident.Compute(@resident.Acquisition(_)) => "compute-acquisition"
          @resident.Compute(@resident.Execution(_)) => "compute-execution"
          @resident.Compute(@resident.ForeignEffectMaterials) =>
            "compute-original-materials"
          @resident.Compute(@resident.EffectRun(_)) => "compute-effect-run"
          @resident.Compute(@resident.EffectInput(_)) => "compute-effect-input"
          @resident.Compute(_) => "compute-post-acquisition"
          @resident.NotStartable(_) => "not-startable"
        }
        println(
          "original-effect-producer-failure: " +
          boundary +
          "; pending-runtime=" +
          (failure.pending_runtime is Some(_)).to_string() +
          "; cleanup-issue=" +
          (failure.cleanup_issue is Some(_)).to_string() +
          "; acquisitions=" +
          acquisitions.val.to_string() +
          "; captures=" +
          captures.val.to_string(),
        )
        fail("Original Effect producer failed at " + boundary)
      }
    }
    let capture_materials = owned.materials_for_capture(journal).unwrap()
    if completion_free {
      assert_eq(capture_materials.request, effect_pair.unwrap().0.request)
      let original_normalization = @host.restore_client_effect_run_normalization(
        capture_materials,
      ).unwrap()
      assert_eq(
        @publication.run_evidence_value_identity(original_normalization),
        "sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087",
      )
      assert_eq(
        journal
        .dispatch_envelope(
          @remote.dispatch_request_attempt_identity(dispatch).unwrap(),
        )
        .unwrap(),
        Some(envelope),
      )
    }
    let captured = @strategy.pin_captured_effect_acquired_unit_results(
      owned.source.effect_run().unwrap(),
      0,
      4,
    ).unwrap()
    assert_true(
      @strategy.captured_effect_local_unit_inputs_match_computation(
        captured,
        @host.prepared_client_effect_computation_graph(
          capture_materials.prepared,
        ),
      ),
    )
    // Equal wire reconstructed by a different owner cannot replace the exact
    // preparation context retained by the actual acquisition Runtime.
    assert_false(
      @strategy.captured_effect_local_unit_inputs_match_computation(
        captured,
        @host.prepared_client_effect_computation_graph(
          effect_pair.unwrap().0.prepared,
        ),
      ),
    )
    assert_eq(
      @publication.publication_contract_identity(
        capture_materials.run_definition,
      ),
      @remote.dispatch_request_task_scope(dispatch).0,
    )
    assert_true(@strategy.release_captured_effect_local_unit_inputs(captured))
    assert_true(
      physical_equal(owned.source_for_capture(journal).unwrap(), owned.source),
    )
    let foreign_journal = @dispatch_journal.open_journal(
      sqlite,
      root_path + "/" + name + ".foreign-capture.sqlite",
      1048576L,
      @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap(),
    ).unwrap()
    assert_true(owned.source_for_capture(foreign_journal) is None)
    assert_true(owned.materials_for_capture(foreign_journal) is None)
    assert_true(
      owned.invocation_for_capture(foreign_journal, 65536, 4096, 64)
      is Err(Unavailable),
    )
    assert_true(foreign_journal.close())
    original_effect_source.val = Some(owned.source)
    original_effect_producer.val = Some(owned)
    assert_eq(owned.executed.result_definition_cid, None)
    assert_true(owned.source.usage().held_bytes > 0L)
    let original_record = journal.require(dispatch).unwrap()
    let replay = @resident.execute_resident_effect_source_attempt(
      journal,
      execution,
      admission,
      retained_compute_effect_limits(),
      configuration,
      () => delegation,
      @remote.dispatch_request_attempt_identity(dispatch).unwrap(),
      "replacement-effect-producer-holder",
      () => "2026-10-09T00:00:00.000Z",
      Some(_ => {
        entries.val += 1
        true
      }),
    )
    guard replay is Err(refusal) else {
      fail("a second producer owner was installed")
    }
    assert_true(refusal.issue is @resident.NotStartable(_))
    assert_true(refusal.pending_runtime is None)
    assert_eq(
      @remote.dispatch_record_revision(journal.require(dispatch).unwrap()),
      @remote.dispatch_record_revision(original_record),
    )
    assert_true(owned.source.usage().held_bytes > 0L)
    assert_eq(acquisitions.val, 1)
    assert_eq(entries.val, 1)
    (owned.executed.runtime, owned.executed.completion)
  } else if through_resident {
    let executed = match
      @resident.execute_resident_attempt(
        journal,
        execution,
        admission,
        @remote.dispatch_request_attempt_identity(dispatch).unwrap(),
        "original-producer-holder",
        () => "2026-10-05T00:00:00.000Z",
        Some(_ => {
          entries.val += 1
          true
        }),
        source_observe=event => {
          match event {
            AcquisitionEntered => acquisitions.val += 1
            ProducerCaptured => captures.val += 1
            _ => ()
          }
          true
        },
      ) {
      Ok(value) => value
      Err(failure) =>
        // Keep the typed cause visible; this is not an accepted refusal test.
        match failure.issue {
          Source(UnsupportedSource) =>
            abort("ordinary resident producer remained unsupported")
          Source(ForeignInput) =>
            abort("ordinary resident producer input was foreign")
          Runtime(Physical(code)) =>
            abort("ordinary resident producer physical failure: " + code)
          _ => abort("ordinary resident producer failed before completion")
        }
    }
    assert_eq(executed.result_definition_cid, None)
    (executed.runtime, executed.completion)
  } else {
    let executor = @resident.install_resident_acquisition_task_executor(
      materials,
      compilation,
      binding,
      dispatch,
      execution,
      source,
      () => "2026-10-05T00:00:00.000Z",
      observe=event => {
        match event {
          AcquisitionEntered => acquisitions.val += 1
          ProducerCaptured => captures.val += 1
          _ => ()
        }
        true
      },
    ).unwrap()
    assert_eq(acquisitions.val, 0)
    let runtime = @output.open_native_remote_standard_site_runtime(
      site,
      active,
      execution.operation_capability_cid,
      execution.issuer_capability_cid,
      [executor],
      journal,
      bundles,
      [budget],
    ).unwrap()
    runtime
    .guard_executor_start(() => {
      @resident_protocol.check_resident_materials_current(
        materials, "2026-10-05T00:00:00.000Z",
      )
      is Ok(_)
    })
    .unwrap()
    runtime.claim_starts_as("original-producer-holder").unwrap()
    runtime
    .observe_executor_entry(_ => {
      entries.val += 1
      true
    })
    .unwrap()
    let completion = runtime.start(dispatch, binding).unwrap()
    (runtime, completion)
  }
  assert_eq(entries.val, 1)
  assert_eq(acquisitions.val, 1)
  assert_eq(captures.val, 1)
  assert_eq(
    runtime.start(dispatch, binding).unwrap().evidence_cid,
    completion.evidence_cid,
  )
  assert_eq(acquisitions.val, 1)
  let observed = journal.observation(dispatch).unwrap()
  assert_true(
    @dispatch_journal.recovered_site_dispatch_source_observation(observed)
    is Some(_),
  )
  let evidence = @dispatch_journal.recovered_site_dispatch_evidence(observed).unwrap()
  let subject = @dispatch_journal.recovered_site_dispatch_subject(observed).unwrap()
  let edge = match effect_pair {
    Some(pair) =>
      @host.prepare_client_effect_retained_input_edge(
        pair.0.allowed,
        pair.0.run_definition,
      ).unwrap()
    None =>
      @host.prepare_client_retained_input_edge(
        prepared,
        compilation,
        materials.admission,
        definition,
        1,
        0,
      ).unwrap()
  }
  let producer = @host.prepare_client_retained_input_producer(
    edge,
    journal.require(dispatch).unwrap(),
    evidence,
    subject,
  ).unwrap()
  assert_true(@host.client_retained_input_producer_available(producer))
  let fields = @remote.remote_managed_output_subject_projection(subject)
  let facts = runtime.inspect_output_facts(dispatch, fields[1]).unwrap()
  assert_eq(facts.row_count, 3)
  assert_eq(
    facts.result_schema_cid,
    "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513",
  )
  if through_consumer {
    acquisition_runtime_transfer_consumer(
      materials,
      admission,
      configuration,
      compilation,
      caller,
      selected,
      runtime,
      journal,
      dispatch,
      producer,
      fields[1],
      site,
      sqlite,
      root_path,
      name,
      effect_pair~,
      effect_producer=original_effect_producer.val,
      provider~,
      completion_free_review~,
      mapped_create_write~,
      through_consumer_holder~,
      cancel_consumer_before_start~,
      cancel_consumer_after_borrow~,
      consumer_output_unavailable~,
      cancel_receiver~,
      deny_after_admission~,
      consumer_start_expiry~,
      producer_cleanup_at_handoff~,
      cleanup_after_preparation~,
      cancel_producer_before_handoff~,
      chain_context=if chain {
        Some({ caller, selected, cancel_tail: cancel_chain_tail, })
      } else {
        None
      },
    )
    assert_eq(
      @host.client_retained_input_producer_available(producer),
      !producer_cleanup_at_handoff,
    )
    assert_eq(acquisitions.val, 1)
    assert_eq(captures.val, 1)
    assert_eq(entries.val, 1)
  }
  if !producer_cleanup_at_handoff {
    let reader = runtime.open_output_reader(dispatch, fields[1], 128).unwrap()
    assert_false(runtime.release(dispatch).unwrap())
    let bytes : Array[Byte] = []
    while true {
      let chunk = reader.next().unwrap()
      for byte in chunk.bytes {
        bytes.push(byte)
      }
      if chunk.eof {
        break
      }
    }
    // Database insertion order is 3, 1, 2; the read-only acquisition preserves
    // that source order. The consumer's later filter yields only id 3.
    assert_eq(
      @utf8.decode(Bytes::from_array(bytes)),
      "[{\"id\":3},{\"id\":1},{\"id\":2}]",
    )
    assert_true(reader.finish().unwrap())
    assert_true(runtime.release(dispatch).unwrap())
    assert_false(runtime.release(dispatch).unwrap())
  }
  assert_false(@host.client_retained_input_producer_available(producer))
  let (_, _, cleanup, _, _) = @remote.dispatch_record_state(
    journal.require(dispatch).unwrap(),
  )
  assert_true(cleanup is @remote.CleanupReleased)
  assert_false(runtime.retains_dispatch_resources())
  for index in [2, 4, 6, 7, 8] {
    assert_eq(@site.site_status(site)[index], 0L)
  }
  assert_eq(acquisitions.val, 1)
  assert_eq(entries.val, 1)
  if chain {
    for index in [3, 5] {
      assert_eq(@site.site_status(site)[index], 0L)
    }
  }
  if original_effect_source.val is Some(original) {
    assert_eq(original.usage().held_bytes, 0L)
    assert_eq(original.usage().reserved_execution_bytes, 0L)
    assert_true(original.close())
  }
  if original_effect_producer.val is Some(original) {
    assert_true(original.materials_for_capture(journal) is None)
    assert_true(
      original.invocation_for_capture(journal, 65536, 4096, 64)
      is Err(Unavailable),
    )
  }
  assert_true(runtime.close().unwrap())
  assert_true(journal.close())
  assert_true(bundles.close().unwrap())
}

///|
test "original Source task completes through Runtime without a producer Named Result" {
  acquisition_runtime_case(false)
}

///|
test "actual producer Runtime bytes reach the original retained consumer without Source reacquisition" {
  acquisition_runtime_case(true)
}

///|
test "ordinary resident holder executes the original internal Source producer once" {
  acquisition_runtime_case(false, through_resident=true)
}

///|
test "ordinary resident producer bytes transfer to the original consumer without reacquisition" {
  acquisition_runtime_case(true, through_resident=true)
}

///|
test "resident producer keeps its Source while partial receiver handoff cancels and reclaims" {
  acquisition_runtime_case(true, through_resident=true, cancel_receiver=true)
}

///|
test "resident retained handoff rechecks grants after receiver admission before payload write" {
  acquisition_runtime_case(
    true,
    through_resident=true,
    deny_after_admission=true,
  )
}

///|
test "resident consumer expiry at the exclusive start boundary keeps caller borrow for cleanup" {
  acquisition_runtime_case(
    true,
    through_resident=true,
    consumer_start_expiry=true,
  )
}

///|
test "retained plan handoff refuses producer cleanup during admission before receiver IO" {
  acquisition_runtime_case(
    true,
    through_resident=true,
    producer_cleanup_at_handoff=true,
  )
}

///|
test "retained plan physical advance refuses producer cleanup during authorization before receiver IO" {
  acquisition_runtime_case(
    true,
    through_resident=true,
    producer_cleanup_at_handoff=true,
    cleanup_after_preparation=true,
  )
}

///|
test "durable producer cancellation withholds retained handoff before consumer start" {
  acquisition_runtime_case(
    true,
    through_resident=true,
    cancel_producer_before_handoff=true,
  )
}

///|
test "original producer holder owns one consumer borrow through formal cleanup" {
  acquisition_runtime_case(
    true,
    through_resident=true,
    through_consumer_holder=true,
  )
}

///|
test "producer holder retains independent holdings when consumer is cancelled before its start" {
  acquisition_runtime_case(
    true,
    through_resident=true,
    through_consumer_holder=true,
    cancel_consumer_before_start=true,
  )
}

///|
test "producer holder keeps cleanup after consumer output storage failure" {
  acquisition_runtime_case(
    true,
    through_resident=true,
    through_consumer_holder=true,
    consumer_output_unavailable=true,
  )
}

///|
test "producer holder returns a borrowed consumer cancelled before its exclusive start" {
  acquisition_runtime_case(
    true,
    through_resident=true,
    through_consumer_holder=true,
    cancel_consumer_after_borrow=true,
  )
}

///|
test "Effect original Source producer completes through saved journal and Runtime once" {
  acquisition_runtime_case(false, effect=true)
}

///|
test "Effect original Source producer refuses revoked delegation at exclusive start before IO" {
  acquisition_runtime_case(false, effect=true, revoke_effect_at_start=true)
}

///|
test "Effect original Source producer refuses original deadline at exclusive start before IO" {
  acquisition_runtime_case(false, effect=true, expire_effect_at_start=true)
}

///|
test "Effect original Source producer settles an already expired accepted envelope without IO" {
  acquisition_runtime_case(false, effect=true, expire_effect_before_start=true)
}

///|
test "Effect original Source producer preserves primary and cleanup failure until the same Runtime retries" {
  acquisition_runtime_case(false, effect=true, fail_effect_capture_cleanup=true)
}

///|
test "Effect actual producer bytes transfer to saved consumer without Source reacquisition" {
  acquisition_runtime_case(true, effect=true)
}

///|
test "Effect actual producer keeps Source custody when partial receiver holding is cancelled" {
  acquisition_runtime_case(true, effect=true, cancel_receiver=true)
}

///|
test "Effect actual producer handoff rechecks authority after receiver admission before bytes" {
  acquisition_runtime_case(true, effect=true, deny_after_admission=true)
}

///|
test "Effect actual producer cancellation withholds transfer while preserving completed Source custody" {
  acquisition_runtime_case(
    true,
    effect=true,
    cancel_producer_before_handoff=true,
  )
}

///|
test "Effect consumer holder owns one borrow and separate receiver cleanup" {
  acquisition_runtime_case(true, effect=true, through_consumer_holder=true)
}

///|
test "Effect consumer holder cancellation before start retains independent cleanup" {
  acquisition_runtime_case(
    true,
    effect=true,
    through_consumer_holder=true,
    cancel_consumer_before_start=true,
  )
}

///|
test "Effect consumer holder cancellation after borrow prevents exclusive start" {
  acquisition_runtime_case(
    true,
    effect=true,
    through_consumer_holder=true,
    cancel_consumer_after_borrow=true,
  )
}

///|
test "Effect consumer holder output failure does not acquire input or execute twice" {
  acquisition_runtime_case(
    true,
    effect=true,
    through_consumer_holder=true,
    consumer_output_unavailable=true,
  )
}

///|
test "Effect poll admission keeps durable original intent after ACK failure without queuing execution" {
  acquisition_runtime_case(false, effect=true, parent_ack_failure=true)
}

///|
test "Effect original holders retain physical Provider review and Checkpoint without reacquisition" {
  acquisition_runtime_case(
    true,
    effect=true,
    provider=true,
    through_consumer_holder=true,
  )
}

///|
test "completion-free original materials execute the physical Source producer once" {
  acquisition_runtime_case(false, effect=true, completion_free=true)
}

///|
test "original completion-free Source and consumer persist mapped-create review through Store loss and cleanup retry" {
  native_mapped_create_phase("case-entered")
  println("native-mapped-create: entering actual acquisition harness")
  acquisition_runtime_case(
    true,
    effect=true,
    completion_free=true,
    completion_free_review=true,
    through_consumer_holder=true,
  )
  native_mapped_create_phase("harness-cleanup-confirmed")
}

///|
test "original completion-free mapped-create approval retains one physical write through response custody loss" {
  acquisition_runtime_case(
    true,
    effect=true,
    completion_free=true,
    completion_free_review=true,
    mapped_create_write=true,
    through_consumer_holder=true,
  )
}
