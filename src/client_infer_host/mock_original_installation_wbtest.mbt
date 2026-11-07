///|
// Explicit fixture Account and synthetic original byte grants exercise the
// complete portable caller. They are not an adopted installed Account/profile.
fn original_mock_fixture(
  calls : Ref[Int],
  document? : String = infer_fixture_program,
  entry_unknown? : Bool = false,
  shared_parent? : @resources.LedgerLimits? = None,
  shared_sibling? : Ref[@resources.CapacityReservation?]? = None,
  purpose_ledger? : @resources.LedgerLimits? = None,
  expected_purpose_issue? : @resources.LedgerIssue? = None,
  restored_input? : Bool = false,
  restored_custody? : () -> Bool = () => true,
) -> (
  Execution,
  @model.ModelMockInstallation,
  @environment.ModelMockProfile,
  @publication_host.ClientModelReadPreparation,
  @resources.Ledger,
  Ref[@authorization.AdmittedAccountConfiguration],
  Ref[String],
) raise {
  let limits : @environment.ModelTaskLimits = {
    bodies: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_members: 1000,
    },
    contracts: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    max_work: 10000000,
  }
  let declaration = @environment.read_public_model_task_document(
    (
      #|{"task":"model-task:mock.v1","model":{"provider":"not-installed","name":"ignored"},"input":{"text":{"type":"string","nullable":true}},"output":{"reason":{"type":"string","nullable":true},"risk":{"type":"string","enum":["high","low"]}},"instructions":"original mock"}
    ),
    "json",
    limits,
  ).unwrap()
  let profile = @environment.install_model_mock_profile(limits).unwrap()
  let normalized = @environment.normalize_public_mock_model_task(
    declaration, profile, limits,
  ).unwrap()
  let (wire, cid, _) = @environment.read_project_public_model_task_environment(
    infer_fixture_environment,
    infer_fixture_environment_cid,
    [normalized],
    limits,
  ).unwrap()
  let environment = @publication_host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let source = document.replace(
    old="model-task:risk-score.v1",
    new="model-task:mock.v1",
  )
  let prepared_program = @publication_host.prepare_effect_free_client_program(
    source,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let answers = @model.read_model_mock_answer_document(
    declaration,
    (
      #|{"task":"model-task:mock.v1","answers":{"default":{"reason":null,"risk":"high"},"by_key":{"a":{"reason":null,"risk":"low"}}}}
    ),
    "json",
    {
      document: limits.bodies,
      values: { max_nodes: 100, max_depth: 16, max_text_bytes: 1000, },
      max_entries: 10,
      max_work: 1000000,
    },
  ).unwrap()
  let now = Ref("2026-10-12T00:00:00.000Z")
  let installation = @model.install_original_model_mock(
    profile,
    declaration,
    normalized,
    answers,
    () => {
      calls.val += 1
      now.val
    },
  ).unwrap()
  let provider = @model.original_model_mock_provider(installation).unwrap()
  assert_true(@model.model_provider_synchronous_invoke(provider) is None)
  let execution_materials = @environment.model_mock_execution_materials(
    profile, normalized, limits,
  ).unwrap()
  let execution = @publication_host.read_prepared_client_infer_model_execution(
    prepared_program,
    2,
    @utf8.encode(execution_materials.0),
    execution_materials.1,
    limits.bodies,
    limits.max_work,
  ).unwrap()
  // Admit the actual same-Task prompt and both empty policies through the
  // existing dependency Owner, not fixture hashes or a Host policy table.
  let prompt = @environment.normalized_public_model_task_materials(normalized)
  let dependencies = @environment.read_single_attempt_model_dependencies(
    execution,
    Some(@utf8.encode(prompt.2)),
    Some(@utf8.encode(execution_materials.2)),
    Some(@utf8.encode(execution_materials.4)),
    limits.bodies,
    limits.max_work,
  ).unwrap()
  @model.admit_original_model_mock_provider(
    installation, execution, dependencies,
  ).unwrap()
  |> ignore
  let plan = @publication_host.issue_prepared_client_infer_plan_graph(
    prepared_program,
    2,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  ).unwrap()
  // Keep the existing fixture's original 4/133072 grant unchanged and select
  // those same limits before both read and startup. The Mock contract is a
  // ceiling, never permission to enlarge or replace the helper's original.
  let original_limits = standard_limits()
  let original_limits = {
    ..original_limits,
    model: {
      ..original_limits.model,
      ledger: purpose_ledger.unwrap_or_else(() => {
        ..original_limits.model.ledger,
        attempts: 4,
        transfer_bytes: 133072L,
      }),
    },
  }
  let (compiled, definition, ledger, read) = match shared_parent {
    None => original_funded_start_read(prepared_program, plan, original_limits)
    Some(parent) => {
      let (compiled, definition) = original_input_capacity_run(
        prepared_program, plan,
      )
      let ledger = @resources.create_ledger(parent).unwrap()
      let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
      let scope = @publication_host.begin_client_model_read_scope(
        compiled, definition, plan, ledger, bootstrap, 8, 2, 0,
      ).unwrap()
      if shared_sibling is Some(retained) {
        retained.val = Some(
          @resources.reserve_capacity(ledger, 20L, 10L).unwrap(),
        )
      }
      @resources.charge_planning(ledger, 17).unwrap()
      let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
      (compiled, definition, ledger, read)
    }
  }
  let attempted = if restored_input {
    // The original input and its identity scan issue the snapshot. Restore
    // under this same compiled Run/Plan before entering the real Mock; caller
    // rows and a claimed saved-scope Boolean never issue this input.
    let (input, _, scope) = original_input_capacity_fixture(
      prepared_program, plan,
    )
    let output = @input.client_infer_completed_input(input).unwrap()
    let binding = @publication_host.client_infer_plan_graph_request_cid(plan)
    let exported = @input.export_client_infer_retained_input(output, binding).unwrap()
    let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
      prepared_program,
    ).unwrap()
    let saved = @publication_host.read_client_infer_saved_call_scope(
      compiled,
      definition,
      occurrence,
      plan,
      @publication_host.client_infer_call_scope_snapshot(scope).unwrap(),
      "sha256:" + "a".repeat(64),
      restored_custody,
    ).unwrap()
    let prefix = @input.prepare_client_composed_infer_prefix(
      prepared_program,
      occurrence,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
    ).unwrap()
    assert_true(@input.cleanup_client_infer_input(input).unwrap())
    let consumer = @publication_host.claim_client_model_read_preparation(
      read, compiled, definition, plan, 7L, 5L,
    ).unwrap()
    start_original_restored_composed(
      occurrence,
      plan,
      prefix,
      provider,
      binding,
      @input.client_infer_retained_input_export_descriptor(exported),
      @input.client_infer_retained_input_export_rows(exported),
      restored_custody,
      saved,
      original_limits,
      compiled,
      definition,
      consumer,
      7L,
      5L,
      100L,
      5L,
    )
  } else if shared_parent is Some(_) {
    let consumer = @publication_host.claim_client_model_read_preparation(
      read, compiled, definition, plan, 7L, 5L,
    ).unwrap()
    let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
      prepared_program,
    ).unwrap()
    let prefix = @input.prepare_client_composed_infer_prefix(
      prepared_program,
      occurrence,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
    ).unwrap()
    start_original_composed(
      occurrence,
      plan,
      prefix,
      [],
      provider,
      original_limits,
      compiled,
      definition,
      consumer,
      7L,
      5L,
      100L,
      5L,
    )
  } else {
    original_funded_start_from_read(
      prepared_program,
      2,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
      provider,
      original_limits,
      compiled,
      definition,
      plan,
      read,
      7L,
      5L,
      100L,
      5L,
    )
  }
  let active = match attempted {
    Ok(active) => active
    Err(OriginalCapacity(issue)) => {
      debug_inspect(issue)
      abort("original capacity start refused")
    }
    Err(Model(issue)) => {
      debug_inspect(issue)
      abort("original model start refused")
    }
    Err(Input(_)) => abort("original input start refused")
    Err(Capacity(_)) => abort("original Host capacity start refused")
    Err(CallScope(_)) => abort("original call scope start refused")
    Err(IdentityExport(_)) => abort("original identity export start refused")
    Err(InvalidAdvance) => abort("original start invalid advance")
  }
  require_model_call_entry(active).unwrap()
  let execution_contract = @publication_host.client_infer_plan_graph_execution_contract(
    plan,
  )
  let egress = @publication_host.admit_prepared_client_infer_egress(
    prepared_program,
    2,
    execution_contract,
    () => {
      Some({
        classification: @environment.Public,
        region: "host-local-fixture",
        provider_retention: false,
        training_use: false,
      })
    },
  ).unwrap()
  bind_egress_admission(active, egress).unwrap()
  let prefix_work = match fixture_finish(active) {
    Waiting(work~) => {
      assert_true(expected_purpose_issue is None)
      work
    }
    Failed(Model(@model.Ledger(issue)), ..) if expected_purpose_issue ==
      Some(issue) =>
      return (
        active,
        installation,
        profile,
        read,
        ledger,
        Ref(evidence_account(@authorization.Allow)),
        now,
      )
    Failed(Model(issue), ..) => {
      debug_inspect(issue)
      abort("original mock must prepare before dispatch")
    }
    _ => abort("original mock must wait before dispatch")
  }
  assert_true(prefix_work > 0L)
  let prepared = prepared_call_set(active).unwrap()
  let slots = 1
  assert_eq(@model.prepared_model_call_count(prepared), Some(slots))
  let artifact = @model.prepared_model_input_artifact(prepared).unwrap()
  let (_, task_cid, _) = @model.prepared_model_identities(prepared).unwrap()
  let originals = @environment.model_mock_profile_originals(profile).unwrap()
  let current = Ref(evidence_account(@authorization.Allow))
  let root = "sha256:" + "a".repeat(64)
  let provider = @publication.seal_run_evidence_value(
    "model_provider_binding",
    fixture_canonical(
      Json::object({
        "version": Json::string("actql-model-provider-binding/0.1"),
        "provider_id": Json::string("mock"),
        "installation_revision_cid": Json::string(originals.1),
        "configuration_contract_cid": Json::string(originals.3),
        "configuration_cid": Json::string(originals.5),
      }),
    ),
    16384,
    1024,
    20,
  ).unwrap()
  let plan = active.plan.unwrap()
  let boundary : @publication.ModelInvocationBoundary = {
    unit_id: @publication_host.client_infer_call_scope_unit_id(
      active.call_scope.unwrap(),
    ).unwrap(),
    task_index: @publication_host.client_infer_occurrence_coordinates(
      active.occurrence,
    ).0.to_int64(),
    strategy_revision: 0L,
    inference_barrier_cid: @publication_host.client_infer_plan_graph_barrier_cid(
      plan,
    ),
    account_id: "infer-fixture",
    configuration_cid: current.val.configuration_cid(),
    entry_id: "model-policy",
    principal: "fixture-principal",
    connection: "mock",
    resource: task_cid,
    context_cid: root,
    installation_revision_cid: originals.1,
    configuration_contract_cid: originals.3,
    provider_configuration_cid: originals.5,
  }
  let scope = @publication.seal_run_evidence_value(
    "model_invocation_scope",
    fixture_canonical(
      Json::object({
        "version": Json::string("actql-model-invocation-scope/0.1"),
        "run_definition_cid": Json::string(
          @publication.publication_contract_identity(definition),
        ),
        "task_index": Json::number(boundary.task_index.to_double()),
        "strategy_revision": Json::number(0),
        "inference_barrier_cid": Json::string(boundary.inference_barrier_cid),
        "input_artifact_cid": Json::string(
          @publication.run_evidence_value_identity(artifact),
        ),
        "model_call_slot_cids": Json::array(
          Array::makei(slots, slot => {
            Json::string(
              @publication.run_evidence_value_identity(
                @model.prepared_model_call_at(prepared, slot).unwrap(),
              ),
            )
          }),
        ),
        "provider_binding_cid": Json::string(
          @publication.run_evidence_value_identity(provider),
        ),
        "authorization_context": Json::object({
          "account_id": Json::string(boundary.account_id),
          "configuration_cid": Json::string(boundary.configuration_cid),
          "entry_id": Json::string(boundary.entry_id),
          "principal": Json::string(boundary.principal),
          "connection": Json::string(boundary.connection),
          "resource": Json::string(boundary.resource),
          "operation": Json::string("infer"),
          "boundary": Json::string("activation"),
          "context_cid": Json::string(boundary.context_cid),
        }),
      }),
    ),
    16384,
    1024,
    20,
  ).unwrap()
  let bound = bind_model_scope(active, prepared, scope, provider, boundary).unwrap()
  let admission = @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    current.val,
    "fixture-principal",
    now.val,
    model_scope=Some(bound),
    observe_current=() => Ok((current.val, now.val)),
  ).unwrap()
  assert_eq(calls.val, 0)
  if entry_unknown {
    bind_model_entry_persistence(active, prepared, admission, entry => {
      @model.model_call_entry_persistence(entry, prepared, () => @model.Unknown)
    }).unwrap()
  } else {
    bind_model_dispatch(active, prepared, admission, entry => {
      @model.acknowledge_model_call_entry(entry, prepared).unwrap() |> ignore
      true
    }).unwrap()
  }
  (active, installation, profile, read, ledger, current, now)
}

