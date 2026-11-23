///|
test "Relation Sample captures the exact installed Request and committed output" {
  collection_request_publication_case(
    1,
    false,
    simple=true,
    check_sample_start=true,
  )
}

///|
fn collection_sample_submission_reference(
  tag_digit : String,
) -> @publication_host.ClientSubmissionReferenceRecord {
  let epoch = @publication_host.admit_client_submission_epoch_token(
    "{\"version\":\"actql-submission-epoch/0.1\",\"authorityScopeCid\":\"sha256:" +
    "a".repeat(64) +
    "\",\"epochNonce\":\"" +
    "1".repeat(64) +
    "\",\"notBefore\":1,\"expiresAt\":2,\"authenticator\":\"" +
    tag_digit.repeat(64) +
    "\"}",
  ).unwrap()
  @publication_host.prepare_client_submission_reference_record(
    epoch, "sample-binding-fixture",
  ).unwrap()
}

///|
fn check_relation_sample_profile_on_collection(
  run : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  ledger : @resources.Ledger,
  original_reference : @publication_host.ClientSubmissionReferenceRecord,
) -> ClientCheckedRelationSampleProfile raise {
  let observation = prepare_installed_logical_observation(
    run, prepared, compiled, definition, 65536, 8192, 64,
  ).unwrap()
  let map = @publication.admit_interactive_run_evidence_value(
    "logical_map",
    observation.original.unwrap().map,
    65536,
    8192,
    64,
  ).unwrap()
  let seal = fn(name, body) {
    @publication.seal_run_evidence_value(name, body, 65536, 8192, 64).unwrap()
  }
  let profile_body =
    #|{"version":"actql-control-profile/0.1","execution":{"stop_on_entry":false,"default_until":"terminal","breakpoints":[],"guards":null},"retain":{"samples":{"strategy":"execution_prefix","capture_scope":"all_outputs","targets":[],"max_items":50,"max_bytes":"512","max_artifacts":1,"ttl_seconds":60,"required":true,"graph":{"max_nodes":0,"max_edges":0},"vectors":{"max_components_per_item":1}}}}
  let profile = seal("control_profile", profile_body)
  let plan_cid = @publication.publication_contract_identity(
    @publication_host.client_compiled_run_plan(compiled),
  )
  let profile_cid = @publication.run_evidence_value_identity(profile)
  let authority = @publication_host.client_request_authority_scope_cid(request)
  let fingerprint = @publication_host.client_request_intent_cid(request)
  let changed_reference = collection_sample_submission_reference("3")
  // The authenticator changes without changing the derived request ID.
  assert_true(
    @publication_host.client_submission_reference_matches_request(
      changed_reference, request,
    ),
  )
  let map_cid = @publication.run_evidence_value_identity(map)
  let definition_cid = @publication.publication_contract_identity(definition)
  let policy = "sha256:" + "d".repeat(64)
  guard @identity.object_field(observation.original.unwrap().map, "steps")
    is Some(@identity.Array(steps)) else {
    fail("the original Plan must project logical steps")
  }
  let outputs : Array[String] = []
  let mut first_output = None
  let mut port_count = 0
  for i in 0..<@identity.array_count(steps) {
    let step = @identity.array_at(steps, i).unwrap()
    guard @identity.object_field(step, "ports") is Some(@identity.Array(ports)) else {
      fail("actual original ports")
    }
    port_count += @identity.array_count(ports)
    for j in 0..<@identity.array_count(ports) {
      let port = @identity.array_at(ports, j).unwrap()
      if @identity.object_field(port, "role")
        is Some(@identity.String("output")) {
        guard @identity.object_field(port, "port_id")
          is Some(@identity.String(id)) else {
          fail("actual original port ID")
        }
        outputs.push("\"" + id + "\"")
        if first_output is None {
          first_output = Some(id)
        }
      }
    }
  }
  assert_false(outputs.is_empty())
  let max_nodes = 256
  let mut admitted = None
  for (complete, same_reference) in [(true, true), (false, true), (true, false)] {
    let reference = if same_reference {
      original_reference
    } else {
      changed_reference
    }
    let intent = seal(
      "control_request_intent",
      "{\"version\":\"actql-control-request-intent/0.1\",\"submission_ref\":" +
      @publication_host.client_submission_reference_record_wire(reference) +
      ",\"legacy_request_fingerprint_cid\":\"" +
      fingerprint +
      "\",\"requested_profile_cid\":\"" +
      profile_cid +
      "\",\"expected_plan_cid\":\"" +
      plan_cid +
      "\"}",
    )
    let intent_cid = @publication.run_evidence_value_identity(intent)
    let selected = if complete { outputs.join(",") } else { "" }
    let resolved = seal(
      "resolved_control_profile",
      "{\"version\":\"actql-resolved-control-profile/0.1\",\"requested_profile_cid\":\"" +
      profile_cid +
      "\",\"effective_profile_cid\":\"" +
      profile_cid +
      "\",\"compiled_plan_cid\":\"" +
      plan_cid +
      "\",\"logical_map_cid\":\"" +
      map_cid +
      "\",\"breakpoints\":[],\"sample_output_port_ids\":[" +
      selected +
      "]}",
    )
    let resolved_cid = @publication.run_evidence_value_identity(resolved)
    let admission = seal(
      "control_admission",
      "{\"version\":\"actql-control-admission/0.1\",\"request_intent_cid\":\"" +
      intent_cid +
      "\",\"run_ref\":{\"namespaceId\":\"collection-publication\",\"authorityScopeCid\":\"" +
      authority +
      "\",\"runDefinitionCid\":\"" +
      definition_cid +
      "\"},\"compiled_plan_cid\":\"" +
      plan_cid +
      "\",\"logical_map_cid\":\"" +
      map_cid +
      "\",\"resolved_profile_cid\":\"" +
      resolved_cid +
      "\",\"policy_revision_cid\":\"" +
      policy +
      "\"}",
    )
    let records : InstalledRelationSampleProfileEvidence = {
      intent,
      requested: profile,
      effective: profile,
      resolved,
      map,
      admission,
    }
    let before = @resources.ledger_usage(ledger).planning_work
    if complete && same_reference {
      let used = @resources.ledger_usage(ledger)
      let limits = @resources.ledger_limits(ledger)
      let entry_quote = 2464L +
        explanation_logical_map_scanner_bytes().unwrap() +
        installed_sample_profile_reference_bytes
      let blocker = @resources.reserve_capacity(
        ledger,
        limits.retained_bytes -
        used.held_bytes -
        used.reserved_retention_bytes -
        entry_quote +
        1L,
        0L,
      ).unwrap()
      assert_true(
        check_installed_relation_sample_profile(
          run, request, definition, observation, original_reference, records, 65536,
          max_nodes, 64,
        )
        is Err(SampleProfileCapacity(Resource(RetentionLimit))),
      )
      assert_eq(@resources.ledger_usage(ledger).planning_work, before)
      @resources.settle_capacity(ledger, blocker).unwrap()
    }
    let outcome = check_installed_relation_sample_profile(
      run, request, definition, observation, original_reference, records, 65536,
      max_nodes, 64,
    )
    if !same_reference {
      assert_true(outcome is Err(ForeignSampleProfile))
    } else if complete {
      outcome.unwrap() |> ignore
    } else {
      assert_true(
        outcome
        is Err(
          SampleProfileBinding(
            RunEvidenceReferenceMismatch("control_admission.sample_output")
          )
        ),
      )
    }
    let (_, resolved_nodes, _) = @publication.run_evidence_value_wire_usage(
      resolved,
    ).unwrap()
    // A foreign reference consumes only the fixed bounded reference visit.
    let expected = if same_reference {
      32 +
      2 * max_nodes +
      2 * (@identity.array_count(steps) + port_count) +
      resolved_nodes +
      (if complete { 2 * @identity.array_count(steps) } else { 0 })
    } else {
      32
    }
    assert_eq(@resources.ledger_usage(ledger).planning_work - before, expected)
    assert_false(observation.reading || run.source_free_opening)
    if complete && same_reference {
      let reference_wire = @publication_host.client_submission_reference_record_wire(
        original_reference,
      )
      let before_wire = @resources.ledger_usage(ledger).planning_work
      let used = @resources.ledger_usage(ledger)
      let limits = @resources.ledger_limits(ledger)
      let quote = 2464L +
        explanation_logical_map_scanner_bytes().unwrap() +
        installed_sample_profile_reference_bytes +
        installed_sample_journal_reference_bytes
      let blocker = @resources.reserve_capacity(
        ledger,
        limits.retained_bytes -
        used.held_bytes -
        used.reserved_retention_bytes -
        quote +
        1L,
        0L,
      ).unwrap()
      assert_true(
        check_installed_relation_sample_profile_journal_reference(
          run, request, definition, observation, reference_wire, records, 65536,
          max_nodes, 64,
        )
        is Err(SampleProfileCapacity(Resource(RetentionLimit))),
      )
      assert_eq(@resources.ledger_usage(ledger).planning_work, before_wire)
      @resources.settle_capacity(ledger, blocker).unwrap()
      assert_true(
        check_installed_relation_sample_profile_journal_reference(
          run,
          request,
          definition,
          observation,
          " " + reference_wire,
          records,
          65536,
          max_nodes,
          64,
        )
        is Err(ForeignSampleProfile),
      )
      let (bytes, nodes, _) = @publication.interactive_submission_reference_limits()
      // This fixture's epoch/ref wire is ASCII; leading space adds one byte.
      let codec_work = bytes + 12 * reference_wire.length() + 16 * nodes
      assert_eq(
        @resources.ledger_usage(ledger).planning_work - before_wire,
        codec_work + 12,
      )
      let valid_wire = check_installed_relation_sample_profile_journal_reference(
        run, request, definition, observation, reference_wire, records, 65536, max_nodes,
        64,
      )
      match valid_wire {
        Ok(checked) =>
          admitted = Some(
            (
              checked,
              @publication.run_evidence_value_identity(admission),
              resolved_cid,
            ),
          )
        Err(ForeignSampleProfile) =>
          fail("the exact canonical original reference was refused")
        Err(SampleProfileCapacity(_)) =>
          fail("the second codec reservation did not fit the fixture")
        Err(SampleProfileWork(_)) =>
          fail("the second codec work charge did not fit the fixture")
        Err(_) => fail("the exact original profile did not bind")
      }
      assert_eq(
        @resources.ledger_usage(ledger).planning_work - before_wire,
        2 * codec_work + 12 + expected,
      )
      assert_false(observation.reading || run.source_free_opening)
    }
  }
  // No boundary, task control or prefix was entered by profile validation.
  assert_true(observation.attached is None)
  return_installed_logical_observation(observation).unwrap() |> ignore
  let (checked, admission_cid, resolved_cid) = admitted.unwrap()
  let before_lookup = @resources.ledger_usage(ledger).planning_work
  let retention = installed_relation_sample_retention_for_output(
      run,
      checked,
      first_output.unwrap(),
    )
    .unwrap()
    .unwrap()
  assert_eq(retention.control_admission_cid, admission_cid)
  assert_eq(retention.resolved_profile_cid, resolved_cid)
  assert_eq(retention.limits.max_items, 50L)
  assert_eq(retention.limits.max_bytes, 512L)
  assert_eq(retention.limits.max_artifacts, 1L)
  assert_eq(retention.limits.ttl_seconds, 60L)
  assert_true(retention.limits.required)
  assert_true(
    installed_relation_sample_retention_for_output(
      run,
      checked,
      "sha256:" + "f".repeat(64),
    )
    is Ok(None),
  )
  assert_eq(@resources.ledger_usage(ledger).planning_work - before_lookup, 2)
  checked
}

