///|
test "cold authoring uses the same recovery Request capacity original and retirement" {
  let f = request_serialized_model_fixture(serialized=false)
  let input = [189]
  let current = Ref(true)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => current.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_model_recovery_materials(
    owner,
    input,
    f.request,
    f.definition,
    1,
    _ => "{}",
    1,
  ).unwrap()
  let capacity = owner.capacity
  let before = @resources.ledger_usage(owner.ledger)
  let compiler = @publication_host.client_standard_effect_computation_limits().program
  let original = prepare_request_model_recovery_authoring_context(
    owner,
    input,
    f.request,
    f.definition,
    f.prepared,
    f.compiled,
    compiler,
  ).unwrap()
  assert_true(owner.phase == ModelRecovery)
  assert_true(physical_equal(owner.capacity, capacity))
  assert_true(owner.program_capacity is None && owner.compiled_program is None)
  assert_true(
    physical_equal(
      original,
      prepare_request_model_recovery_authoring_context(
        owner,
        input,
        f.request,
        f.definition,
        f.prepared,
        f.compiled,
        compiler,
      ).unwrap(),
    ),
  )
  let evidence = @publication_host.prepared_client_authoring_context_evidence(
    f.prepared,
    original,
    1000000,
    100000,
    64,
  ).unwrap()
  assert_true(
    @publication.run_evidence_value_json(evidence).contains(
      "\"annotations\":[]",
    ),
  )
  assert_true(
    prepare_request_model_recovery_authoring_context(
      owner,
      [189],
      f.request,
      f.definition,
      f.prepared,
      f.compiled,
      compiler,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  let after = @resources.ledger_usage(owner.ledger)
  assert_true(after.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_eq(after.live_reservations, before.live_reservations)
  current.val = false
  assert_true(
    prepare_request_model_recovery_authoring_context(
      owner,
      input,
      f.request,
      f.definition,
      f.prepared,
      f.compiled,
      compiler,
    )
    is Err(Preparation(Capacity(_))),
  )
  current.val = true
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(owner.program_authoring is None)
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
}

///|
test "saved Model constructors share original restoration reservation without a new compiler or Run" {
  let (_, request, definition) = capture_recovery_originals()
  let input = [181]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let original = owner.capacity
  let before = @resources.ledger_usage(owner.ledger)
  let calls = Ref(0)
  let observed = Ref(true)
  for bodies in [["{\"saved\":true}"], ["{}", "{}", "{}"], ["{}", "{}", "{}"]] {
    let previous = @resources.ledger_usage(owner.ledger)
    reserve_request_model_recovery_materials(
      owner,
      input,
      request,
      definition,
      bodies.length(),
      index => {
        observed.val = observed.val && owner.phase == Selecting
        observed.val = observed.val &&
          reserve_request_model_recovery_materials(
            owner,
            input,
            request,
            definition,
            0,
            _ => "",
            0,
          )
          is Err(ForeignOriginal)
        calls.val += 1
        bodies[index]
      },
      bodies.length(),
    ).unwrap()
    let after = @resources.ledger_usage(owner.ledger)
    assert_true(
      after.reserved_retention_bytes > previous.reserved_retention_bytes,
    )
    assert_true(
      after.reserved_execution_bytes >= previous.reserved_execution_bytes,
    )
    assert_eq(after.live_reservations, before.live_reservations)
    assert_eq(after.attempts, before.attempts)
    assert_eq(after.transferred_bytes, before.transferred_bytes)
    assert_true(physical_equal(owner.capacity, original))
    assert_true(
      owner.program_capacity is None && owner.compiled_program is None,
    )
    assert_true(
      owner.program_compilation is None && owner.program_check is None,
    )
    assert_true(owner.phase == ModelRecovery)
  }
  assert_eq(calls.val, 7)
  assert_true(observed.val)
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
  assert_true(owner.phase == Closed)
}

///|
test "saved Model reservation rejects foreign pair and current refusal before reading another material" {
  let (_, request, definition) = capture_recovery_originals()
  let (_, foreign, foreign_definition) = capture_recovery_originals()
  let input = [182]
  let current = Ref(true)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => current.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_model_recovery_materials(
    owner,
    input,
    request,
    definition,
    1,
    _ => "{}",
    1,
  ).unwrap()
  let retained = @resources.ledger_usage(owner.ledger)
  let calls = Ref(0)
  for
    (selected_input, selected_request, selected_definition) in [
      ([182], request, definition),
      (input, foreign, definition),
      (input, request, foreign_definition),
    ] {
    assert_true(
      reserve_request_model_recovery_materials(
        owner,
        selected_input,
        selected_request,
        selected_definition,
        1,
        _ => {
          calls.val += 1
          "{}"
        },
        1,
      )
      is Err(ForeignOriginal),
    )
    assert_eq(@resources.ledger_usage(owner.ledger), retained)
  }
  current.val = false
  assert_true(
    reserve_request_model_recovery_materials(
      owner,
      input,
      request,
      definition,
      1,
      _ => {
        calls.val += 1
        "{}"
      },
      1,
    )
    is Err(Capacity(_)),
  )
  assert_eq(calls.val, 0)
  current.val = true
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "saved Model growth failure keeps original capacity and physical cleanup pending" {
  let (_, request, definition) = capture_recovery_originals()
  let input = [183]
  let pending = Ref(false)
  let owner = begin_request_preparation(
    request_parent_fixture(input, pending=() => pending.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_model_recovery_materials(
    owner,
    input,
    request,
    definition,
    1,
    _ => "{}",
    1,
  ).unwrap()
  let previous = @resources.ledger_usage(owner.ledger)
  assert_true(
    reserve_request_model_recovery_materials(
      owner,
      input,
      request,
      definition,
      1,
      _ => "x".repeat(1000000),
      1,
    )
    is Err(Capacity(_)),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), previous)
  pending.val = true
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(_))
  assert_true(owner.phase == Retiring && owner.input is None)
  pending.val = false
  // A later empty callback cannot fabricate the original stop ACK.
  assert_true(abort_request_preparation_after_cleanup(owner) is Err(Initial(_)))
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
// Original checked compiler/Graph from the existing fixture, then a distinct
// physical-process Request parent. No compiler is entered by recovery here.
test "cold Model Scope binds the original recovery Request census and ledger without a replacement Run" {
  let f = request_serialized_model_fixture(serialized=false)
  let input = [188]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_model_recovery_materials(
    owner,
    input,
    f.request,
    f.definition,
    1,
    _ => "{}",
    1,
  ).unwrap()
  let original = owner.capacity
  let ledger = request_model_recovery_ledger(
    owner,
    input,
    f.request,
    f.definition,
  ).unwrap()
  assert_true(physical_equal(ledger, owner.ledger))
  let before = @resources.ledger_usage(ledger)
  let scopes = prepare_request_model_recovery_read_scopes(
    owner,
    input,
    f.request,
    f.definition,
    f.prepared,
    f.compiled,
    [f.graph],
    effect_model_plan_limits,
    [7L],
    [5L],
    20,
    20,
    20,
  ).unwrap()
  assert_eq(scopes.length(), 1)
  assert_true(physical_equal(owner.capacity, original))
  assert_true(owner.program_capacity is None && owner.compiled_program is None)
  assert_true(owner.program_compilation is None && owner.program_model is None)
  assert_true(owner.phase == ModelRecovery)
  let scope = scopes[0]
  let identity = @resources.preparation_capacity_inventory_original(
    original, input,
  ).unwrap()
  assert_true(
    @publication_host.client_model_read_scope_original_inventory(
      scope, ledger, identity,
    ),
  )
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.transferred_bytes, before.transferred_bytes)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_true(after.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_false(
    @publication_host.client_compiled_run_infer_originals_match(f.compiled, []),
  )
  assert_false(
    @publication_host.client_compiled_run_infer_originals_match(f.compiled, [
      f.graph,
      f.graph,
    ]),
  )
  let read = @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  @publication_host.stop_client_model_read(read).unwrap()
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      f.compiled,
      f.definition,
      f.graph,
      true,
    ).unwrap(),
  )
  assert_true(
    @resources.preparation_capacity_working_usage_isolated(
      owner.capacity,
      input,
      ledger,
    ),
  )
  assert_false(
    @resources.preparation_capacity_working_usage_isolated(
      owner.capacity,
      [188],
      ledger,
    ),
  )
  assert_false(
    @resources.preparation_capacity_working_usage_isolated(
      owner.capacity,
      input,
      f.parent.ledger,
    ),
  )
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
}

///|
test "saved material geometry keeps long text distinct from original Value slots" {
  let observe = (text : String) => {
    let cursor = @decode.admit_raw_json(
      @json.parse(text),
      {
        start_byte: 0,
        end_byte: text.length(),
        start_line: 1,
        start_column: 1,
        end_line: 1,
        end_column: text.length() + 1,
        source_path: "<original-material>",
      },
      {
        max_nodes: 20,
        max_depth: 4,
        max_string_bytes: 20000,
        max_total_string_bytes: 20000,
      },
    ).unwrap()
    cursor
  }
  let short = "{\"program\":\"x\"}"
  let long = "{\"program\":\"" + "x".repeat(10000) + "\"}"
  let short_cursor = observe(short)
  let long_cursor = observe(long)
  let a = @decode.observe_subtree_construction_geometry(short_cursor)
  let b = @decode.observe_subtree_construction_geometry(long_cursor)
  assert_eq(a.nodes, 2)
  assert_eq(b.nodes, 2)
  assert_eq(b.total_utf16 - a.total_utf16, 9999L)
  let old_a = request_model_recovery_capacity(short.length().to_int64() * 3L, 1).unwrap()
  let old_b = request_model_recovery_capacity(long.length().to_int64() * 3L, 1).unwrap()
  let new_a = request_model_recovery_material_capacity(
    short,
    a,
    @decode.admission_usage(short_cursor).depth,
    1,
  ).unwrap()
  let new_b = request_model_recovery_material_capacity(
    long,
    b,
    @decode.admission_usage(long_cursor).depth,
    1,
  ).unwrap()
  // Six original decoded-text roles and four canonical-wire roles grow;
  // neither Value-slot nor cursor-depth quantity changes with Text length.
  assert_eq(
    @execution.execution_capacity_retained_bytes(new_b) -
    @execution.execution_capacity_retained_bytes(new_a),
    9999L * (3L * 6L * 8L + 3L * 4L * 8L),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(new_b) <
    @execution.execution_capacity_retained_bytes(old_b),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(old_b) >
    @execution.execution_capacity_retained_bytes(old_a),
  )
  assert_true(
    request_model_recovery_material_capacity(
      long,
      b,
      @decode.admission_usage(long_cursor).depth,
      -1,
    )
    is None,
  )
  assert_true(request_model_recovery_capacity(-1L, 1) is None)
}

///|
test "saved structured Program quote uses original constructor inventory not literal text length" {
  let limits = @publication_host.client_standard_program_preparation_limits().checking.input
  let prefix = "{\"version\":\"actql/0.1\",\"id\":\"recovery-original\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"text\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"text\":\""
  let suffix = "\"}]},\"as\":\"seed\"}],\"results\":{\"rows\":{\"from\":\"seed\",\"fields\":[\"text\"]}}}],\"results\":{\"rows\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  let observe = (literal : String) => {
    let input = @syntax.parse_program_input(prefix + literal + suffix, limits).unwrap()
    let cursor = @syntax.program_input_cursor(input)
    let (inventory, spent) = @syntax.observe_program_constructor_inventory(
      cursor,
      @syntax.program_constructor_inspection_work_bound(input),
    )
    (inventory.unwrap(), @decode.admission_usage(cursor).depth, spent)
  }
  let (short, depth, short_work) = observe("x")
  let (long, long_depth, long_work) = observe("x".repeat(10000))
  assert_eq(short.retained, long.retained)
  assert_eq(depth, long_depth)
  assert_eq(short_work, long_work)
  let a = request_model_recovery_program_capacity(short, depth).unwrap()
  let b = request_model_recovery_program_capacity(long, long_depth).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(a),
    @execution.execution_capacity_retained_bytes(b),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(a),
    @execution.execution_capacity_execution_bytes(b),
  )
  // These borrowed original literals remain backed by the Source index;
  // the Program decoder allocates no additional Value forest for their text.
  assert_true(@execution.execution_capacity_retained_bytes(a) > 0L)
  assert_true(request_model_recovery_program_capacity(short, -1) is None)
}

///|
test "cold normalization admits only its saved original on the same recovery Request" {
  let f = request_serialized_model_fixture(serialized=false)
  let input = [190]
  let current = Ref(true)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => current.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_model_recovery_materials(
    owner,
    input,
    f.request,
    f.definition,
    1,
    _ => "{}",
    1,
  ).unwrap()
  let capacity = owner.capacity
  let before = @resources.ledger_usage(owner.ledger)
  let compiler = @publication_host.client_standard_effect_computation_limits().program
  let wire =
    #|{"entries":[],"journal_cid":"sha256:e245b445e5014e5764dab4bf1b9ddc3b3abdf821ddf75950f9bee9df29007164","rule_catalog_cid":"sha256:f93d91b468d850cbc63a8c8350578af8431a2256eb2b1ef3f60586fdc640561d","version":"actql-normalization-journal/0.1"}
  let original = prepare_request_model_recovery_normalization(
    owner,
    input,
    f.request,
    f.definition,
    f.prepared,
    wire,
    compiler,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(
      @publication_host.prepared_client_local_normalization_evidence(
        f.prepared,
        original,
      ).unwrap(),
    ),
    wire,
  )
  assert_true(physical_equal(owner.capacity, capacity))
  assert_true(owner.program_capacity is None && owner.compiled_program is None)
  assert_true(owner.phase == ModelRecovery)
  assert_true(
    physical_equal(
      original,
      prepare_request_model_recovery_normalization(
        owner,
        input,
        f.request,
        f.definition,
        f.prepared,
        wire,
        compiler,
      ).unwrap(),
    ),
  )
  assert_true(
    prepare_request_model_recovery_normalization(
      owner,
      input,
      f.request,
      f.definition,
      f.prepared,
      wire + " ",
      compiler,
    )
    is Err(Normalization(SubstitutedJournal)),
  )
  let after = @resources.ledger_usage(owner.ledger)
  assert_true(after.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_eq(after.live_reservations, before.live_reservations)
  current.val = false
  assert_true(
    prepare_request_model_recovery_normalization(
      owner,
      input,
      f.request,
      f.definition,
      f.prepared,
      wire,
      compiler,
    )
    is Err(Preparation(Capacity(_))),
  )
  current.val = true
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(owner.program_normalization is None)
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
}

///|
test "cold normalization refuses current before constructing an audit or saved evidence" {
  let f = request_serialized_model_fixture(serialized=false)
  let input = [191]
  let current = Ref(true)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => current.val),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_model_recovery_materials(
    owner,
    input,
    f.request,
    f.definition,
    1,
    _ => "{}",
    1,
  ).unwrap()
  current.val = false
  assert_true(
    prepare_request_model_recovery_normalization(
      owner,
      input,
      f.request,
      f.definition,
      f.prepared,
      "not evidence",
      @publication_host.client_standard_effect_computation_limits().program,
    )
    is Err(Preparation(Capacity(_))),
  )
  assert_true(owner.program_normalization.unwrap().audit is None)
  assert_true(
    @publication_host.prepared_client_local_normalization_original(f.prepared)
    is None,
  )
  current.val = true
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
}

///|
test "funded material inverse retains normalization and authoring on its one original restored preparation" {
  let f = request_serialized_model_fixture(serialized=false)
  // This component's existing warm compiler fixture supplies the actual issued
  // journal. The new inverse below owns its separate physical Request/Resource.
  @publication_host.issue_prepared_client_local_normalization(f.prepared).unwrap()
  |> ignore
  let (environment, _) = effect_model_plan_source()
  let limits : @publication_host.ClientValuesRunMaterialsLimits = {
    preparation: @publication_host.client_standard_program_preparation_limits(),
    sequence: @publication_host.client_standard_values_sequence_limits(),
    max_sequence_steps: 1000,
    max_sequence_work: 10000,
    max_evidence_bytes: 1000000,
    max_evidence_nodes: 100000,
    max_evidence_depth: 100,
  }
  let wire = @publication_host.issue_prepared_client_infer_run_materials(
    f.compiled,
    f.definition,
    environment,
    None,
    limits,
  ).unwrap()
  for valid in [true, false] {
    let input = [192]
    let owner = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    let selected = if valid {
      wire
    } else {
      wire.replace(old="serialized-model", new="changed-saved-run")
    }
    assert_true(valid || selected != wire)
    reserve_request_model_recovery_materials(
      owner,
      input,
      f.request,
      f.definition,
      1,
      _ => selected,
      4,
    ).unwrap()
    let capacity = owner.capacity
    let result = admit_request_model_recovery_materials(
      owner,
      input,
      f.request,
      f.definition,
      selected,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      request_program_module_manifests(),
      limits,
    )
    if valid {
      let (material, authoring) = result.unwrap()
      assert_false(physical_equal(material.prepared, f.prepared))
      assert_true(physical_equal(owner.capacity, capacity))
      let normalized = @publication_host.prepared_client_local_normalization_original(
        material.prepared,
      ).unwrap()
      assert_true(
        @publication_host.prepared_client_local_normalization_evidence(
          material.prepared,
          normalized,
        )
        is Ok(_),
      )
      assert_true(
        @publication_host.prepared_client_authoring_context_evidence(
          material.prepared,
          authoring,
          1000000,
          100000,
          100,
        )
        is Ok(_),
      )
      assert_true(
        @publication_host.prepared_client_authoring_context_evidence(
          f.prepared,
          authoring,
          1000000,
          100000,
          100,
        )
        is Err(ForeignOriginal),
      )
      assert_eq(
        @publication.publication_contract_identity(material.run_definition),
        @publication.publication_contract_identity(f.definition),
      )
    } else {
      // The existing inverse tries historical then composed graph profiles.
      // If neither full Run matches, it preserves the original first admission
      // refusal rather than replacing it with the last candidate's mismatch.
      assert_true(
        result
        is Err(Materials(Admission(@publication.RunAdmissionPreparedMismatch))),
      )
      assert_true(owner.program_normalization is Some(_))
      assert_true(owner.program_authoring is None)
    }
    assert_true(owner.phase == ModelRecovery)
    abort_request_preparation_after_cleanup(owner).unwrap()
    assert_true(
      owner.program_normalization is None && owner.program_authoring is None,
    )
    assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
  }
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
}

///|
test "warm INFER material serializer uses its original Request capacity and retains the same journal" {
  let f = request_serialized_model_fixture(serialized=false)
  let original = @publication_host.issue_prepared_client_local_normalization(
    f.prepared,
  ).unwrap()
  let capacity = f.parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(
    capacity,
    f.input,
  ).unwrap()
  let wire = issue_request_model_run_materials(
    f.parent,
    f.input,
    f.compiled,
    f.definition,
  ).unwrap()
  assert_true(wire.contains("normalization_journal_json"))
  assert_true(f.parent.phase == ModelPlanReserved)
  assert_true(physical_equal(capacity, f.parent.program_capacity.unwrap()))
  assert_true(
    physical_equal(
      original,
      @publication_host.prepared_client_local_normalization_original(f.prepared).unwrap(),
    ),
  )
  let after = @resources.preparation_capacity_working_extents(capacity, f.input).unwrap()
  assert_true(after.0 > before.0)
  assert_true(after.1 >= before.1)
  let unchanged = request_preparation_accounting(f.parent)
  assert_true(
    issue_request_model_run_materials(f.parent, [], f.compiled, f.definition)
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(request_preparation_accounting(f.parent), unchanged)
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "warm INFER material refusal preserves its original Request before codec entry" {
  let f = request_serialized_model_fixture(serialized=false)
  let capacity = f.parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(
    capacity,
    f.input,
  ).unwrap()
  let limits = @resources.ledger_limits(f.parent.ledger)
  let usage = @resources.ledger_usage(f.parent.ledger)
  let blocker = @resources.reserve_capacity(
    f.parent.ledger,
    limits.retained_bytes -
    usage.reserved_retention_bytes -
    (request_effect_material_control_bytes + 8L) +
    1L,
    0L,
  ).unwrap()
  assert_true(
    issue_request_model_run_materials(
      f.parent,
      f.input,
      f.compiled,
      f.definition,
    )
    is Err(Preparation(Capacity(Resource(RetentionLimit)))),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, f.input).unwrap(),
    before,
  )
  assert_true(f.parent.phase == ModelPlanReserved)
  assert_true(
    @publication_host.prepared_client_local_normalization_original(f.prepared)
    is None,
  )
  @resources.settle_capacity(f.parent.ledger, blocker).unwrap()
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "original material Plan view admits its one reference before the same callback" {
  for retention in [true, false] {
    let f = request_serialized_model_fixture(serialized=false)
    let capacity = f.parent.program_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity,
      f.input,
    ).unwrap()
    let limits = @resources.ledger_limits(f.parent.ledger)
    let usage = @resources.ledger_usage(f.parent.ledger)
    // Independent existing logical tariff: one reference, no extra object,
    // is8bytes. The original fixed codec census is unchanged for Effects.
    let added = request_effect_material_control_bytes + 8L
    let available = if retention {
      limits.retained_bytes - usage.held_bytes - usage.reserved_retention_bytes
    } else {
      limits.execution_bytes - usage.reserved_execution_bytes
    }
    let entered = Ref(0)
    let run = fn() -> Result[Unit, ClientRequestProgramPlanIssue] {
      construct_request_original_materials_owned(
        f.parent,
        f.input,
        capacity,
        () => {
          f.parent.phase == Selecting &&
          f.parent.input is Some(original) &&
          physical_equal(original, f.input)
        },
        retained_aliases=1L,
        _ => {
          entered.val += 1
          Ok(())
        },
      )
    }
    let blocked = @resources.reserve_capacity(
      f.parent.ledger,
      if retention {
        available - added + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        available - added + 1L
      },
    ).unwrap()
    let refusal = run()
    assert_true(
      if retention {
        refusal is Err(Preparation(Capacity(Resource(RetentionLimit))))
      } else {
        refusal is Err(Preparation(Capacity(Resource(ExecutionLimit))))
      },
    )
    assert_eq(entered.val, 0)
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, f.input).unwrap(),
      before,
    )
    @resources.settle_capacity(f.parent.ledger, blocked).unwrap()
    let exact = @resources.reserve_capacity(
      f.parent.ledger,
      if retention {
        available - added
      } else {
        0L
      },
      if retention {
        0L
      } else {
        available - added
      },
    ).unwrap()
    run().unwrap()
    assert_eq(entered.val, 1)
    assert_true(f.parent.phase == ModelPlanReserved)
    let after = @resources.preparation_capacity_working_extents(
      capacity,
      f.input,
    ).unwrap()
    assert_eq(after.0, before.0 + added)
    assert_eq(after.1, before.1 + added)
    @resources.settle_capacity(f.parent.ledger, exact).unwrap()
    assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
    abort_request_preparation_after_cleanup(f.parent).unwrap()
    assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
  }
}
