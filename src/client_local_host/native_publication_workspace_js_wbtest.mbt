///|
// Existing observed JSON Request preparation and explicit selected row profile.
// No Native Host, Account, Store, durable Run or physical backing is supplied.
fn native_publication_workspace_fixture(
  rows : Int,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
) raise {
  let document = request_native_numeric_public_program(rows)
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_native_intake_wire(
    parent,
    input,
    document.length() * 6 + 4096,
  ).unwrap()
  let wire = request_numeric_local_environment(
    @publication_host.client_local_product_assets().environment,
    rows,
  )
  let environment = @publication_host.admit_client_check_environment(
    wire,
    request_numeric_environment_cid(wire),
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let writer = @encode.writer(document.length() * 6 + 1024, 4, 2)
  @encode.string_value(writer, document)
  let intent = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"text\":" +
    @encode.finish(writer) +
    ",\"format\":\"json\"},\"parameters\":null}",
    document.length() * 6 + 1024,
    8192,
    64,
  ).unwrap()
  finish_request_native_intake_wire(parent, input, intent).unwrap()
  retain_request_submitted_intent(parent, input, intent).unwrap()
  reserve_request_retained_intent_source(parent, input).unwrap() |> ignore
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "json"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  finish_request_checked_computation(parent, input, environment, publication).unwrap()
  |> ignore
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=request_program_compilation_limits(parent, input).unwrap(),
    retained_output=false,
    provider_factory=_ => [],
  ).unwrap()
  (parent, input, parent.compiled_program.unwrap())
}