///|
fn check_collection_committed_relation_sample(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  completed : @execution.ManagedCompletedOutput[Int],
  supplied : @execution.CompletedOutput?,
  expected_task : Int,
  expected_attempt : Int,
  adopt_after_refusals : Bool,
) -> String raise {
  let original = supplied.unwrap()
  let captured = profile.captured
  let observation = prepare_installed_logical_observation(
    owner,
    profile.prepared,
    profile.compiled,
    profile.definition,
    65536,
    8192,
    64,
  ).unwrap()
  defer return_installed_logical_observation(observation) |> ignore
  let hooks = @strategy.captured_task_boundary_hooks(captured).unwrap()
  let committed = @strategy.read_captured_task_boundary(
      captured,
      hooks,
      Settled,
    )
    .unwrap()
    .unwrap()
  defer @strategy.return_captured_task_boundary(committed) |> ignore
  let projected = @publication_host.bind_client_logical_task_boundary(
    observation.original.unwrap(),
    profile.compiled,
    profile.prepared,
    captured,
    committed,
    8192,
  ).unwrap()
  guard projected is @publication_host.Projected(boundary) else {
    fail("exact completed logical output required")
  }
  defer @publication_host.return_client_logical_task_boundary(boundary)
    |> ignore
  assert_eq(@strategy.captured_task_boundary_task(committed), expected_task)
  let expected_step = @publication_host.client_logical_task_boundary_step_id(
    boundary,
    profile.compiled,
    profile.prepared,
  ).unwrap()
  @strategy.return_captured_task_boundary(committed).unwrap()
  let generation = @strategy.captured_task_boundary_generation(committed)
  let schema : @execution.RelationSchemaIdentityLimits = {
    max_fields: 1,
    max_bytes: 512,
    max_nodes: 32,
    max_depth: 8,
  }
  let ledger = @strategy.captured_dag_ledger(captured)
  let before = @resources.ledger_usage(ledger)
  assert_eq(before.attempts, expected_attempt)
  for denied_at in [2, 4] {
    let check_count = Ref(0)
    match
      retain_installed_relation_sample_prefix(
        owner,
        profile,
        boundary,
        completed,
        original,
        schema,
        32,
        8,
        () => {
          check_count.val += 1
          check_count.val < denied_at
        },
      ) {
      Err(SamplePrefixAuthorityLost) => ()
      Err(SamplePrefixLogical(issue)) => fail(@debug.to_string(issue))
      Err(SamplePrefixPhysical(@strategy.AttemptUnavailable)) =>
        fail("missing consumed attempt")
      Err(SamplePrefixPhysical(@strategy.StartUnavailable)) =>
        fail("missing acknowledged start")
      Err(SamplePrefixPhysical(@strategy.StaleOriginal)) =>
        fail("stale managed producer")
      Err(SamplePrefixPhysical(@strategy.Resident(_))) =>
        fail("resident pin refused")
      Err(SamplePrefixPhysical(@strategy.Prefix(@execution.Encoding(issue)))) =>
        fail(@debug.to_string(issue))
      Err(SamplePrefixPhysical(@strategy.Prefix(@execution.Schema(_)))) =>
        fail("schema extent refused")
      Err(SamplePrefixPhysical(@strategy.Prefix(_))) =>
        fail("prefix layout or availability")
      Err(SamplePrefixPhysical(@strategy.Boundary(issue))) =>
        fail(@debug.to_string(issue))
      Err(_) => fail("other capture refusal")
      Ok(None) => fail("Relation port not selected")
      Ok(Some(sample)) => {
        return_installed_relation_sample_prefix(sample).unwrap()
        fail("revoked capture authority admitted the prefix")
      }
    }
    assert_eq(check_count.val, denied_at)
    let after_refusal = @resources.ledger_usage(ledger)
    assert_eq(after_refusal.live_reservations, before.live_reservations)
    assert_eq(
      after_refusal.reserved_retention_bytes,
      before.reserved_retention_bytes,
    )
    assert_eq(
      after_refusal.reserved_execution_bytes,
      before.reserved_execution_bytes,
    )
  }
  let sample = retain_installed_committed_relation_sample(
      owner,
      profile,
      expected_task,
      completed,
      Some(original),
      schema,
      32,
      8,
      () => true,
    )
    .unwrap()
    .unwrap()
  defer return_installed_relation_sample_prefix(sample) |> ignore
  assert_true(
    @resources.ledger_usage(ledger).live_reservations > before.live_reservations,
  )
  @publication_host.return_client_logical_task_boundary(boundary).unwrap()
  return_installed_logical_observation(observation).unwrap() |> ignore
  let (
    retention,
    step_id,
    port_id,
    contract,
    document,
    count,
    total,
    actual_generation,
    attempt,
    revision,
  ) = installed_relation_sample_prefix_original(owner, sample).unwrap()
  assert_eq(retention.control_admission_cid, profile.control_admission_cid)
  assert_eq(step_id, expected_step)
  assert_eq(
    (actual_generation, attempt, revision),
    (generation, expected_attempt.to_int64(), 2),
  )
  assert_eq((count, total), (1, 1))
  let expected = @publication.seal_run_evidence_value(
    "logical_port_key",
    "{\"version\":\"actql-logical-port-key/0.1\",\"compiled_plan_cid\":\"" +
    @publication.publication_contract_identity(
      @publication_host.client_compiled_run_plan(profile.compiled),
    ) +
    "\",\"step_id\":\"" +
    step_id +
    "\",\"role\":\"output\",\"port_ordinal\":0}",
    4096,
    32,
    8,
  ).unwrap()
  assert_eq(port_id, @publication.run_evidence_value_identity(expected))
  assert_true(contract.has_prefix("sha256:"))
  // Only the final SELECT output has the independently expected value 0.
  // The earlier original is a separate materialized computation.
  if adopt_after_refusals {
    assert_true(
      @encode.document_text(document).contains(
        "\"rows\":[[{\"presence\":\"present\",\"value\":0,",
      ),
    )
  }
  let visits = Ref(0)
  let reserved = @resources.ledger_usage(ledger)
  let refusals = if adopt_after_refusals { [] } else { [1, 2, 2, 2] }
  for denied_at in refusals {
    let checks = Ref(0)
    let entered_charge = Ref(false)
    let work = @resources.ledger_usage(ledger).planning_work
    match
      with_installed_relation_sample_adoption(
        owner,
        sample,
        () => {
          checks.val += 1
          if checks.val == 2 {
            let charged = @resources.ledger_usage(ledger)
            entered_charge.val = charged.live_reservations ==
              reserved.live_reservations + 1 &&
              charged.reserved_retention_bytes >
              reserved.reserved_retention_bytes &&
              charged.reserved_execution_bytes >
              reserved.reserved_execution_bytes
          }
          checks.val < denied_at
        },
        (_, _) => {
          visits.val += 1
          Ok(())
        },
      ) {
      Err(SampleAdoptionAuthorityLost) => ()
      Err(SampleAdoptionOriginalUnavailable) =>
        fail("Sample original unavailable")
      Err(SampleAdoptionLimits) => fail("Sample adoption geometry refused")
      Err(SampleAdoptionEncoding(issue)) => fail(@debug.to_string(issue))
      Err(SampleAdoptionEvidence(issue)) => fail(@debug.to_string(issue))
      Err(SampleAdoptionCapacity(issue))
      | Err(SampleAdoptionReturn(issue))
      | Err(SampleAdoptionWork(issue)) => fail(@debug.to_string(issue))
      Err(SampleAdoptionVisitorRefused) | Ok(_) =>
        fail("Revoked capture authority reached the Sample Journal visitor")
    }
    assert_eq(checks.val, denied_at)
    assert_eq(entered_charge.val, denied_at >= 2)
    let after = @resources.ledger_usage(ledger)
    assert_eq(after.live_reservations, reserved.live_reservations)
    assert_eq(after.reserved_retention_bytes, reserved.reserved_retention_bytes)
    assert_eq(after.reserved_execution_bytes, reserved.reserved_execution_bytes)
    assert_eq(after.planning_work, work + denied_at - 1)
  }
  assert_eq(visits.val, 0)
  if adopt_after_refusals {
    let equivalent = { ..profile, }
    assert_true(
      with_installed_relation_sample_journal(
        owner,
        equivalent,
        sample,
        () => true,
        (_, _, _) => {
          visits.val += 1
          true
        },
      )
      is Err(SampleAdoptionOriginalUnavailable),
    )
    let readbacks : Ref[Result[Unit, Error]?] = Ref(None)
    let escaped_current : Ref[(() -> Bool)?] = Ref(None)
    let outcome = with_installed_relation_sample_journal(
      owner,
      profile,
      sample,
      () => true,
      (input, current, funded_bytes) => {
        escaped_current.val = Some(current)
        try {
          visits.val += 1
          assert_true(current())
          assert_true(physical_equal(input.relation, document))
          assert_true(
            return_installed_relation_sample_prefix(sample)
            is Err(@strategy.ReadInProgress),
          )
          assert_true(
            with_installed_relation_sample_adoption(owner, sample, () => true, (
              _,
              _,
            ) => {
              visits.val += 1
              Ok(())
            })
            is Err(SampleAdoptionOriginalUnavailable),
          )
          let generation = @publication.run_evidence_value_json(
            input.source_generation,
          )
          assert_true(generation.contains("\"start_revision\":\"2\""))
          assert_true(
            generation.contains(
              "\"attempt_sequence\":\"" + expected_attempt.to_string() + "\"",
            ),
          )
          assert_true(
            generation.contains(
              "\"committed_generation\":\"" +
              actual_generation.to_string() +
              "\"",
            ),
          )
          assert_true(
            generation.contains("\"output_port_id\":\"" + port_id + "\""),
          )
          let emission = @publication.run_evidence_value_json(input.emission)
          let digest = @sha.hex(@utf8.encode(@encode.document_text(document)))
          assert_true(
            emission.contains(
              "\"relation_prefix_cid\":\"sha256:" + digest + "\"",
            ),
          )
          assert_true(emission.contains("\"completeness\":\"complete\""))
          assert_true(emission.contains("\"truncation\":\"not_truncated\""))
          let reference = @publication.run_evidence_value_json(input.reference)
          assert_true(
            reference.contains(
              "\"original_capture_cid\":\"" +
              @publication.run_evidence_value_identity(input.capture) +
              "\"",
            ),
          )
          assert_true(
            reference.contains(
              "\"emission_provenance_cid\":\"" +
              @publication.run_evidence_value_identity(input.emission) +
              "\"",
            ),
          )
          assert_true(
            @publication.run_evidence_value_identity(input.reference).has_prefix(
              "sha256:",
            ),
          )
          assert_eq(
            @resources.ledger_usage(ledger).live_reservations,
            reserved.live_reservations + 1,
          )
          let namespace_id = @publication.run_definition_namespace(
            profile.definition,
          ).unwrap()
          let mut actual_bytes = @utf8.encode(@encode.document_text(document)).length() +
            1024 +
            6 * namespace_id.length()
          for
            value in [
              input.source_generation,
              input.capture,
              input.emission,
              input.reference,
            ] {
            actual_bytes += @utf8.encode(
              @publication.run_evidence_value_json(value),
            ).length()
          }
          assert_eq(funded_bytes, actual_bytes)
        } catch {
          issue => readbacks.val = Some(Err(issue))
        } noraise {
          _ => readbacks.val = Some(Ok(()))
        }
        true
      },
    )
    match outcome {
      Ok(_) => ()
      Err(SampleAdoptionCapacity(issue))
      | Err(SampleAdoptionReturn(issue))
      | Err(SampleAdoptionWork(issue)) => fail(@debug.to_string(issue))
      Err(SampleAdoptionEvidence(issue)) => fail(@debug.to_string(issue))
      Err(SampleAdoptionEncoding(issue)) => fail(@debug.to_string(issue))
      Err(_) => fail("Original Sample adoption visit refused")
    }
    match readbacks.val.unwrap() {
      Ok(_) => ()
      Err(issue) => raise issue
    }
    assert_false(escaped_current.val.unwrap()())
    let after = @resources.ledger_usage(ledger)
    assert_eq(after.live_reservations, reserved.live_reservations)
    assert_eq(after.reserved_retention_bytes, reserved.reserved_retention_bytes)
    assert_eq(after.reserved_execution_bytes, reserved.reserved_execution_bytes)
    assert_eq(visits.val, 1)
  } else {
    let work = @resources.ledger_usage(ledger).planning_work
    assert_true(
      with_installed_relation_sample_adoption(owner, sample, () => true, (_, _) => {
        Err(SampleAdoptionVisitorRefused)
      })
      is Err(SampleAdoptionVisitorRefused),
    )
    let after = @resources.ledger_usage(ledger)
    assert_true(after.planning_work > work + 1)
    assert_eq(after.live_reservations, reserved.live_reservations)
    assert_eq(after.reserved_retention_bytes, reserved.reserved_retention_bytes)
    assert_eq(after.reserved_execution_bytes, reserved.reserved_execution_bytes)
  }
  return_installed_relation_sample_prefix(sample).unwrap()
  assert_true(installed_relation_sample_prefix_original(owner, sample) is None)
  assert_true(
    with_installed_relation_sample_adoption(owner, sample, () => true, (_, _) => {
      visits.val += 1
      Ok(())
    })
    is Err(SampleAdoptionOriginalUnavailable),
  )
  assert_eq(visits.val, if adopt_after_refusals { 1 } else { 0 })
  return_installed_relation_sample_prefix(sample).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).live_reservations,
    before.live_reservations - 1,
  )
  port_id
}

