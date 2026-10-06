// Actual producer Runtime output, not a synthetic completion record. Public
// Cloud delivery remains separate acceptance. The optional consumer branch
// uses the exact Runtime manifest and bytes through an independent Transfer.

///|
fn acquisition_runtime_case(
  through_consumer : Bool,
  through_resident? : Bool = false,
  cancel_receiver? : Bool = false,
  deny_after_admission? : Bool = false,
  consumer_start_expiry? : Bool = false,
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
  let prepared = resident_compute_prepared()
  let configuration = resident_compute_configuration(library, path)
  let source = {
    ..configuration.source,
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
  let dispatch = @host.prepare_client_task_dispatch(
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
  let binding = @host.prepare_client_task_input_binding(prepared, 0).unwrap()
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
    registry_body: configuration.registry_body,
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
  let (runtime, completion) = if through_resident {
    let environment = @host.admit_client_check_environment(
      resident_effect_source_environment,
      "sha256:feb4443bd80a5e95c14e195113219eeb2e24bdd12e424d1ba00c1295f5c53554",
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    ).unwrap()
    let wire = @host.issue_client_task_run_materials(
      prepared,
      compilation,
      materials.admission,
      definition,
      environment,
      resident_effect_source_environment,
      resident_compute_document,
      None,
    ).unwrap()
    let envelope = @remote.remote_poll_dispatch_materials_json(
      dispatch, binding, wire,
    ).unwrap()
    journal.retain_dispatch_envelope(dispatch, envelope).unwrap()
    journal.accept(dispatch).unwrap() |> ignore
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
  let edge = @host.prepare_client_retained_input_edge(
    prepared,
    compilation,
    materials.admission,
    definition,
    1,
    0,
  ).unwrap()
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
      cancel_receiver~,
      deny_after_admission~,
      consumer_start_expiry~,
    )
    assert_true(@host.client_retained_input_producer_available(producer))
    assert_eq(acquisitions.val, 1)
    assert_eq(captures.val, 1)
    assert_eq(entries.val, 1)
  }
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
