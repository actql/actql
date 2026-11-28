///|
fn saved_model_journal_rows(
  run : NativeClientRunRecord,
  store_authority : String,
  binding : String,
  slot : Int,
  observation? : String? = None,
  dependency? : NativeModelEntryDependency? = None,
  attachment? : Bool = false,
) -> (String, String, Bytes, Bytes) raise {
  let id = @publication.publication_contract_identity(run.definition)
  let context = @publication.publication_contract_json(run.definition)
  let source = @source.parse_json_bytes_preserving(@utf8.encode(context), {
    max_input_bytes: 65536,
    max_nodes: 1024,
    max_depth: 32,
  }).unwrap()
  let cursor = @decode.admit(source, {
    max_nodes: 1024,
    max_depth: 32,
    max_string_bytes: 65536,
    max_total_string_bytes: 65536,
  }).unwrap()
  let fields = @decode.open_object(cursor).unwrap()
  let context_cid = epoch_text(fields, "authorization_context_cid").unwrap()
  let task = "sha256:" + "a".repeat(64)
  let fixed = "sha256:" + "b".repeat(64)
  let program = "sha256:" + "c".repeat(64)
  let scope = "sha256:" + "d".repeat(64)
  let input = "sha256:" + "e".repeat(64)
  let call_wire =
    $|{"effective_inputs_cid":"\{input}","fixed_request_cid":"\{fixed}","input_artifact_cid":"\{input}","input_key_cid":"\{input}","model_task_cid":"\{task}","program_definition_cid":"\{program}","source_ordinal":\{slot},"unit_definition_cid":"\{program}","version":"actql-model-call-slot/0.1"}
  let call = @publication.seal_run_evidence_value(
    "model_call_slot", call_wire, 16384, 256, 8,
  ).unwrap()
  let slot_cid = @publication.run_evidence_value_identity(call)
  let authority_wire =
    $|{"account_configuration_cid":"\{program}","answering_authority":null,"basis":"account_allow","connection":"models/fixture","entry_id":"fixture","execution_context_cid":"\{context_cid}","fixed_request_cid":"\{fixed}","host_policy_cid":"\{input}","model_invocation_scope_cid":"\{scope}","model_task_cid":"\{task}","operation":"infer","principal":"fixture-principal","program_definition_cid":"\{program}","resource":"\{task}","run_authorization_cid":"\{input}","run_definition_cid":"\{id}","satisfied_claims":[],"version":"actql-model-dispatch-authority/0.1"}
  let authority = @publication.seal_run_evidence_value(
    "model_dispatch_authority", authority_wire, 16384, 256, 8,
  ).unwrap()
  let authority_cid = @publication.run_evidence_value_identity(authority)
  let attempt_wire =
    $|{"attempt":1,"authority_evidence_cid":"\{authority_cid}","fixed_request_cid":"\{fixed}","model_task_cid":"\{task}","provider_id":"models/fixture","run_definition_cid":"\{id}","slot_cid":"\{slot_cid}","version":"actql-model-call-attempt/0.1"}
  let attempt = @publication.seal_run_evidence_value(
    "model_call_attempt", attempt_wire, 16384, 256, 8,
  ).unwrap()
  let attempt_cid = @publication.run_evidence_value_identity(attempt)
  let entry = native_model_entry_body(
    run.request,
    run.definition,
    slot,
    call,
    attempt,
    authority,
    65536,
    dependency~,
  ).unwrap()
  if dependency is Some(_) {
    assert_eq(
      native_model_entry_body(
        run.request,
        run.definition,
        slot,
        call,
        attempt,
        authority,
        entry.length(),
        dependency~,
      ).unwrap(),
      entry,
    )
    assert_true(
      native_model_entry_body(
        run.request,
        run.definition,
        slot,
        call,
        attempt,
        authority,
        entry.length() - 1,
        dependency~,
      )
      is Err(CapacityExceeded),
    )
  }
  let digest = "sha256:" + @sha.hex(entry)
  let request = @host.client_request_scope_cid(run.request)
  let raw_cid = "sha256:" +
    @sha.hex(@utf8.encode("fixture-raw-" + slot.to_string()))
  let roles = [
    ("model_call_attempt", attempt_cid),
    ("model_attempt_accounting", fixed),
    ("model_attempt_outcome", task),
    ("model_dispatch_authority", authority_cid),
    ("model_slot_capture", input),
  ]
  if observation is Some(cid) {
    roles.push(("model_invocation_evidence", cid))
  }
  roles.push(("model_raw_response", raw_cid))
  if attachment {
    roles.push(("model_attachment_admission", fixed))
  }
  roles.push(("model_capture_bundle", program))
  let leaves : Array[String] = []
  for (role, cid) in roles {
    let holding = @publication.model_scoped_private_holding_cid(
      run.definition,
      store_authority,
      scope,
      slot_cid,
      attempt_cid,
      1,
      "settled",
      role,
    ).unwrap()
    let leaf =
      $|{"cid":"\{cid}","holding_cid":"\{holding}","role":"\{role}"}
    leaves.push(leaf)
  }
  let evidence = leaves.join(",")
  let settlement =
    $|{"attempt_cid":"\{attempt_cid}","entry_digest":"\{digest}","request_scope_cid":"\{request}","run_definition_cid":"\{id}","scope_cid":"\{scope}","store_binding":"\{binding}","version":"actql-native-model-call-settlement-original/0.1","slot":\{slot},"evidence":[\{evidence}]}
  (attempt_cid, raw_cid, entry, @utf8.encode(settlement))
}