///|
test "collection original Request publishes 9999 with its same live output" {
  collection_request_publication_case(9999, false)
}

///|
test "collection original Request snapshot refuses occupied retention" {
  collection_request_publication_case(9999, true)
}

///|
test "collection original Request publishes 9999 with explicit finite work" {
  collection_request_publication_case(
    9999,
    false,
    source_free_max_work=Some(30000000),
  )
}

///|
test "collection original Request default work refusal retains bounded cleanup" {
  collection_request_publication_case(100000, false, expect_work_refusal=true)
}

///|
test "collection original Request 100000 uses selected finite initial parent through Result and close" {
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(1073741824L),
    execution_bytes=Some(1073741824L),
  ).unwrap()
  collection_request_publication_case(
    100000,
    false,
    source_free_max_work=Some(30000000),
    initial_limits=Some(limits),
  )
}

///|
test "small original Request actual demand is unchanged by larger finite memory ceilings" {
  let baseline : Array[@resources.LedgerUsage] = []
  for
    memory in [
      None,
      Some(1073741824L),
      Some(2147483648L),
      Some(268435456L),
      Some(67108864L),
    ] {
    let samples : Array[@resources.LedgerUsage] = []
    let limits = client_local_preparation_initial_limits(
      client_local_resource_policy(),
      retained_bytes=memory,
      execution_bytes=memory,
    ).unwrap()
    collection_request_publication_case(
      1,
      false,
      source_free_max_work=Some(30000000),
      initial_limits=Some(limits),
      simple=true,
      observed=Some(samples),
    )
    assert_eq(samples.length(), 8)
    if baseline.is_empty() {
      for sample in samples {
        baseline.push(sample)
      }
    } else {
      assert_eq(samples, baseline)
    }
    for phase, sample in samples {
      println(
        "small-request-demand cap=" +
        limits.retained_bytes.to_string() +
        " phase=" +
        phase.to_string() +
        " R=" +
        sample.reserved_retention_bytes.to_string() +
        " E=" +
        sample.reserved_execution_bytes.to_string() +
        " held=" +
        sample.held_bytes.to_string() +
        " peakR=" +
        sample.peak_retention_bytes.to_string(),
      )
    }
  }
}