///|
test "actual original mock uses same Run entry typed enum output and child-first cleanup" {
  let calls = Ref(0)
  let (active, installation, profile, read, ledger, _, _) = original_mock_fixture(
    calls,
  )
  let before = @resources.ledger_usage(ledger)
  let work = match fixture_finish(active, initial_work=active.work) {
    Settling(_, work~) => work
    Failed(Model(issue), ..) => {
      debug_inspect(issue)
      abort("mock must retain original settlement")
    }
    _ => abort("mock must settle one original attempt")
  }
  assert_eq(calls.val, 1)
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
  let saved = capture(active).unwrap()
  assert_eq(saved.captures.length(), 1)
  assert_eq(saved.captures[0].provider_id, "mock")
  assert_eq(saved.captures[0].provider_model, Some("typed-answers"))
  assert_eq(saved.captures[0].input_tokens, Some(0L))
  assert_eq(saved.captures[0].output_tokens, Some(0L))
  assert_true(
    saved.captures[0].value.value is @admitted.Object(fields) &&
    @admitted.element_at(fields, 1) is Some(("risk", @admitted.Text("low"))),
  )
  assert_eq(@model.retire_original_model_mock(installation), Ok(false))
  assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts + 1)
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 0)
  assert_eq(
    @resources.ledger_usage(ledger).uncertain_transfer_bytes,
    before.uncertain_transfer_bytes,
  )
  assert_true(cleanup(active).unwrap())
  assert_eq(@model.retire_original_model_mock(installation), Ok(true))
  assert_true(@environment.retire_model_mock_profile(profile))
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
  assert_eq(calls.val, 1)
}