///|
test "saved Model failure Journal points bind the original Entry and selected settlement" {
  let (database, journal, request) = journal_start_operation_fixture(
    "r13-saved-model-settlement-points",
  )
  let store = "sha256:" + "f".repeat(64)
  let binding = "fixture-publication"
  let run = {
    ..journal.retained(request).unwrap().unwrap(),
    dispatch_reserved: true,
    physical_start_claimed: true,
    publication_binding: Some(binding),
  }
  let first = saved_model_journal_rows(run, store, binding, 0)
  let adjacent = saved_model_journal_rows(run, store, binding, 1)
  assert_true(first.0 != adjacent.0)
  for (attempt, _, entry, settlement) in [first, adjacent] {
    database.insert("client_model_call_originals", attempt, entry).unwrap()
    |> ignore
    database
    .insert("client_model_call_settlements", attempt, settlement)
    .unwrap()
    |> ignore
  }
  let cap = first.2.length().to_int64() + first.3.length().to_int64()
  let calls : Array[String] = []
  let reads = journal_test_read_access(database, calls)
  let select = (authority, locator : (String, String), maximum) => {
    journal.transaction_with_reads(
      () => {
        journal.read_saved_model_settlement_locked(
          run,
          binding,
          authority,
          SavedFailure(locator.0, locator.1),
          maximum,
          reads,
        )
      },
      reads=Some(reads),
    )
  }
  let locator = (first.0, first.1)
  let selected = select(store, locator, cap).unwrap()
  assert_eq(selected.raw_cid, first.1)
  assert_eq(@publication.run_evidence_value_identity(selected.attempt), first.0)
  assert_eq(calls, [
    "fenced",
    "begin",
    "read-bounded:client_model_call_originals:" + first.0,
    "read-bounded:client_model_call_settlements:" + first.0,
    "commit",
  ])
  assert_true(select(store, locator, cap - 1L) is Err(CapacityExceeded))
  assert_eq(
    select(store, locator, cap + 1L).unwrap().slot_cid,
    selected.slot_cid,
  )
  assert_true(
    select(store, (adjacent.0, first.1), cap + 1L) is Err(CustodyLost),
  )
  assert_true(
    select("sha256:" + "1".repeat(64), locator, cap) is Err(CustodyLost),
  )
  // Identical bytes written at a stale successor are still a different
  // physical row. The point reader cannot expose the old diagnosis from it.
  database
  .compare_exchange("client_model_call_settlements", first.0, 0L, first.3)
  .unwrap()
  |> ignore
  assert_true(select(store, locator, cap) is Err(CustodyLost))
  database.close_checked().unwrap()
}