///|
fn collection_request_publication_case(
  count : Int,
  occupied : Bool,
  source_free_max_work? : Int? = None,
  expect_work_refusal? : Bool = false,
  initial_limits? : @resources.LedgerLimits? = None,
  simple? : Bool = false,
  observed? : Array[@resources.LedgerUsage]? = None,
  actual_request_profile? : Bool = false,
  giant_elements? : Int? = None,
  diagnostic_failure? : Ref[LocalValuesExecutionIssue?]? = None,
  check_sample_start? : Bool = false,
) -> Unit raise {
  let digits : Array[String] = []
  for n in 0..<10 {
    digits.push("SELECT " + n.to_string() + " AS n")
  }
  let giant_row = giant_elements.map(elements => {
    "{\"cells\":[" + Array::make(elements, "0").join(",") + "]}"
  })
  let sql = if giant_elements is Some(elements) {
    "SELECT [" + Array::make(elements, "0").join(",") + "] AS cells"
  } else if simple {
    "SELECT 0 AS n"
  } else {
    "WITH d AS (" +
    digits.join(" UNION ALL ") +
    ") SELECT 0 AS n FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e CROSS JOIN d f WHERE a.n + 10*b.n + 100*c.n + 1000*e.n + 10000*f.n < " +
    count.to_string()
  }
  let selected_rows = if actual_request_profile {
    let initial = initial_limits.unwrap()
    client_local_materialized_row_ceiling(
      client_local_resource_policy(),
      retained_bytes=Some(initial.retained_bytes),
      execution_bytes=Some(initial.execution_bytes),
    ).unwrap()
  } else {
    client_local_materialized_row_ceiling(client_local_resource_policy()).unwrap()
  }
  let environment = collection_capacity_selected_environment(selected_rows)
  let cid = @checked.checking_environment_cid(environment)
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" + cid + "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, input) = native_driver_parent(sql, initial_limits~, observed~)
  let original_ledger = parent.ledger
  if initial_limits is Some(selected) {
    assert_eq(@resources.ledger_limits(original_ledger), selected)
  }
  let prepared = if actual_request_profile {
    prepare_request_default_source_computation_check(
      parent,
      input,
      request_document_test_source(sql, "sql"),
      native_json_reader,
      environment,
      publication,
      [],
      None,
      @publication_host.client_standard_effect_computation_limits(),
    ).unwrap()
    finish_request_checked_computation(parent, input, environment, publication).unwrap()
    |> ignore
    parent.compiled_program.unwrap()
  } else {
    parse_request_query_syntax(parent, input, sql, @frontend.Sql).unwrap()
    |> ignore
    lower_request_published_query(
      parent,
      input,
      publication,
      environment,
      None,
      public_primary=true,
    ).unwrap()
    |> ignore
    let limits = @publication_host.client_standard_program_preparation_limits()
    let check = prepare_request_program_check_preparation(
      parent,
      input,
      environment,
      None,
      [],
      limits.checking,
    ).unwrap()
    prepare_program_check_input(check).unwrap()
    prepare_program_check_prelude(check).unwrap() |> ignore
    prepare_program_check_registry(check).unwrap() |> ignore
    prepare_program_check_contents(check).unwrap() |> ignore
    prepare_program_check_references(check).unwrap() |> ignore
    prepare_program_check_policies(check).unwrap() |> ignore
    prepare_program_check_values(check).unwrap() |> ignore
    prepare_program_check_views(check).unwrap() |> ignore
    prepare_program_check_carriers(check).unwrap() |> ignore
    prepare_program_check_requests(check).unwrap() |> ignore
    reconcile_program_check_requests(check).unwrap()
    assert_true(
      finish_program_check_preparation(check).unwrap() is @checked.Checked(_),
    )
    compile_program_check_preparation(
      check,
      limits,
      execution_profile=if check_sample_start { Debug } else { Normal },
    ).unwrap()
  }
  if observed is Some(samples) {
    samples.push(@resources.ledger_usage(parent.ledger))
  }
  if !actual_request_profile {
    continue_request_program_preparation(parent, input).unwrap() |> ignore
  }
  let selected_codec = if actual_request_profile {
    request_program_compilation_limits(parent, input).unwrap()
  } else {
    @publication_host.client_standard_pure_compilation_limits()
  }
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=selected_codec,
    runtime_compilation_limits=if actual_request_profile {
      Some(selected_codec)
    } else {
      None
    },
    retained_output=false,
    provider_factory=_ => [],
    source_free_max_work~,
  ).unwrap()
  // A second module entrance cannot replace the first selected policy or
  // construct another Plan on the same original Request.
  assert_true(
    prepare_request_program_module_body(
      parent,
      input,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=false,
      provider_factory=_ => [],
      source_free_max_work=Some(40000000),
    )
    is Err(Preparation(WrongPhase)),
  )
  let plan = parent.program_source_free.unwrap()
  if observed is Some(samples) {
    samples.push(@resources.ledger_usage(parent.ledger))
  }
  assert_eq(
    plan.capacity_plan.values.max_work,
    source_free_max_work.unwrap_or(20000000),
  )
  assert_eq(
    plan.capacity_plan.execution.rows.output_values.max_work,
    plan.capacity_plan.values.max_work,
  )
  assert_eq(
    plan.capacity_plan.execution.max_work,
    plan.capacity_plan.values.max_work,
  )
  assert_eq(
    parent.program_source_free_max_work,
    Some(plan.capacity_plan.values.max_work),
  )
  if !simple {
    let actual_requirements = @execution.generated_sequence_requirements(
      plan.sequences[43],
      10000,
    ).unwrap()
    let actual_fragment = @lower.sequence_requirements_fragment_for_step(
      actual_requirements, 43,
    ).unwrap()
    assert_eq(
      actual_fragment.logical.max_work,
      plan.capacity_plan.values.max_work.to_int64(),
    )
  }
  println(
    "request-finalization-policy " +
    @debug.to_string(
      (
        @publication_host.prepared_client_values_max_rows(prepared),
        plan.capacity_plan.execution.rows.max_rows,
        plan.capacity_plan.execution.rows.output_values,
      ),
    ),
  )
  let holder = borrow_request_program_preparation(parent).unwrap()
  let original_reference = if check_sample_start {
    Some(collection_sample_submission_reference("2"))
  } else {
    None
  }
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    original_reference
    .map(@publication_host.client_submission_reference_record_request_id)
    .unwrap_or("same-request-finalization-" + count.to_string()),
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_true(physical_equal(run.ledger.unwrap(), original_ledger))
  if initial_limits is Some(selected) {
    assert_eq(@resources.ledger_limits(run.ledger.unwrap()), selected)
  }
  if observed is Some(samples) {
    samples.push(@resources.ledger_usage(parent.ledger))
  }
  // Consume the SAME compilation retained by this Request's existing Plan.
  // This does not compile another Program or substitute a serialized body.
  let compiled = match plan.compilation.unwrap() {
    Values(original) =>
      @publication_host.issue_client_values_compiled_run(
        prepared,
        original,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    Tasks(original) =>
      @publication_host.issue_client_task_compiled_run(
        prepared,
        original,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    _ => fail("original source-free Values or Tasks compilation required")
  }
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled,
    "collection-publication",
    "same-original-" + count.to_string(),
    "2026-10-29T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  issue_program_publication_invocation(
    run, prepared, compiled, definition, "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    65536, 8192, 64,
  ).unwrap()
  |> ignore
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      false,
    )
    .unwrap()
    .unwrap()
  let sample_profile = if check_sample_start {
    let captured = run.source_free_captured.unwrap()
    let foreign_definition = @publication.admit_publication_contract(
      "run_definition",
      @publication.publication_contract_json(definition),
      65536,
      8192,
      64,
    ).unwrap()
    assert_true(
      acknowledge_installed_relation_sample_start(
        run, prepared, request, compiled, foreign_definition, captured, 2,
      )
      is Err(ForeignSampleStart),
    )
    let foreign_request = @publication_host.prepare_source_free_client_request_identity(
      prepared,
      "sha256:" + "a".repeat(64),
      @publication_host.client_request_caller_id(request),
    ).unwrap()
    assert_true(
      acknowledge_installed_relation_sample_start(
        run, prepared, foreign_request, compiled, definition, captured, 2,
      )
      is Err(ForeignSampleStart),
    )
    let ledger = run.ledger.unwrap()
    let foreign_run = @strategy.open_source_free_dag(
      @strategy.captured_dag_graph(captured),
      ledger,
    ).unwrap()
    assert_true(
      acknowledge_installed_relation_sample_start(
        run, prepared, request, compiled, definition, foreign_run, 2,
      )
      is Err(ForeignSampleStart),
    )
    @strategy.stop_captured_dag(foreign_run)
    // The independent header/reference/word inventory costs 7456 bytes in
    // both dimensions on this SAME original preparation reservation.
    let journal_bytes = 1024
    let journal_charge = installed_relation_sample_journal_bytes(journal_bytes).unwrap()
    assert_true(journal_charge > journal_bytes.to_int64())
    let original_holder = managed_run_publication_body(run, prepared).unwrap()
    for (stored, start_bytes) in [(0, 7456L), (journal_bytes, journal_charge)] {
      let (retained, execution) = @resources.preparation_body_borrow_reserved_extents(
        original_holder,
      ).unwrap()
      let used = @resources.ledger_usage(ledger)
      let limits = @resources.ledger_limits(ledger)
      let retention_blocker = limits.retained_bytes -
        used.held_bytes -
        used.reserved_retention_bytes -
        start_bytes
      let execution_blocker = limits.execution_bytes -
        used.reserved_execution_bytes -
        start_bytes
      for retention in [true, false] {
        let blocker = @resources.reserve_capacity(
          ledger,
          retention_blocker + (if retention { 1L } else { 0L }),
          execution_blocker + (if retention { 0L } else { 1L }),
        ).unwrap()
        let declined = reserve_installed_relation_sample_start(
          run,
          prepared,
          request,
          compiled,
          definition,
          captured,
          journal_bytes=stored,
        )
        assert_true(
          if retention {
            declined is Err(SampleStartCapacity(Resource(RetentionLimit)))
          } else {
            declined is Err(SampleStartCapacity(Resource(ExecutionLimit)))
          },
        )
        assert_eq(
          @resources.preparation_body_borrow_reserved_extents(original_holder),
          Ok((retained, execution)),
        )
        @resources.settle_capacity(ledger, blocker).unwrap()
      }
      let blocker = @resources.reserve_capacity(
        ledger, retention_blocker, execution_blocker,
      ).unwrap()
      assert_true(
        reserve_installed_relation_sample_start(
          run,
          prepared,
          foreign_request,
          compiled,
          definition,
          captured,
          journal_bytes=stored,
        )
        is Err(ForeignSampleStart),
      )
      reserve_installed_relation_sample_start(
        run,
        prepared,
        request,
        compiled,
        definition,
        captured,
        journal_bytes=stored,
      ).unwrap()
      assert_eq(
        @resources.preparation_body_borrow_reserved_extents(original_holder),
        Ok((retained + start_bytes, execution + start_bytes)),
      )
      @resources.settle_capacity(ledger, blocker).unwrap()
    }
    let profile = check_relation_sample_profile_on_collection(
      run,
      prepared,
      request,
      compiled,
      definition,
      ledger,
      original_reference.unwrap(),
    )
    // Exact originals alone cannot substitute for the selected controller.
    assert_true(
      acknowledge_installed_relation_sample_start(
        run, prepared, request, compiled, definition, captured, 2,
      )
      is Err(SampleStartControl(@strategy.NotPrepared)),
    )
    let hooks = @strategy.prepare_captured_task_boundary_hooks(
      captured,
      @strategy.captured_dag_graph(captured),
      @strategy.captured_dag_strategy_revision(captured),
    ).unwrap()
    let account = @authorization.admit_account_configuration({
      account_id: "sample-test",
      entries: [
        {
          entry_id: "sample-test-control",
          outcome: Allow,
          scope: {
            principal: All,
            connection: All,
            resource: All,
            operation: AnyOf(["pause", "resume"]),
          },
          exclusions: [],
        },
      ],
      bootstrap: None,
    }).unwrap()
    let pause : @authorization.AccessTuple = {
      principal: "sample-fixture",
      connection: "node",
      resource: "run",
      operation: "pause",
    }
    let subject = @publication.publication_contract_identity(definition)
    let context = @publication.run_publication_execution_context(
      @publication_host.client_compiled_run_admission(compiled),
    )
    let bound = fn(tuple) {
      @authorization.bind_dispatch_authorization(
        account,
        tuple,
        Activation,
        subject,
        context,
      ).unwrap()
    }
    match
      @strategy.prepare_captured_task_control(
        captured,
        hooks,
        bound(pause),
        account,
        pause,
        subject,
        context,
      ) {
      Ok(_) => ()
      Err(issue) => fail("Original Debug setup: " + @debug.to_string(issue))
    }
    acknowledge_installed_relation_sample_start(
      run, prepared, request, compiled, definition, captured, 2,
    ).unwrap()
    assert_true(
      acknowledge_installed_relation_sample_start(
        run, prepared, request, compiled, definition, captured, 3,
      )
      is Err(SampleStartControl(@strategy.AlreadyStarted)),
    )
    let resume_access = { ..pause, operation: "resume", }
    @strategy.command_captured_task_control(
      captured,
      hooks,
      0,
      ResumeTerminal,
      bound(resume_access),
      account,
      resume_access,
      subject,
      context,
    ).unwrap()
    Some(profile)
  } else {
    None
  }
  let ledger = parent.ledger
  let sample_failure : Ref[Error?] = Ref(None)
  let sample_ports : Array[String] = []
  let sample_compute : Ref[(Int, Int)?] = Ref(None)
  let sample_tasks = match sample_profile {
    None => []
    Some(profile) => {
      let graph = @strategy.captured_dag_graph(profile.captured)
      let result = @strategy.graph_result_task(graph, 0).unwrap()
      let earlier = @strategy.graph_captured_prefix(graph)
      assert_true(earlier < result)
      assert_true(@strategy.graph_task_target(graph, earlier) is Some(_))
      [earlier, result]
    }
  }
  let on_relation_commit = sample_profile.map(profile => {
    (completed, original) => {
      if sample_failure.val is Some(_) {
        return
      }
      let (expected_task, expected_attempt) = sample_compute.val.unwrap()
      sample_compute.val = None
      try {
        let port = check_collection_committed_relation_sample(
          run,
          profile,
          completed,
          original,
          expected_task,
          expected_attempt,
          expected_task == sample_tasks[1],
        )
        assert_false(sample_ports.contains(port))
        sample_ports.push(port)
      } catch {
        issue => sample_failure.val = Some(issue)
      } noraise {
        _ => ()
      }
    }
  })
  let result = collection_node_callback_order(
    setup,
    32,
    100000,
    () => true,
    require_live=None,
    first=0,
    component_compute_quantum=256,
    on_relation_commit~,
    sample_tasks~,
    component_after_compute=Some((operations, task) => {
      if sample_tasks.contains(task) && sample_profile is Some(profile) {
        sample_compute.val = Some(
          (
            task,
            @resources.ledger_usage(
              @strategy.captured_dag_ledger(profile.captured),
            ).attempts,
          ),
        )
      }
      collection_node_snapshot(operations, task, ledger)
    }),
  )
  let output = match result {
    Ok(value) => {
      assert_false(expect_work_refusal)
      if sample_profile is Some(_) {
        if sample_failure.val is Some(issue) {
          raise issue
        }
        assert_eq(sample_ports.length(), 2)
      }
      value
    }
    Err(failure) => {
      if diagnostic_failure is Some(original) {
        original.val = Some(local_values_execution_failure_issue(failure))
        let mut cleaned = false
        for _ in 0..<100000 {
          if retry_local_values_execution_failure_cleanup(failure) {
            cleaned = true
            break
          }
        }
        assert_true(cleaned)
        @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
        retire_installed_managed_run(run).unwrap()
        assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
        return
      }
      if expect_work_refusal {
        assert_true(source_free_max_work is None)
        assert_true(
          local_values_execution_failure_issue(failure)
          // The original managed diagnostic retains the exact selected policy,
          // rather than the former nested rows-only failure shape.
          is Driver(
            @local_driver.LogicalWorkLimit(
              43,
              20000000L,
              SourceFreeInstallation
            )
          ),
        )
        let mut cleanup_polls = 0
        let mut cleaned = false
        for _ in 0..<100000 {
          cleanup_polls += 1
          if retry_local_values_execution_failure_cleanup(failure) {
            cleaned = true
            break
          }
        }
        println(
          "default-work-refusal cleanupPolls=" +
          cleanup_polls.to_string() +
          " complete=" +
          cleaned.to_string(),
        )
        assert_true(cleaned)
        @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
        retire_installed_managed_run(run).unwrap()
        assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
        return
      }
      let family = match local_values_execution_failure_issue(failure) {
        Driver(
          @local_driver.ManagedValues(
            @execution.Admission(@execution.CaptureLimit)
          )
        ) => "ManagedValues/Admission/CaptureLimit"
        Driver(@local_driver.Configuration(@connector.InputUnavailable)) =>
          "Configuration/InputUnavailable"
        Driver(@local_driver.Execution(@strategy.Physical(original))) =>
          "Execution/Physical/" + @debug.to_string(original)
        Driver(
          @local_driver.Configuration(
            @connector.Execution(@execution.Capture(step, original))
          )
        ) =>
          "Configuration/Execution/Capture/" +
          @debug.to_string((step, original))
        Driver(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(step, @execution.LogicalRows(original))
            )
          )
        ) =>
          "Configuration/Execution/LogicalRows/" +
          @debug.to_string((step, original))
        Driver(
          @local_driver.Configuration(
            @connector.Execution(@execution.Rows(step, @execution.RowLimit))
          )
        ) => "Configuration/Execution/RowLimit/" + step.to_string()
        Driver(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(
                step,
                @execution.Evaluation(row, binding, original)
              )
            )
          )
        ) =>
          "Configuration/Execution/Evaluation/" +
          @debug.to_string((step, row, binding, original.kind))
        Driver(
          @local_driver.Configuration(
            @connector.Execution(@execution.Rows(step, @execution.InvalidRows))
          )
        ) => "Configuration/Execution/InvalidRows/" + step.to_string()
        Driver(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(step, @execution.InvalidRowLimits)
            )
          )
        ) => "Configuration/Execution/InvalidRowLimits/" + step.to_string()
        Driver(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(step, @execution.OwnerMismatch)
            )
          )
        ) => "Configuration/Execution/OwnerMismatch/" + step.to_string()
        Driver(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(step, @execution.InputMismatch)
            )
          )
        ) => "Configuration/Execution/InputMismatch/" + step.to_string()
        Driver(@local_driver.Configuration(_)) => "Configuration/other"
        Driver(@local_driver.Execution(_)) => "Execution/other"
        Driver(@local_driver.ManagedValues(_)) => "ManagedValues/other"
        Driver(@local_driver.ManagedCopy(original)) =>
          "ManagedCopy/" + @debug.to_string(original)
        Driver(@local_driver.ManagedRetention(original)) =>
          "ManagedRetention/" + @debug.to_string(original)
        _ => "different checked failure"
      }
      let cleaned = retry_local_values_execution_failure_cleanup(failure)
      println(
        "request-finalization-budget " +
        @debug.to_string(@resources.ledger_usage(parent.ledger)),
      )
      fail("request-finalization " + family + " cleanup=" + cleaned.to_string())
    }
  }
  // The ordinary caller reserves publication BEFORE closing its still-needed
  // completed output. The earlier isolated component closed that output first.
  let before = @resources.ledger_usage(parent.ledger)
  if observed is Some(samples) {
    samples.push(before)
  }
  let caps = @resources.ledger_admission_limits(parent.ledger)
  println(
    "publication-live held=" +
    before.held_bytes.to_string() +
    " reservedR=" +
    before.reserved_retention_bytes.to_string() +
    " reservedE=" +
    before.reserved_execution_bytes.to_string() +
    " limitR=" +
    caps.retained_bytes.to_string() +
    " limitE=" +
    caps.execution_bytes.to_string(),
  )
  let publication = match reserve_program_publication(run, prepared) {
    Ok(value) => value
    Err(issue) => {
      let family = match issue {
        Capacity(Resource(original)) =>
          "Capacity/Resource/" + @debug.to_string(original)
        Capacity(original) => "Capacity/" + @debug.to_string(original)
        WrongPhase => "WrongPhase"
        ForeignOriginal => "ForeignOriginal"
        Policy => "Policy"
        _ => "different checked publication failure"
      }
      let closed = output.close()
      @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
      let retired = retire_installed_managed_run(run) is Ok(_)
      fail(
        "same-live-publication " +
        family +
        " close=" +
        closed.to_string() +
        " retired=" +
        retired.to_string(),
      )
    }
  }
  assert_true(physical_equal(run.publication.unwrap(), publication))
  if !simple {
    assert_false(publication.snapshot_prequoted)
  }
  let rows = output.rows().unwrap()
  assert_eq(rows.length(), count)
  for row in rows {
    assert_eq(row, giant_row.unwrap_or("{\"n\":0}"))
  }
  // Use the same retained Plan's actual export limits and the original
  // physical output bridge. No replacement Result/schema/row owner is issued.
  let limits = installed_managed_publication_limits(run, prepared, 10000000).unwrap()
  let (bridge, export_output) = output
    .prepare_publication_bridge(
      plan.capacity_plan.imports.row,
      plan.capacity_plan.metadata.bridge_entries,
      plan.capacity_plan.metadata.name_bytes,
      limits,
    )
    .unwrap()
  let transformation = @publication_host.start_captured_managed_result_publication_export(
    publication.run.unwrap(),
    0,
    output.completed,
    bridge,
    export_output,
    limits,
  ).unwrap()
  let mut transformed = false
  for _ in 0..<100000 {
    let (done, work) = transformation.advance(64).unwrap()
    assert_true(work <= 64)
    if done {
      transformed = true
      break
    }
  }
  assert_true(transformed)
  let stream = transformation.finish().unwrap()
  let exported = StringBuilder()
  let mut eof = false
  let mut export_polls = limits.payload_wire.max_bytes.to_int64() + 2L
  while export_polls > 0L {
    export_polls -= 1L
    match stream.next().unwrap() {
      Some(chunk) => exported.write_string(chunk)
      None => {
        eof = true
        break
      }
    }
  }
  assert_true(eof)
  exported.write_string(stream.finish().unwrap())
  let expected = "[" +
    Array::make(count, giant_row.unwrap_or("{\"n\":0}")).join(",") +
    "]"
  assert_eq(exported.to_string(), expected)
  stream
  .issue_result_evidence(
    "sha256:" + "1".repeat(64),
    ["sha256:" + "2".repeat(64)],
    @publication.publication_contract_identity(definition),
    "sha256:" + "4".repeat(64),
    "sha256:" + "5".repeat(64),
    65536,
    8192,
    64,
  )
  .unwrap()
  // Explicit component retention contract. It is no Account/Host/Store
  // admission; all actual output/occurrence evidence above is retained.
  let retention = @publication.seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"sha256:" +
    "8".repeat(64) +
    "\",\"effective_data_policy_cid\":\"sha256:" +
    "4".repeat(64) +
    "\",\"available_until\":\"2099-01-01T00:00:00.000Z\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"extension_ceiling_at\":\"2099-01-03T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:" +
    "9".repeat(64) +
    "\",\"metadata_delete_by\":\"2099-01-04T00:00:00.000Z\",\"clock_contract_cid\":\"sha256:" +
    "a".repeat(64) +
    "\"}",
    65536,
    8192,
    64,
  ).unwrap()
  stream
  .issue_artifact(
    run.publication_invocation.unwrap(),
    retention,
    65536,
    8192,
    64,
  )
  .unwrap()
  |> ignore
  if occupied {
    let usage = @resources.ledger_usage(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      caps.retained_bytes - usage.held_bytes - usage.reserved_retention_bytes,
      0L,
    ).unwrap()
    assert_true(
      begin_program_snapshot(publication, stream)
      is Err(Capacity(Resource(RetentionLimit))),
    )
    assert_true(publication.snapshot is None)
    assert_eq(publication.completed_snapshots.length(), 0)
    assert_false(publication.snapshot_starting)
    assert_eq(publication.next_snapshot_index, 1)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    // Failed constructor admission consumed the occurrence; releasing a
    // different reservation cannot authorize a retry or issue a snapshot.
    assert_true(begin_program_snapshot(publication, stream) is Err(WrongPhase))
  } else {
    let snapshot = begin_program_snapshot(publication, stream).unwrap()
    let mut done = false
    for _ in 0..<100000 {
      let (complete, work) = advance_program_snapshot(snapshot, 64).unwrap()
      assert_true(work <= 64)
      if complete {
        done = true
        break
      }
    }
    assert_true(done)
    let captured = finish_program_snapshot(snapshot).unwrap()
    // Successful nominal completion rechecks the original artifact hash and
    // row/field binding; its private rows are deliberately not projected here.
    assert_true(physical_equal(publication.completed_snapshots[0], captured))
    assert_true(finish_program_snapshot(snapshot) is Err(ForeignOriginal))
    cancel_program_snapshot(snapshot)
    assert_eq(publication.completed_snapshots.length(), 1)
  }
  if observed is Some(samples) {
    samples.push(@resources.ledger_usage(parent.ledger))
  }
  stream.cancel()
  @execution.close_managed_publication_bridge(bridge)
  assert_true(output.close())
  if sample_profile is Some(profile) {
    assert_false(
      @strategy.captured_task_boundary_cleanup_pending(profile.captured),
    )
    assert_eq(
      @strategy.captured_task_boundary_cleanup_issue(profile.captured),
      None,
    )
    let usage = @resources.ledger_usage(
      @strategy.captured_dag_ledger(profile.captured),
    )
    assert_eq(usage.live_reservations, 1)
    assert_eq(usage.holdings, 0)
  }
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  match retire_installed_managed_run(run) {
    Ok(_) => ()
    Err(CleanupPending) =>
      fail(
        "retirement still pending: " +
        @debug.to_string(@resources.ledger_usage(parent.ledger)),
      )
    Err(Ledger(issue)) => fail(@debug.to_string(issue))
    Err(Preparation(issue)) => fail(@debug.to_string(issue))
    Err(_) => fail("original retirement refused")
  }
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  if observed is Some(samples) {
    samples.push(@resources.ledger_usage(parent.ledger))
  }
}