///|
test "actual original mock current revocation refuses before explicit default or override" {
  let calls = Ref(0)
  let (active, installation, profile, read, ledger, current, _) = original_mock_fixture(
    calls,
  )
  current.val = evidence_account(@authorization.Deny)
  assert_true(
    fixture_finish(active, initial_work=active.work)
    is Failed(Model(@model.Authorization(_)), ..),
  )
  assert_eq(calls.val, 0)
  assert_true(capture(active) is None)
  assert_true(cleanup(active).unwrap())
  assert_eq(@model.retire_original_model_mock(installation), Ok(true))
  assert_true(@environment.retire_model_mock_profile(profile))
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
}

///|
test "actual original mock defaults admit non-Text and composite typed keys" {
  let numeric = infer_fixture_program
    .replace(
      old="\"id\":{\"type\":\"string\",\"nullable\":false}",
      new="\"id\":{\"type\":\"number\",\"nullable\":false}",
    )
    .replace(old="\"id\":\"a\"", new="\"id\":1")
  let composite = infer_fixture_program
    .replace(old="\"key\":\"id\"", new="\"key\":[\"id\",\"text\"]")
    .replace(
      old="\"unique_by\":[\"id\"]",
      new="\"unique_by\":[\"id\",\"text\"]",
    )
    .replace(
      old="\"text\":{\"type\":\"string\",\"nullable\":true}",
      new="\"text\":{\"type\":\"string\",\"nullable\":false}",
    )
  for document in [numeric, composite] {
    let calls = Ref(0)
    let (active, installation, profile, read, ledger, _, _) = original_mock_fixture(
      calls,
      document~,
    )
    let work = match fixture_finish(active, initial_work=active.work) {
      Settling(_, work~) => work
      _ => abort("valid original tuple must reach explicit fallback settlement")
    }
    assert_true(
      @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
    )
    assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
    let saved = capture(active).unwrap()
    assert_eq(saved.captures.length(), 1)
    assert_true(
      saved.captures[0].value.value is @admitted.Object(fields) &&
      @admitted.element_at(fields, 1) is Some(("risk", @admitted.Text("high"))),
    )
    assert_eq(calls.val, 1)
    assert_true(cleanup(active).unwrap())
    assert_eq(@model.retire_original_model_mock(installation), Ok(true))
    assert_true(@environment.retire_model_mock_profile(profile))
    @publication_host.settle_client_model_read(read, true).unwrap()
    assert_true(
      @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
    )
  }
}