///|
test "dependent Model success Journal points select the exact originating slot and full success inventory" {
  let (database, journal, request) = journal_start_operation_fixture(
    "r6-saved-model-dependency-points",
  )
  let store = "sha256:" + "f".repeat(64)
  let binding = "fixture-publication"
  let scope_cid = "sha256:" + "d".repeat(64)
  let observation_cid = "sha256:" + "1".repeat(64)
  let second_observation = "sha256:" + "2".repeat(64)
  let dependency : NativeModelEntryDependency = {
    scope: scope_cid,
    ports: [
      {
        input: 0,
        stage: 1,
        step: 2,
        artifact: "sha256:" + "3".repeat(64),
        manifest: "sha256:" + "4".repeat(64),
        producer_scope: "sha256:" + "5".repeat(64),
      },
      {
        input: 1,
        stage: 1,
        step: 2,
        artifact: "sha256:" + "3".repeat(64),
        manifest: "sha256:" + "4".repeat(64),
        producer_scope: "sha256:" + "5".repeat(64),
      },
    ],
    producers: [
      {
        scope: "sha256:" + "5".repeat(64),
        slots: [
          (
            0,
            "sha256:" + "6".repeat(64),
            "sha256:" + "7".repeat(64),
            "sha256:" + "8".repeat(64),
          ),
        ],
      },
    ],
  }
  let run = {
    ..journal.retained(request).unwrap().unwrap(),
    dispatch_reserved: true,
    physical_start_claimed: true,
    publication_binding: Some(binding),
  }
  let first = saved_model_journal_rows(
    run,
    store,
    binding,
    0,
    observation=Some(observation_cid),
  )
  let adjacent = saved_model_journal_rows(
    run,
    store,
    binding,
    1,
    observation=Some(second_observation),
    attachment=true,
  )
  let failure = saved_model_journal_rows(
    run,
    store,
    binding,
    2,
    attachment=true,
  )
  let dependent = saved_model_journal_rows(
    run,
    store,
    binding,
    3,
    observation=Some(observation_cid),
    dependency=Some(dependency),
  )
  for (attempt, _, entry, settlement) in [first, adjacent, failure, dependent] {
    database.insert("client_model_call_originals", attempt, entry).unwrap()
    |> ignore
    database
    .insert("client_model_call_settlements", attempt, settlement)
    .unwrap()
    |> ignore
  }
  let first_cap = first.2.length().to_int64() + first.3.length().to_int64()
  let adjacent_cap = adjacent.2.length().to_int64() +
    adjacent.3.length().to_int64()
  let calls : Array[String] = []
  let reads = journal_test_read_access(database, calls)
  let select = (authority, selection, maximum) => {
    journal.transaction_with_reads(
      () => {
        journal.read_saved_model_settlement_locked(
          run, binding, authority, selection, maximum, reads,
        )
      },
      reads=Some(reads),
    )
  }
  let exact : NativeSavedModelSuccessSelection = {
    slot: 0,
    scope_cid,
    observation_cid,
    dependency: None,
  }
  let requested = DependentSuccess(first.0, exact)
  let selected = select(store, requested, first_cap).unwrap()
  assert_eq(selected.raw_cid, first.1)
  assert_eq(selected.success.unwrap().observation_cid, observation_cid)
  assert_eq(selected.success.unwrap().bundle_cid, "sha256:" + "c".repeat(64))
  let limits = @model.model_call_settlement_export_limits(1048576, 100000)
  // Only sizing runs here. The existing Bundle decoder checks its content
  // after the original finite allowance has been accepted.
  let bundle_wire = "x".repeat(1911)
  let bundle_nodes = bundle_wire.length()
  let quote : Ref[(Int64, Int64, Int64)?] = Ref(None)
  let execution_limit = Ref(9223372036854775807L)
  let funded = {
    ..reads,
    before_metadata_construction: Some((retained, execution, block) => {
      quote.val = Some((retained, execution, block))
      if execution > execution_limit.val {
        Err(CapacityExceeded)
      } else {
        Ok(())
      }
    }),
  }
  let fund_bundle = maximum => {
    fund_native_saved_model_leaf(
      funded,
      bundle_wire,
      maximum,
      bundle_nodes,
      limits.max_depth,
      capture_bundle=true,
    )
  }
  assert_true(
    fund_native_saved_model_leaf(
      funded,
      bundle_wire,
      limits.max_bytes,
      bundle_nodes,
      limits.max_depth,
    )
    is Err(CustodyLost),
  )
  assert_true(quote.val is None)
  assert_true(fund_bundle(bundle_wire.length() - 1) is Err(CustodyLost))
  assert_true(quote.val is None)
  fund_bundle(limits.max_bytes).unwrap()
  let (retained, execution, block) = quote.val.unwrap()
  assert_true(retained > 0L && execution > retained && block > 0L)
  execution_limit.val = execution - 1L
  assert_true(fund_bundle(limits.max_bytes) is Err(CapacityExceeded))
  execution_limit.val = execution
  fund_bundle(limits.max_bytes).unwrap()
  assert_eq(quote.val, Some((retained, execution, block)))
  assert_eq(calls, [
    "fenced",
    "begin",
    "read-bounded:client_model_call_originals:" + first.0,
    "read-bounded:client_model_call_settlements:" + first.0,
    "commit",
  ])
  assert_true(select(store, requested, first_cap - 1L) is Err(CapacityExceeded))
  assert_eq(
    select(
      store,
      DependentSuccess(adjacent.0, {
        ..exact,
        slot: 1,
        observation_cid: second_observation,
      }),
      adjacent_cap,
    ).unwrap().raw_cid,
    adjacent.1,
  )
  assert_true(
    select(
      store,
      DependentSuccess(adjacent.0, { ..exact, slot: 1, }),
      adjacent_cap,
    )
    is Err(CustodyLost),
  )
  assert_true(
    select(store, DependentSuccess(first.0, { ..exact, slot: 1, }), first_cap)
    is Err(CustodyLost),
  )
  assert_true(
    select(
      store,
      DependentSuccess(first.0, { ..exact, scope_cid: second_observation, }),
      first_cap,
    )
    is Err(CustodyLost),
  )
  assert_true(
    select(second_observation, requested, first_cap) is Err(CustodyLost),
  )
  assert_true(
    select(store, SavedFailure(first.0, first.1), first_cap) is Err(CustodyLost),
  )
  assert_true(
    select(
      store,
      DependentSuccess(failure.0, { ..exact, slot: 2, }),
      adjacent_cap,
    )
    is Err(CustodyLost),
  )
  assert_true(
    select(store, SavedFailure(failure.0, failure.1), adjacent_cap).unwrap().success
    is None,
  )
  let dependent_cap = dependent.2.length().to_int64() +
    dependent.3.length().to_int64()
  let dependent_selection = DependentSuccess(dependent.0, {
    ..exact,
    slot: 3,
    dependency: Some(dependency),
  })
  assert_eq(
    select(store, dependent_selection, dependent_cap).unwrap().raw_cid,
    dependent.1,
  )
  assert_true(
    select(store, dependent_selection, dependent_cap - 1L)
    is Err(CapacityExceeded),
  )
  assert_true(
    select(
      store,
      DependentSuccess(dependent.0, { ..exact, slot: 3, }),
      dependent_cap,
    )
    is Err(CustodyLost),
  )
  let changed = {
    ..dependency,
    ports: [
      dependency.ports[0],
      { ..dependency.ports[1], manifest: "sha256:" + "9".repeat(64), },
    ],
  }
  assert_true(
    select(
      store,
      DependentSuccess(dependent.0, {
        ..exact,
        slot: 3,
        dependency: Some(changed),
      }),
      dependent_cap,
    )
    is Err(CustodyLost),
  )
  assert_true(
    select(store, SavedFailure(dependent.0, dependent.1), dependent_cap)
    is Err(CustodyLost),
  )
  let observe_entry = (attempt, digest, maximum) => {
    journal.transaction_with_reads(
      () => {
        journal.read_dependent_model_entry_locked(
          attempt, digest, maximum, reads,
        )
      },
      reads=Some(reads),
    )
  }
  let bundle = "sha256:" + "c".repeat(64)
  let original_a = ReferencedSuccess(scope_cid, (0, first.0, first.1, bundle))
  assert_eq(
    select(store, original_a, first_cap).unwrap().success.unwrap().bundle_cid,
    bundle,
  )
  assert_true(
    select(store, original_a, first_cap - 1L) is Err(CapacityExceeded),
  )
  assert_true(
    select(second_observation, original_a, first_cap) is Err(CustodyLost),
  )
  for
    reference in [
      ReferencedSuccess(scope_cid, (0, adjacent.0, first.1, bundle)),
      ReferencedSuccess(scope_cid, (0, first.0, adjacent.1, bundle)),
      ReferencedSuccess(scope_cid, (0, first.0, first.1, adjacent.1)),
      ReferencedSuccess(second_observation, (0, first.0, first.1, bundle)),
      ReferencedSuccess(scope_cid, (2, failure.0, failure.1, bundle)),
    ] {
    assert_true(select(store, reference, dependent_cap) is Err(CustodyLost))
  }
  let from_prior_model = ReferencedSuccess(
    scope_cid,
    (3, dependent.0, dependent.1, bundle),
  )
  assert_eq(
    select(store, from_prior_model, dependent_cap).unwrap().raw_cid,
    dependent.1,
  )
  let extent = dependent.2.length().to_int64()
  let digest = "sha256:" + @sha.hex(dependent.2)
  assert_eq(observe_entry(dependent.0, digest, extent).unwrap(), dependent.2)
  let restored = observe_entry(dependent.0, digest, extent)
    .bind(body => {
      admit_native_saved_dependent_model_entry(reads, run, body, dependent.0)
    })
    .unwrap()
  assert_eq(restored.scope, dependency.scope)
  assert_eq(restored.ports.length(), 2)
  assert_eq(restored.ports[1].manifest, dependency.ports[1].manifest)
  assert_eq(restored.producers[0].slots, dependency.producers[0].slots)
  assert_true(
    admit_native_saved_dependent_model_entry(reads, run, dependent.2, first.0)
    is Err(CustodyLost),
  )
  assert_true(
    admit_native_saved_dependent_model_entry(reads, run, first.2, first.0)
    is Err(CustodyLost),
  )

  assert_true(
    observe_entry(dependent.0, digest, extent - 1L) is Err(CapacityExceeded),
  )
  assert_true(
    observe_entry(dependent.0, "sha256:" + "0".repeat(64), extent)
    is Err(CustodyLost),
  )
  assert_true(
    observe_entry("sha256:" + "0".repeat(64), digest, extent)
    is Err(CustodyLost),
  )
  database
  .compare_exchange("client_model_call_originals", dependent.0, 0L, dependent.2)
  .unwrap()
  |> ignore
  assert_true(
    select(store, dependent_selection, dependent_cap) is Err(CustodyLost),
  )
  assert_true(observe_entry(dependent.0, digest, extent) is Err(CustodyLost))
  database
  .compare_exchange("client_model_call_settlements", first.0, 0L, first.3)
  .unwrap()
  |> ignore
  assert_true(select(store, requested, first_cap) is Err(CustodyLost))
  database.close_checked().unwrap()
}
