///|
test "first Effect append binds actual preparing bytes and leaves start unclaimed" {
  let now = 1500.0
  let at = @values.epoch_milliseconds_timestamp(now.to_int64()).unwrap()
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  let retention = issue_client_local_run_retention_policy(profile, at).unwrap()
  let until = @publication.result_retention_available_until(retention).unwrap()
  let reference = saved_snapshot_reference()
  let (prepared, base, _) = original_effect_materials_fixture(normalized=true)
  let (program, _, _) = client_composed_effect_base_fixture()
  let intent = prepare_client_submitted_intent(
    "{\"input\":" + program + ",\"kind\":\"program\",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let scope = client_submission_epoch_token_authority_scope_cid(reference.epoch)
  let request = prepare_client_effect_request_identity(
    prepared,
    scope,
    reference.request_id,
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    base.compilation,
    scope,
    "sha256:" + "a".repeat(64),
    until,
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "local", "first-effect-run", at, until,
  ).unwrap()
  let issued = issue_prepared_client_effect_normalization_materials(
    allowed,
    definition,
    issue_prepared_client_effect_normalization(prepared).unwrap(),
    request=Some(request),
  ).unwrap()
  let materials = bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  ).unwrap()
  let before = inventory_row(
    reference.request_id,
    client_submitted_intent_journal_row_body(reference.wire, intent).unwrap(),
    revision=7L,
  )
  let rows = [
    ("client_run_custody", inventory_row("issued", b"0", revision=17L)),
    ("client_submitted_intents", before),
  ]
  let read = (table, key) => inventory_read(rows, table, key)
  let snapshot = read_client_saved_submission(
      reference, read, run_append_validate, "custody",
    )
    .unwrap()
    .unwrap()
  fn project(current, cancel) {
    prepare_client_effect_run_journal_append(
      snapshot,
      intent,
      materials,
      profile,
      retention,
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
      now,
      1024,
      (table, key) => inventory_scan(rows, table, key),
      current,
      run_append_validate,
      cancel,
      "custody",
    )
  }
  assert_true(
    project(
      (table, key) => {
        if table == "client_submitted_intents" {
          Ok(Some({ ..before, revision: 8L, }))
        } else {
          read(table, key)
        }
      },
      () => Err("must not inspect cancellation"),
    )
    is Err(Observation("custody")),
  )
  assert_true(
    project(read, () => Err("cancel observation failed"))
    is Err(Observation("cancel observation failed")),
  )
  let candidate = project(read, () => Ok(())).unwrap()
  let (run, preparing, ready, locator) = client_effect_run_journal_append_rows(
    candidate,
  )
  assert_eq(preparing.revision, 7L)
  let transport = client_effect_run_journal_append_wire(candidate).unwrap()
  assert_true(transport.contains("\"preparing_revision\":\"7\""))
  assert_eq(preparing.body, before.body)
  let (key, body, issued_revision, issued_body) = client_run_journal_append_rows(
    run,
  )
  assert_eq(key, client_request_scope_cid(request))
  assert_eq((issued_revision, issued_body), (17L, b"1"))
  let (row, policy, observation) = decode_client_run_journal_row_with_observation_originals(
    body,
  ).unwrap()
  assert_true(policy is Some(_) && observation is Some(_))
  assert_false(
    row.dispatch_reserved ||
    row.physical_start_claimed ||
    row.cancellation_requested(),
  )
  assert_true(row.checkpoint is None)
  let packet = read_client_effect_material_journal_packet(
    row.effect_material_originals.unwrap(),
  ).unwrap()
  assert_eq(
    packet.materials_wire,
    client_effect_issued_normalization_materials_wire(issued),
  )
  assert_eq(packet.submission_reference, reference.wire)
  let observed = decode_client_submitted_journal_row(ready).unwrap()
  assert_eq(
    observed.run_admission,
    Some((request, @publication.publication_contract_identity(definition), 0L)),
  )
  assert_eq(observed.run_state_observation, Some((0L, None)))
  // A completed Store lookup for this same request is never a fresh append.
  let already = client_run_journal_row_body({
    ..row,
    effect_material_originals: None,
    publication_policy_originals: None,
  }).unwrap()
  assert_true(
    project(
      (table, id) => {
        if table == "client_runs" && id == key {
          Ok(Some(inventory_row(id, already)))
        } else {
          read(table, id)
        }
      },
      () => Err("must not inspect cancellation"),
    )
    is Err(ForeignRun),
  )
  let located = read_client_saved_run_reference(
    "local",
    scope,
    @publication.publication_contract_identity(definition),
    (table, id) => {
      match table {
        "client_run_reference_index" if id == locator.0 =>
          Ok(Some(inventory_row(id, locator.1)))
        "client_submitted_intents" if id == preparing.key =>
          Ok(Some(inventory_row(id, ready, revision=8L)))
        "client_runs" if id == key => Ok(Some(inventory_row(id, body)))
        _ => Err("wrong original")
      }
    },
    original => {
      if original.key == key && original.body == body && original.revision == 0L {
        Ok({
          request,
          definition,
          checkpoint: None,
          cancellation_head: None,
          task_materials_cid: None,
        })
      } else {
        Err("wrong Run")
      }
    },
    "custody",
  ).unwrap()
  assert_eq(client_saved_submission_row(located).body, ready)
  let original_locator = inventory_row(locator.0, locator.1)
  fn admit(saved, physical_locator) {
    client_first_effect_saved_admission_wire(
      snapshot, saved, materials, candidate, physical_locator,
    )
  }
  assert_true(admit(located, original_locator) is Ok(_))
  let changed_run = {
    ..located,
    run: Some(inventory_row(key, mutate_first_effect_row_body(body))),
  }
  assert_true(admit(changed_run, original_locator) is Err(CustodyLost))
  let changed_submission = {
    ..located,
    submission: {
      ..located.submission,
      body: mutate_first_effect_row_body(ready),
    },
  }
  assert_true(admit(changed_submission, original_locator) is Err(CustodyLost))
  let changed_locator = {
    ..original_locator,
    body: mutate_first_effect_row_body(locator.1),
  }
  assert_true(admit(located, changed_locator) is Err(CustodyLost))

  fn start(saved, authority, dispatch) {
    prepare_client_effect_first_start_step(
      snapshot,
      saved,
      materials,
      candidate,
      original_locator,
      authority,
      dispatch~,
    )
  }
  assert_true(
    start(located, false, None) is Err(Observation(AuthorizationDenied)),
  )
  assert_true(start(changed_run, true, None) is Err(InvalidOriginal))
  assert_true(start(changed_submission, true, None) is Err(InvalidOriginal))
  let dispatch = start(located, true, None).unwrap()
  let (first, dispatch_body) = client_effect_first_start_step_row(dispatch)
  assert_eq((first.key, first.revision, first.body), (key, 0L, body))
  let dispatched = inventory_row(key, dispatch_body, revision=1L)
  assert_true(confirm_client_effect_first_start_step(dispatch, dispatched))
  assert_false(confirm_client_effect_first_start_step(dispatch, first))
  assert_false(
    confirm_client_effect_first_start_step(dispatch, {
      ..dispatched,
      body: mutate_first_effect_row_body(dispatched.body),
    }),
  )
  let reserved = { ..located, run: Some(dispatched), }
  assert_true(start(located, true, Some(dispatch)) is Err(InvalidOriginal))
  assert_true(start(reserved, true, None) is Err(InvalidOriginal))
  let claim = start(reserved, true, Some(dispatch)).unwrap()
  let (claimed_before, claim_body) = client_effect_first_start_step_row(claim)
  assert_eq((claimed_before.revision, claimed_before.body), (1L, dispatch_body))
  let (claimed, _, _) = decode_client_run_journal_row_with_observation_originals(
    claim_body,
  ).unwrap()
  assert_true(claimed.dispatch_reserved && claimed.physical_start_claimed)
  assert_eq(claimed.effect_material_originals, row.effect_material_originals)
  assert_true(
    confirm_client_effect_first_start_step(
      claim,
      inventory_row(key, claim_body, revision=2L),
    ),
  )
  assert_true(start(reserved, true, Some(claim)) is Err(InvalidOriginal))

  assert_eq(claimed.publication_binding, None)
  let binding = client_publication_store_binding_body(
    "local",
    "sha256:" + "b".repeat(64),
    11UL,
    22UL,
  ).unwrap()
  let definition_cid = @publication.publication_contract_identity(definition)
  let cp_limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 128,
    max_depth: 16,
  }
  let artifact = @checkpoint.seal_checkpoint(
    {
      checkpoint_id: "saved-effect",
      continuation_state_cid: "sha256:" + "1".repeat(64),
      subject: RunUnit(
        run_id="first-effect-run",
        unit_id=client_effect_compilation_unit_id(allowed.compilation),
        run_definition_cid=definition_cid,
      ),
      phase: Commit,
      kind: EffectSet,
      required_artifact_cid: "sha256:" + "2".repeat(64),
      review_projection_cid: "sha256:" + "3".repeat(64),
      requirements: [EffectScopeApproved],
      reason_code: "review_required",
      human_summary: "Original Effect",
      created_at: at,
      expires_at: until,
    },
    cp_limits,
  ).unwrap()
  let persisted = @checkpoint.confirm_checkpoint_persisted(
    artifact,
    artifact.wire,
  ).unwrap()
  let claimed_row = inventory_row(key, claim_body, revision=2L)
  let waiting_step = prepare_client_effect_waiting_step(
    materials,
    candidate,
    claim,
    claimed_row,
    artifact,
    persisted,
    ("local", "sha256:" + "b".repeat(64), 11UL, 22UL),
    at,
    true,
  ).unwrap()
  assert_true(
    prepare_client_effect_waiting_step(
      materials,
      candidate,
      claim,
      { ..claimed_row, revision: 3L, },
      artifact,
      persisted,
      ("local", "sha256:" + "b".repeat(64), 11UL, 22UL),
      at,
      true,
    )
    is Err(ForeignOriginal),
  )
  let waiting = inventory_row(key, waiting_step.body, revision=3L)
  let witness = waiting_step.witness
  let cp_location = waiting_step.locator
  let actual_rows = [
    ("client_run_reference_index", original_locator),
    (
      "client_submitted_intents",
      inventory_row(preparing.key, ready, revision=8L),
    ),
    ("client_runs", waiting),
    ("client_effect_custody", witness),
    ("client_checkpoint_id_index", cp_location),
  ]
  fn observe(rows, store, fund) {
    read_client_waiting_effect_original(
      "local",
      scope,
      definition_cid,
      store,
      (table, key) => inventory_read(rows, table, key),
      row => {
        decode_client_run_journal_row_with_observation_originals(row.body)
        .map(decoded => decoded.0)
        .map_err(_ => "decode")
      },
      "custody",
      fund,
    )
  }
  let view = observe(actual_rows, binding, (_, _, _) => Ok(())).unwrap()
  assert_eq(view.checkpoint.artifact.wire, artifact.wire)
  let summary = @encode.writer(8192, 50, 4)
  assert_true(view.write_summary(summary))
  let body = @encode.finish(summary)
  assert_true(body.contains(artifact.checkpoint_cid))
  assert_true(body.contains("first-effect-run"))
  assert_true(
    observe(actual_rows, binding + "foreign", (_, _, _) => Ok(()))
    is Err("custody"),
  )
  assert_true(
    observe(actual_rows, binding, (_, _, _) => Err("budget")) is Err("budget"),
  )
  for
    (table, original) in [
      ("client_runs", waiting),
      ("client_checkpoint_id_index", cp_location),
    ] {
    let changed = actual_rows.map(pair => {
      if pair.0 == table {
        (table, { ..original, revision: original.revision + 1L, })
      } else {
        pair
      }
    })
    assert_true(
      observe(changed, binding, (_, _, _) => Ok(())) is Err("custody"),
    )
  }
  let decided_at = @values.epoch_milliseconds_timestamp((now + 1).to_int64()).unwrap()
  let resolution = reject_first_effect_fixture(
    artifact, definition_cid, scope, decided_at, cp_limits,
  )
  let cancelled = @checkpoint.issue_waiting_exit_run_state(
    "first-effect-run",
    decided_at,
    view.checkpoint.declared_results,
    [],
    cp_limits,
  ).unwrap()
  let checkpoint = client_checkpoint_journal_row_body({
    ..view.checkpoint,
    updated_at: decided_at,
    state: @checkpoint.admit_run_state_wire(cancelled, cp_limits).unwrap(),
    resolution_cid: Some(resolution.resolution_cid),
    verified_wire: Some(resolution.wire),
  }).unwrap()
  let (before_decision, policy, observation) = decode_client_run_journal_row_with_observation_originals(
    waiting.body,
  ).unwrap()
  let decided_run = { ..before_decision, checkpoint: Some(checkpoint), }
  let decided = inventory_row(
    key,
    client_run_journal_row_body(
      decided_run,
      local_run_policy_originals=policy,
      run_observation_originals=observation,
    ).unwrap(),
    revision=4L,
  )
  let decided_rows = actual_rows.map(pair => {
    if pair.0 == "client_runs" {
      (pair.0, decided)
    } else {
      pair
    }
  })
  fn observe_decision(row, rows, store, fund) {
    observe_client_decided_effect_checkpoint(
      "local",
      scope,
      store,
      row,
      decided_run,
      (table, id) => inventory_read(rows, table, id),
      "custody",
      fund,
    )
  }
  let (inspection, state) = observe_decision(decided, decided_rows, binding, (
    _,
    _,
    _,
  ) => Ok(())).unwrap()
  assert_true(
    client_request_identity_relation(inspection.request, request) == SameRequest,
  )
  assert_true(inspection.checkpoint is Some(entries) && entries.is_empty())
  assert_true(state.contains("\"status\":\"cancelled\""))
  assert_true(state.contains("\"revision\":4"))
  assert_true(
    observe(decided_rows, binding, (_, _, _) => Ok(())) is Err("custody"),
  )
  assert_true(
    observe_decision(waiting, actual_rows, binding, (_, _, _) => Ok(()))
    is Err("custody"),
  )
  assert_true(
    observe_decision(decided, decided_rows, binding + "foreign", (_, _, _) => {
      Ok(())
    })
    is Err("custody"),
  )
  assert_true(
    observe_decision(decided, decided_rows, binding, (_, _, _) => Err("budget"))
    is Err("budget"),
  )
  assert_true(
    observe_decision(decided, actual_rows, binding, (_, _, _) => Ok(()))
    is Err("custody"),
  )
  for table in ["client_checkpoint_id_index", "client_effect_custody"] {
    let changed = decided_rows.map(pair => {
      if pair.0 == table {
        (table, { ..pair.1, revision: pair.1.revision + 1L, })
      } else {
        pair
      }
    })
    assert_true(
      observe_decision(decided, changed, binding, (_, _, _) => Ok(()))
      is Err("custody"),
    )
  }
}