///|
// Diagnostic component backing only. The real driver owns source revocation,
// export/import receipts, completed output and reference reclamation. Encoded
// chunks stand in for physical Store I/O; this is not Node file/close evidence.
fn collection_node_snapshot(
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  task : Int,
  ledger : @resources.Ledger,
) -> Result[Unit, @local_driver.LocalDispatchIssue] {
  let released = Ref(false)
  let present = Ref(true)
  let snapshot = match
    (operations.prepare_relation_snapshot)(() => released.val) {
    Ok(Some(value)) => value
    Ok(None) => return Ok(())
    Err(issue) =>
      return collection_node_snapshot_failure(task, 1, issue, ledger)
  }
  let parts : Array[String] = []
  let mut bytes = 0
  let mut saved = false
  // Consume the selected finite byte stream, including its tail/EOF calls.
  // The former 100000-poll fixture stopped a valid 100000-row stream early;
  // this changes no product wire/work/resource limit or outer guard duration.
  let mut save_polls = snapshot.frames.maxBytes.to_int64() + 2L
  while save_polls > 0L {
    save_polls -= 1L
    let observation = match (snapshot.advance_save)(32) {
      Ok(value) => value
      Err(issue) =>
        return collection_node_snapshot_failure(task, 2, issue, ledger)
    }
    let part = match (snapshot.take_output)() {
      Ok(value) => value
      Err(issue) =>
        return collection_node_snapshot_failure(task, 2, issue, ledger)
    }
    if part != "" {
      bytes += @utf8.encode(part).length()
      parts.push(part)
    }
    if observation.complete {
      saved = true
      break
    }
  }
  if !saved {
    return collection_node_snapshot_failure(
      task,
      3,
      @local_driver.Configuration(@connector.InvalidLimits),
      ledger,
    )
  }
  let content = match (snapshot.content)() {
    Ok(value) => value
    Err(issue) =>
      return collection_node_snapshot_failure(task, 4, issue, ledger)
  }
  if content.bytes != bytes ||
    content.cid != "sha256:" + @sha.hex(@utf8.encode(parts.join(""))) {
    return collection_node_snapshot_failure(
      task,
      5,
      @local_driver.Configuration(@connector.InputUnavailable),
      ledger,
    )
  }
  let source_rows = (operations.output_rows)()
  match (snapshot.release_source)(content.cid, () => present.val) {
    Ok(_) => ()
    Err(issue) =>
      return collection_node_snapshot_failure(task, 6, issue, ledger)
  }
  if (snapshot.source_available)() ||
    (source_rows > 0 && (operations.output_row)(0) is Ok(_)) {
    return collection_node_snapshot_failure(
      task,
      7,
      @local_driver.Configuration(@connector.InputUnavailable),
      ledger,
    )
  }
  match (snapshot.begin_reload)() {
    Ok(_) => ()
    Err(issue) =>
      return collection_node_snapshot_failure(task, 8, issue, ledger)
  }
  let limits = snapshot.frames
  let frames = match
    @publication.prepare_durable_result_row_frames(
      limits.maxBytes,
      limits.maxRows,
      limits.maxRowBytes,
      limits.maxDepth,
      limits.maxFrameBytes,
    ) {
    Ok(value) => value
    Err(issue) => {
      println(
        "node-component framer-prepare task=" +
        task.to_string() +
        " issue=" +
        @debug.to_string(issue),
      )
      return Err(@local_driver.Configuration(@connector.InvalidLimits))
    }
  }
  for part in parts {
    let rows = match
      @publication.feed_durable_result_row_frames(frames, @utf8.encode(part)) {
      Ok(value) => value
      Err(issue) => {
        @publication.cancel_durable_result_row_frames(frames)
        println(
          "node-component framer-feed task=" +
          task.to_string() +
          " issue=" +
          @debug.to_string(issue),
        )
        return Err(@local_driver.Configuration(@connector.InvalidLimits))
      }
    }
    for row in rows {
      match (snapshot.append_reload)(row) {
        Ok(_) => ()
        Err(issue) => {
          @publication.cancel_durable_result_row_frames(frames)
          return collection_node_snapshot_failure(task, 9, issue, ledger)
        }
      }
    }
  }
  let usage = match @publication.finish_durable_result_row_frames(frames) {
    Ok(value) => value
    Err(issue) => {
      @publication.cancel_durable_result_row_frames(frames)
      println(
        "node-component framer-finish task=" +
        task.to_string() +
        " issue=" +
        @debug.to_string(issue),
      )
      return Err(@local_driver.Configuration(@connector.InvalidLimits))
    }
  }
  @publication.cancel_durable_result_row_frames(frames)
  if usage.bytes != bytes {
    return collection_node_snapshot_failure(
      task,
      10,
      @local_driver.Configuration(@connector.InputUnavailable),
      ledger,
    )
  }
  match (snapshot.finish_reload)() {
    Ok(_) => ()
    Err(issue) =>
      return collection_node_snapshot_failure(task, 11, issue, ledger)
  }
  present.val = false
  parts.clear()
  released.val = true
  let mut cleaned = false
  for _ in 0..<100000 {
    if (snapshot.cleanup_references)(32) {
      cleaned = true
      break
    }
  }
  if !cleaned {
    return collection_node_snapshot_failure(
      task,
      12,
      @local_driver.Configuration(@connector.InvalidLimits),
      ledger,
    )
  }
  match (snapshot.finish)() {
    Ok(_) => Ok(())
    Err(issue) => collection_node_snapshot_failure(task, 13, issue, ledger)
  }
}