///|
fn native_publication_workspace_component(
  rows : Int,
  check_legacy : Bool,
  snapshot? : Bool = false,
  chain? : Bool = false,
) -> Unit raise {
  let (parent, _input, prepared) = native_publication_workspace_fixture(rows)
  let assets = @publication_host.client_local_product_assets()
  let contracts = parent.program_source_free.unwrap().installed_contracts
  let requirements = prepare_source_free_local_requirements(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let before = requirements.maximum_limits()
  let (bridge_entries, evidence_entries) = requirements
    .publication_entry_limits(prepared)
    .unwrap()
  assert_eq(bridge_entries, 10000)
  assert_eq(evidence_entries, 10000)
  let (row_limits, limits) = requirements
    .publication_limits(prepared, 16777216)
    .unwrap()
  assert_true(limits.max_result_workspace_entries >= rows)
  assert_eq(requirements.maximum_limits(), before)
  // Use the existing prepared managed route selected by the ordinary caller;
  // the legacy raw Host would retain another output allowance alongside this
  // live Request. No policy increase or separate Ledger repairs that mismatch.
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "publication-workspace-component",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  let mut original_compilation : @publication_host.ClientCompiledRun? = None
  let mut original_observation : @publication.RunEvidenceValue? = None
  if snapshot {
    let plan = run.source_free_preparation.unwrap()
    let compiled = match plan.compilation.unwrap() {
      @publication_host.Values(artifact) =>
        @publication_host.issue_client_values_compiled_run(
          prepared,
          artifact,
          "sha256:" + "a".repeat(64),
          "sha256:" + "b".repeat(64),
          "2099-01-01T00:00:00.000Z",
        ).unwrap()
      @publication_host.Tasks(artifact) =>
        @publication_host.issue_client_task_compiled_run(
          prepared,
          artifact,
          "sha256:" + "a".repeat(64),
          "sha256:" + "b".repeat(64),
          "2099-01-01T00:00:00.000Z",
        ).unwrap()
      _ => fail("pure original compilation required")
    }
    original_compilation = Some(compiled)
    let definition = @publication_host.issue_client_compiled_run_definition(
      compiled, "snapshot-component", "publication-workspace-component", "2026-10-30T00:00:00.000Z",
      "2099-01-01T00:00:00.000Z",
    ).unwrap()
    let (observation, _) = issue_program_publication_invocation(
      run, prepared, compiled, definition, "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
      65536, 8192, 64,
    ).unwrap()
    original_observation = Some(observation)
  }
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      false,
    )
    .unwrap()
    .unwrap()
  let execution = match
    execute_source_free_local_tasks_guarded(
      setup,
      256,
      requirements.finalization_round_limit(prepared).unwrap(),
      () => true,
    ) {
    Ok(value) => value
    Err(failure) => {
      let issue = local_values_execution_failure_issue(failure)
      retry_local_values_execution_failure_cleanup(failure) |> ignore
      retire_installed_managed_run(run) |> ignore
      let detail = match issue {
        InvalidLimits => "InvalidLimits"
        Fenced => "Fenced"
        UnsupportedGraph => "UnsupportedGraph"
        MissingLocalModule => "MissingLocalModule"
        FinalizationLimit => "FinalizationLimit"
        MissingOutput => "MissingOutput"
        Estimate(_) => "Estimate"
        Driver(original) =>
          match original {
            Configuration(InvalidLimits) => "Driver.Configuration.InvalidLimits"
            Configuration(LogicalIdentityUnsupported) =>
              "Driver.Configuration.LogicalIdentityUnsupported"
            Configuration(ComputeUnsupported) =>
              "Driver.Configuration.ComputeUnsupported"
            ManagedValues(Guard(_)) => "Driver.ManagedValues.Guard"
            ManagedValues(Admission(_)) => "Driver.ManagedValues.Admission"
            IdentityExport(ResultView(Limit)) =>
              "Driver.IdentityExport.ResultView.Limit"
            Execution(Physical(original)) =>
              "Driver.Execution.Physical." + @debug.to_string(original)
            Execution(ActivationNotAuthorized) =>
              "Driver.Execution.ActivationNotAuthorized"
            Execution(Compute(_)) => "Driver.Execution.Compute"
            Execution(_) => "Driver.Execution.Other"
            _ => "Driver.Other"
          }
      }
      fail("Component completed-output setup: " + detail)
    }
  }
  // The old, tighter request refuses the projection without revoking the
  // existing completed output. No business operation is replayed below.
  if check_legacy {
    let old = { ..limits, max_result_workspace_entries: evidence_entries, }
    assert_true(
      execution.prepare_result_export(0, row_limits, bridge_entries, 65536, old)
      is Err(
        Export(
          @publication_host.Output(@execution.ResultView(@execution.Limit))
        )
      ),
    )
  }
  let output = execution
    .prepare_result_export(0, row_limits, bridge_entries, 65536, limits)
    .unwrap()
  let stream = output.output_export()
  let mut streamed_bytes = 0
  while true {
    match stream.next() {
      Ok(Some(chunk)) => streamed_bytes += @utf8.encode(chunk).length()
      Ok(None) => break
      Err(issue) => {
        let cause = match issue {
          @publication_host.Output(
            @execution.Wire(@execution.Encoding(@encode.OutputLimit))
          ) => "Wire.Encoding.OutputLimit"
          @publication_host.Output(@execution.Wire(@execution.InvalidLimits)) =>
            "Wire.InvalidLimits"
          @publication_host.Output(@execution.ResultView(@execution.Limit)) =>
            "ResultView.Limit"
          _ => "OtherCompletedExport"
        }
        output.close()
        let closed = execution.close()
        retire_installed_managed_run(run) |> ignore
        fail(
          "Same completed-output stream: " +
          cause +
          "; emitted=" +
          streamed_bytes.to_string() +
          "; payload bytes/nodes=" +
          limits.payload_wire.max_bytes.to_string() +
          "/" +
          limits.payload_wire.max_nodes.to_string() +
          "; logical bytes/nodes=" +
          limits.logical_wire.max_bytes.to_string() +
          "/" +
          limits.logical_wire.max_nodes.to_string() +
          "; managed close=" +
          closed.to_string(),
        )
      }
    }
  }
  streamed_bytes += @utf8.encode(stream.finish().unwrap()).length()
  assert_eq(stream.row_count().unwrap(), rows)
  if !check_legacy {
    // Native persistence reopens the exact identified stream. This is a
    // second stream traversal, not re-execution or another submission.
    let replay = stream.replay().unwrap()
    let mut replayed_bytes = 0
    while replay.next().unwrap() is Some(chunk) {
      replayed_bytes += @utf8.encode(chunk).length()
    }
    replayed_bytes += @utf8.encode(replay.finish().unwrap()).length()
    assert_eq(replayed_bytes, streamed_bytes)
  }
  if snapshot {
    let publication = reserve_program_publication(run, prepared).unwrap()
    stream
    .issue_result_evidence(
      if chain {
        @publication.publication_contract_identity(
          @publication_host.client_compiled_run_plan(
            original_compilation.unwrap(),
          ),
        )
      } else {
        "sha256:" + "1".repeat(64)
      },
      [],
      @publication.publication_contract_identity(
        run.publication_definition.unwrap(),
      ),
      if chain {
        "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
      } else {
        "sha256:" + "4".repeat(64)
      },
      if chain {
        "sha256:" + "a".repeat(64)
      } else {
        "sha256:" + "5".repeat(64)
      },
      65536,
      8192,
      64,
    )
    .unwrap()
    |> ignore
    let retention = @publication.seal_publication_contract(
      "result_retention_policy",
      "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"sha256:" +
      "8".repeat(64) +
      "\",\"effective_data_policy_cid\":\"sha256:" +
      (if chain {
        "470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
      } else {
        "4".repeat(64)
      }) +
      "\",\"available_until\":\"2099-01-01T00:00:00.000Z\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"extension_ceiling_at\":\"2099-01-03T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:" +
      "9".repeat(64) +
      "\",\"metadata_delete_by\":\"2099-01-04T00:00:00.000Z\",\"clock_contract_cid\":\"sha256:" +
      "a".repeat(64) +
      "\"}",
      65536,
      8192,
      64,
    ).unwrap()
    let artifact = stream
      .issue_artifact(
        run.publication_invocation.unwrap(),
        retention,
        65536,
        8192,
        64,
      )
      .unwrap()
    // Metadata bounds are not a full-row snapshot allowance. Refusal leaves
    // the same identified original available to its funded continuation.
    assert_true(stream.admit_captured_snapshot(65536, 8192, 64) is Err(_))
    let cursor = match begin_program_snapshot(publication, stream) {
      Ok(value) => value
      Err(issue) => {
        let detail = match issue {
          ForeignOriginal => "ForeignOriginal"
          WrongPhase => "WrongPhase"
          Policy => "Policy"
          Capacity(_) => "Capacity"
          PublicationSnapshot(InvalidState) => "Snapshot.InvalidState"
          PublicationSnapshot(Output(_)) => "Snapshot.Output"
          _ => "Other"
        }
        fail("Original funded snapshot: " + detail)
      }
    }
    let mut done = false
    while !done {
      let (ready, work) = advance_program_snapshot(cursor, 256).unwrap()
      assert_true(work <= 256)
      done = ready
    }
    let captured = finish_program_snapshot(cursor).unwrap()
    assert_true(physical_equal(publication.completed_snapshots[0], captured))
    assert_true(begin_program_snapshot(publication, stream) is Err(WrongPhase))
    if chain {
      let compiled = original_compilation.unwrap()
      let definition = run.publication_definition.unwrap()
      let invocation = run.publication_invocation.unwrap()
      let observation = original_observation.unwrap()
      let result_definition = stream.definition().unwrap()
      let manifest = @publication.issue_result_manifest(
        definition,
        invocation,
        [result_definition],
        [artifact],
        65536,
        8192,
        64,
      ).unwrap()
      let normalization = @publication_host.issue_prepared_client_local_normalization(
        prepared,
      ).unwrap()
      let journal = @publication_host.prepared_client_local_normalization_evidence(
        prepared, normalization,
      ).unwrap()
      let receipt = @publication.issue_effect_free_run_receipt(
        @publication_host.client_compiled_run_admission(compiled),
        definition,
        invocation,
        observation,
        [result_definition],
        [artifact],
        manifest,
        journal,
        [],
        [],
        [],
        [],
        [],
        65536,
        8192,
        64,
      ).unwrap()
      let authoring = @publication.seal_run_evidence_value(
        "authoring_context",
        "{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"" +
        @publication_host.client_request_program_cid(request) +
        "\",\"annotations\":[]}",
        65536,
        8192,
        64,
      ).unwrap()
      let capture = prepare_program_capture(
        publication,
        definition,
        invocation,
        [result_definition],
        [artifact],
        manifest,
        receipt,
        [captured],
        authoring,
        [],
      ).unwrap()
      start_program_capture(capture).unwrap() |> ignore
      while !advance_program_capture(capture, 256).unwrap().0 {
        ()
      }
      let recorded = finish_program_capture(capture).unwrap()
      let check = @publication.start_effect_free_run_evidence_check(
        definition,
        invocation,
        [result_definition],
        [artifact],
        manifest,
        receipt,
        recorded,
        65536,
        8192,
        64,
        @publication.publication_evidence_workspace(8192),
      )
      let mut refused = false
      while !refused {
        match check.advance(256) {
          Ok((true, _)) =>
            fail("Metadata bounds unexpectedly covered full Effect context")
          Ok((false, _)) => ()
          Err(EvidenceEmbeddedIdentity("effect_context_cid")) => refused = true
          Err(_) => fail("Unrelated legacy full-context refusal")
        }
      }
      check.cancel()
      // Independently recheck the actual complete contract through the existing
      // measured Core plan, without reusing the capture issuer's completed fact.
      // This component control supplies no physical Host/Store grant.
      let independent = @publication.prepare_original_effect_free_chain_validation(
        definition,
        invocation,
        [result_definition],
        [artifact],
        manifest,
        receipt,
        recorded,
      ).unwrap()
      assert_eq(
        @publication.publication_validation_plan_reuses_capture(independent),
        Some(false),
      )
      let independent_check = @publication.start_planned_chain_validation(
        independent,
      ).unwrap()
      while !independent_check.advance(256).unwrap().0 {
        ()
      }
      independent_check.finish().unwrap()
      let validation = prepare_program_chain_validation(
        capture,
        definition,
        invocation,
        [result_definition],
        [artifact],
        manifest,
        receipt,
        recorded,
      ).unwrap()
      start_program_validation(validation).unwrap() |> ignore
      while !advance_program_validation(validation, 256).unwrap().0 {
        ()
      }
      finish_program_validation(validation).unwrap()
      // Durable-location facts below are synthetic component DATA, not a
      // physical payload/COMMIT/cleanup acknowledgement or a publication grant.
      let ordering = stream.ordering().unwrap()
      let derivation = stream.derivation().unwrap()
      let binding = @publication.issue_durable_result_binding(
        definition,
        result_definition,
        invocation,
        artifact,
        ordering,
        retention,
        stream.codec_contract_cid().unwrap(),
        stream.result_fields().unwrap(),
        stream.result_schema_wire().unwrap(),
        "sha256:" + "6".repeat(64),
        "sha256:" + "7".repeat(64),
        rows,
        stream.content_bytes().unwrap(),
        "0".repeat(64),
        65536,
        8192,
        64,
      ).unwrap()
      let request_contract = @publication.issue_publication_request(
        definition,
        [result_definition],
        "snapshot-component",
        "sha256:" + "a".repeat(64),
        "sha256:" + "8".repeat(64),
        "sha256:" + "7".repeat(64),
        "2026-10-30T00:00:00.000Z",
        65536,
        8192,
        64,
      ).unwrap()
      let attempt = @publication.issue_publication_attempt(
        request_contract,
        definition,
        "original-attempt",
        "sha256:" + "9".repeat(64),
        None,
        "2026-10-30T00:00:00.000Z",
        65536,
        8192,
        64,
      ).unwrap()
      let index = @publication.issue_public_index_entry(
        definition,
        invocation,
        manifest,
        receipt,
        recorded,
        [binding],
        request_contract,
        attempt,
        "2026-10-30T00:00:00.000Z",
        65536,
        8192,
        64,
      ).unwrap()
      check_program_commit_validation(
        capture,
        definition,
        invocation,
        [result_definition],
        [artifact],
        [derivation],
        [ordering],
        [retention],
        [binding],
        manifest,
        receipt,
        recorded,
        request_contract,
        attempt,
        index,
      ).unwrap()
      let foreign_attempt = @publication.issue_publication_attempt(
        request_contract,
        definition,
        "foreign-attempt",
        "sha256:" + "9".repeat(64),
        None,
        "2026-10-30T00:00:00.000Z",
        65536,
        8192,
        64,
      ).unwrap()
      assert_true(
        check_program_commit_validation(
          capture,
          definition,
          invocation,
          [result_definition],
          [artifact],
          [derivation],
          [ordering],
          [retention],
          [binding],
          manifest,
          receipt,
          recorded,
          request_contract,
          foreign_attempt,
          index,
        )
        is Err(Commit(_)),
      )
      assert_true(capture.validation is None)
    }
  }
  output.close()
  assert_true(execution.close())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Native publication row indices use original quoted workspace independently of evidence entries" {
  native_publication_workspace_component(20000, true)
}

///|
test "same original 100000 completed output streams under its unchanged publication plan" {
  native_publication_workspace_component(100000, false)
}

///|
test "Native publication phase entry bounds refuse foreign preparation without changing limits" {
  let prepared = source_free_requirements_prepared()
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let requirements = prepare_source_free_local_requirements(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let before = requirements.maximum_limits()
  assert_eq(
    requirements.publication_entry_limits(prepared),
    Some((10000, 10000)),
  )
  assert_true(
    requirements.publication_entry_limits(source_free_requirements_prepared())
    is None,
  )
  assert_eq(requirements.maximum_limits(), before)
}

///|
test "same original 100000 Result snapshot uses its funded continuation instead of metadata limits" {
  native_publication_workspace_component(100000, false, snapshot=true)
}

///|
test "original numeric publication snapshot capture and chain validation share exact compiled evidence" {
  native_publication_workspace_component(
    100000,
    false,
    snapshot=true,
    chain=true,
  )
}