///|
// The portable Common fixture checks DATA binding without a physical signer.
fn reject_first_effect_fixture(
  artifact : @checkpoint.SealedCheckpoint,
  definition_cid : String,
  scope : String,
  at : String,
  limits : @checkpoint.WireLimits,
) -> @checkpoint.VerifiedResolution {
  let actor = "fixture-reviewer"
  let key = "fixture-reviewer-key"
  let signature = "A".repeat(86) + "=="
  let unsigned = try {
    let writer = @encode.writer(4096, 64, 8)
    @encode.begin_object(writer)
    for
      (field, item) in [
        ("version", "actql-checkpoint-resolution/0.1"),
        ("actor", actor),
        ("checkpoint_cid", artifact.checkpoint_cid),
        ("checkpoint_id", artifact.checkpoint.checkpoint_id),
        ("decided_at", at),
        ("decision", "rejected"),
        ("required_artifact_cid", artifact.checkpoint.required_artifact_cid),
        ("review_projection_cid", artifact.checkpoint.review_projection_cid),
        ("resolution_id", "fixture-resolution"),
        ("run_definition_cid", definition_cid),
        ("run_id", "first-effect-run"),
      ] {
      @encode.key(writer, field)
      @encode.string_value(writer, item)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => panic()
  }
  let proof = @checkpoint.prepare_resolution_proof(artifact, unsigned, limits).unwrap()
  let signed = @checkpoint.seal_prepared_resolution_proof(proof, key, signature).unwrap()
  let admitted = @checkpoint.admit_checkpoint_resolution(
    artifact,
    signed,
    None,
    {
      key_id: key,
      reviewer_id: actor,
      expected_authority_scope_cid: scope,
      authority_context_cid: scope,
      policy_cid: "sha256:" + "5".repeat(64),
      proof_preimage: proof.preimage(),
    },
    [{ key_id: key, reviewer_id: actor, }],
    at,
    limits,
  ).unwrap()
  @checkpoint.seal_verified_resolution(
    admitted, "fixture-host-key", signature, limits,
  ).unwrap()
}

///|
fn mutate_first_effect_row_body(body : Bytes) -> Bytes {
  Bytes::from_array(
    Array::makei(body.length(), index => {
      if index == 0 {
        b'!'
      } else {
        body[index]
      }
    }),
  )
}