///|
fn collection_node_snapshot_failure(
  task : Int,
  phase : Int,
  issue : @local_driver.LocalDispatchIssue,
  ledger : @resources.Ledger,
) -> Result[Unit, @local_driver.LocalDispatchIssue] {
  let family = match issue {
    Configuration(@connector.InputUnavailable) =>
      "Configuration/InputUnavailable"
    Configuration(@connector.InvalidLimits) => "Configuration/InvalidLimits"
    ManagedValues(@execution.Admission(@execution.CaptureLimit)) =>
      "ManagedValues/Admission/CaptureLimit"
    _ => "different checked failure"
  }
  println(
    "node-component snapshot task=" +
    task.to_string() +
    " phase=" +
    phase.to_string() +
    " issue=" +
    family +
    " usage=" +
    @debug.to_string(@resources.ledger_usage(ledger)),
  )
  Err(issue)
}

///|
// Existing component driver body moved byte-exactly into this whitebox fixture.
// It calls the same original owners; no product callback or public API is added.
fn collection_node_callback_order(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  require_current : () -> Bool,
  require_live~ : (() -> Bool)?,
  first~ : Int,
  retained_effect? : @strategy.CapturedEffectRunDAG? = None,
  component_compute_quantum? : Int = 0,
  component_after_compute? : ((
    @local_driver.LocalManagedDispatchOperations[Int],
    Int,
  ) -> Result[Unit, @local_driver.LocalDispatchIssue])? = None,
  on_relation_commit? : ((
    @execution.ManagedCompletedOutput[Int],
    @execution.CompletedOutput?,
  ) -> Unit)? = None,
  sample_tasks? : Array[Int] = [],
) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
  if finalization_quantum <= 0 || max_finalization_rounds <= 0 {
    return Err(failed_local_values_execution(InvalidLimits))
  }
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let graph = @strategy.captured_dag_graph(run)
  let count = @strategy.graph_task_count(graph)
  // Do not size the retained task table from an unsupported graph. Stopping
  // this original run is still its caller-owned cleanup, not another attempt.
  if count <= first {
    let cleanup = () => close_local_values_tasks(run, [])
    return Err({ issue: UnsupportedGraph, cleanup, cleaned: cleanup(), })
  }
  let tasks : Array[LocalValuesTaskExecution?] = Array::make(count, None)
  let available = Ref(true)
  let current = () => available.val && require_current()
  // Legacy callers retain their original callback at each poll. A trusted
  // caller may separate cheap original-lifetime polling from its currentness
  // guard, which still runs at dispatch and callback-return boundaries below.
  // Neither callback establishes Account authorization in this adapter.
  let live = () => {
    if !available.val {
      return false
    }
    match require_live {
      Some(check) => check()
      None => require_current()
    }
  }
  let reject = fn(
    issue : LocalValuesExecutionIssue,
  ) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
    available.val = false
    let cleanup = () => close_local_values_tasks(run, tasks)
    Err(LocalValuesExecutionFailure::{ issue, cleanup, cleaned: cleanup(), })
  }
  if !current() {
    return reject(Fenced)
  }
  if require_live is Some(poll) && !poll() {
    return reject(Fenced)
  }
  let continuation = retained_effect is Some(original) &&
    physical_equal(@strategy.captured_effect_run_dag(original), run) &&
    @strategy.graph_program_has_effects(graph)
  if @strategy.graph_captured_prefix(graph) != first ||
    (
      !continuation &&
      (
        (first == 0 && !@strategy.graph_source_free_inputs_complete(graph)) ||
        @strategy.graph_program_has_effects(graph) ||
        @strategy.next_captured_task(run) != Some(first)
      )
    ) {
    return reject(UnsupportedGraph)
  }
  guard @builtin.configured_local_module(
      @builtin.configured_host_modules(setup),
    )
    is Some(installed) else {
    return reject(MissingLocalModule)
  }
  for _ in first..<count {
    if !current() {
      return reject(Fenced)
    }
    // This entry starts the exact managed candidate below. The installed
    // fallback estimator belongs to the legacy prepare-next-task boundary;
    // its full materializing envelope cannot preflight this managed request.
    // The retained Model can have completed intermediate tasks already. None
    // only ends dispatch here; the original Result output is still required.
    if continuation && @strategy.next_captured_task(run) is None {
      break
    }
    guard @strategy.next_captured_task(run) is Some(index) &&
      index >= first &&
      index < count &&
      tasks[index] is None &&
      @strategy.graph_task_owner(graph, index) is Some(_) else {
      return reject(UnsupportedGraph)
    }
    // Carrier snapshots remain with their existing physical Store owner.
    // This entry does not turn a missing Carrier custody into row storage.
    if @local_driver.local_dispatch_next_carrier_path(installed) {
      return reject(UnsupportedGraph)
    }
    let producers = @strategy.captured_next_managed_producers(run)
    let inputs : Array[@local_driver.LocalManagedAvailableOutput[Int]] = []
    for producer in producers {
      if continuation && producer == -1 {
        inputs.push(@local_driver.local_managed_supplied_relation_input())
        continue
      }
      if continuation &&
        producer >= 0 &&
        producer < count &&
        tasks[producer] is None &&
        @strategy.captured_task_completed(run, producer) {
        // The common DAG binds the receiver to this exact original output.
        // This does not fabricate a ManagedCompletedOutput or its provider.
        inputs.push(@local_driver.local_managed_captured_relation_input())
        continue
      }
      if first == 1 && producer == 0 {
        inputs.push(@local_driver.local_managed_captured_relation_input())
        continue
      }
      guard producer >= first &&
        producer < count &&
        tasks[producer] is Some(task) &&
        task.completed is Some(output) else {
        return reject(MissingOutput)
      }
      inputs.push(@local_driver.local_managed_relation_output(output))
    }
    let obligations = match
      @strategy.captured_next_managed_obligations(
        run,
        @host_driver.compute_host_max_entries(
          @builtin.configured_host_runtime(setup),
        ),
      ) {
      Ok(value) => value
      Err(_) => return reject(Driver(Configuration(InvalidLimits)))
    }
    let prepared = match
      @local_driver.prepare_local_managed_dispatch_with_outputs(
        installed, inputs, obligations, 0L,
      ) {
      Ok(Some(value)) => value
      Ok(None) => return reject(UnsupportedGraph)
      Err(issue) => return reject(Driver(issue))
    }
    if !current() {
      return reject(Fenced)
    }
    if continuation {
      match
        @strategy.select_captured_managed_registration(
          run,
          index,
          @local_driver.local_dispatch_registration(installed),
        ) {
        Ok(_) => ()
        Err(issue) => return reject(Driver(Execution(issue)))
      }
    }
    let operations = match
      @local_driver.start_local_managed_dispatch_node(
        prepared,
        on_relation_commit=if sample_tasks.contains(index) {
          on_relation_commit
        } else {
          None
        },
      ) {
      Ok(value) => value
      Err(issue) => return reject(Driver(issue))
    }
    // Retain actual operations before the next current callback can fail.
    let task : LocalValuesTaskExecution = {
      operations,
      settled: false,
      completed: None,
    }
    tasks[index] = Some(task)
    if !current() {
      return reject(Fenced)
    }
    if !operations.retained_inputs.is_empty() {
      return reject(UnsupportedGraph)
    }
    for transfer in operations.inputs {
      if !current() {
        return reject(Fenced)
      }
      let input = @execution.managed_producer_read_input_index(transfer.input)
      guard input >= 0 &&
        input < producers.length() &&
        tasks[producers[input]] is Some(producer) &&
        producer.completed is Some(output) &&
        @execution.managed_producer_read_matches_reference(
          transfer.input,
          @execution.managed_completed_reference(output),
        ) else {
        return reject(MissingOutput)
      }
      for row in 0..<@execution.managed_completed_output_row_count(output) {
        if !live() {
          return reject(Fenced)
        }
        let wire = match (producer.operations.output_row)(row) {
          Ok(value) => value
          Err(issue) => return reject(Driver(issue))
        }
        match (transfer.append)(wire) {
          Ok(_) => ()
          Err(issue) => return reject(Driver(issue))
        }
      }
      if !current() {
        return reject(Fenced)
      }
      match (transfer.finish)() {
        Ok(_) => ()
        Err(issue) => return reject(Driver(issue))
      }
      if !current() {
        return reject(Fenced)
      }
    }
    if !current() {
      return reject(Fenced)
    }
    if component_compute_quantum == 0 {
      match (operations.execute)() {
        Ok(_) => ()
        Err(issue) => return reject(Driver(issue))
      }
    } else {
      let mut executed = false
      for _ in 0..<max_finalization_rounds {
        if !live() {
          return reject(Fenced)
        }
        let progress = match (operations.advance)(component_compute_quantum) {
          Ok(value) => value
          Err(issue) => {
            println("node-component advance task=" + index.to_string())
            return reject(Driver(issue))
          }
        }
        if progress.complete {
          executed = true
          break
        }
        if progress.work <= 0L {
          break
        }
      }
      if !executed {
        return reject(FinalizationLimit)
      }
    }
    if component_after_compute is Some(snapshot) {
      match snapshot(operations, index) {
        Ok(_) => ()
        Err(issue) => return reject(Driver(issue))
      }
    }
    if !current() {
      return reject(Fenced)
    }
    match
      (operations.prepare_finalization)(index, operations.storage_bytes, live) {
      Ok(_) => ()
      Err(issue) => {
        println("node-component prepare-finalization task=" + index.to_string())
        return reject(Driver(issue))
      }
    }
    if !current() {
      return reject(Fenced)
    }
    let mut complete = false
    for _ in 0..<max_finalization_rounds {
      if !live() {
        return reject(Fenced)
      }
      let progress = match
        (operations.advance_finalization)(finalization_quantum) {
        Ok(value) => value
        Err(issue) => {
          println(
            "node-component advance-finalization task=" + index.to_string(),
          )
          return reject(Driver(issue))
        }
      }
      if progress.complete {
        complete = true
        break
      }
      if progress.work <= 0L {
        break
      }
    }
    if !current() {
      return reject(Fenced)
    }
    if !complete {
      return reject(FinalizationLimit)
    }
    match (operations.settle)() {
      Ok(_) => task.settled = true
      Err(issue) => return reject(Driver(issue))
    }
    if !current() {
      return reject(Fenced)
    }
    task.completed = match
      (operations.complete)(index, operations.storage_bytes, live) {
      Ok(value) => Some(value)
      Err(issue) => return reject(Driver(issue))
    }
    if !current() {
      return reject(Fenced)
    }
  }
  if @strategy.next_captured_task(run) is Some(_) {
    return reject(UnsupportedGraph)
  }
  let result = match retained_effect {
    None => @strategy.graph_result_task(graph, 0).unwrap_or(count - 1)
    Some(original) =>
      // A Model introduces its own retained Result root. The Effect's primary
      // output is selected from its checked source ports, not that Model root.
      @strategy.captured_effect_run_source_at(original, 0)
      .map(@strategy.checked_effect_source_task)
      .unwrap_or(-1)
  }
  guard result >= 0 &&
    result < count &&
    tasks[result] is Some(primary) &&
    primary.completed is Some(completed) else {
    return reject(MissingOutput)
  }
  let lookup = fn(task : Int) {
    guard tasks.get(task) is Some(Some(original)) &&
      original.completed is Some(output) else {
      return None
    }
    Some((original.operations, output))
  }
  let cleanup = () => close_local_values_tasks(run, tasks)
  Ok({
    run,
    operations: primary.operations,
    completed,
    available,
    tasks: Some((lookup, cleanup)),
  })
}