///|
test "actual mock missing and foreign key aliases refuse before default selection" {
  for missing in [true, false] {
    let calls = Ref(0)
    let (active, installation, profile, read, ledger, _, _) = original_mock_fixture(
      calls,
    )
    let prepared = prepared_call_set(active).unwrap()
    let request = @model.prepared_model_request(prepared, 0).unwrap()
    if missing {
      request.key.clear()
    } else {
      // Equal Text and Contract, but not the checked value retained by the
      // original prepared row/key proof.
      request.key[0] = @admitted.checked_text_value(
        "a",
        request.key[0].contract,
      ).unwrap()
    }
    let work = match fixture_finish(active, initial_work=active.work) {
      Settling(_, work~) => work
      _ => abort("invalid original key must produce a retained refused slot")
    }
    assert_true(
      @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
    )
    assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
    let outcomes = @model.acquire_model_outcomes(active.model.unwrap()).unwrap()
    assert_eq(
      @model.model_outcomes_outcome(outcomes, 0),
      Some("failed:refusal"),
    )
    assert_true(@model.release_model_outcomes(outcomes))
    assert_eq(calls.val, 0)
    assert_true(cleanup(active).unwrap())
    assert_eq(@model.retire_original_model_mock(installation), Ok(true))
    assert_true(@environment.retire_model_mock_profile(profile))
    @publication_host.settle_client_model_read(read, true).unwrap()
    assert_true(
      @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
    )
  }
}

///|
test "actual mock unconfirmed entry never consults answers or retries the original call" {
  let calls = Ref(0)
  let (active, installation, profile, read, ledger, _, _) = original_mock_fixture(
    calls,
    entry_unknown=true,
  )
  let stopped = fixture_finish(active, initial_work=active.work)
  assert_true(stopped is Failed(Model(@model.UnknownCalls), ..))
  assert_eq(calls.val, 0)
  assert_true(@model.model_execution_unknown_calls(active.model.unwrap()))
  assert_true(capture(active) is None)
  // Observing the same terminal owner cannot synthesize another attempt.
  assert_true(advance(active, 1) is Err(InvalidAdvance))
  assert_eq(calls.val, 0)
  assert_true(cleanup(active).unwrap())
  assert_eq(@model.retire_original_model_mock(installation), Ok(true))
  assert_true(@environment.retire_model_mock_profile(profile))
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
}