///|
test "collection actual default Request codec reloads 100000 from the same receipt and finite parent" {
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(1073741824L),
    execution_bytes=Some(1073741824L),
  ).unwrap()
  collection_request_publication_case(
    100000,
    false,
    source_free_max_work=Some(30000000),
    initial_limits=Some(limits),
    actual_request_profile=true,
  )
}

///|
test "actual default Request giant scalar array executes before SDK row-retention refusal" {
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(1073741824L),
    execution_bytes=Some(1073741824L),
  ).unwrap()
  collection_request_publication_case(
    1,
    false,
    source_free_max_work=Some(30000000),
    initial_limits=Some(limits),
    simple=true,
    actual_request_profile=true,
    giant_elements=Some(20000),
  )
}

///|
test "selected 100000 collection retains exact original Capture work cause and cleanup" {
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
    retained_bytes=Some(1073741824L),
    execution_bytes=Some(1073741824L),
  ).unwrap()
  let original : Ref[LocalValuesExecutionIssue?] = Ref(None)
  collection_request_publication_case(
    100000,
    false,
    source_free_max_work=Some(100000),
    initial_limits=Some(limits),
    actual_request_profile=true,
    diagnostic_failure=Some(original),
  )
  guard original.val is Some(Driver(issue)) else {
    fail("original typed Driver failure missing")
  }
  guard issue
    is @local_driver.Configuration(
      @connector.Execution(
        @execution.Capture(
          step,
          @execution.CaptureWorkRefusal(limit, remaining)
        )
      )
    ) else {
    fail("expected the original typed Capture work refusal")
  }
  assert_eq(step, 41)
  assert_eq(limit, 100000)
  // A complete attempted value can exceed the remaining slice before zero.
  // Keep original remaining-work DATA distinct from control or memory limits.
  assert_true(remaining >= 0 && remaining < limit)
  println(
    "COLLECTION_ORIGINAL_CAPTURE_WORK " +
    @debug.to_string((step, limit, remaining)),
  )
  assert_eq(
    @local_driver.local_managed_advance_capture_work(issue),
    Some([41, 100000]),
  )
  assert_eq(@local_driver.local_managed_advance_control_work_limit(issue), None)
}
