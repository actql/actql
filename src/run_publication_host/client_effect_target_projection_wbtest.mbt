///|
fn target_projection_replace_raw_field(
  wire : String,
  field : String,
  replacement : String?,
) -> String raise @encode.EncodeFailure {
  let root = parse_plan_identity_value(wire, 1000000, 100000, 100).unwrap()
  let writer = @encode.writer(1000000, 100000, 100)
  @encode.begin_object(writer)
  for (name, value) in @canonical.object_fields(root).unwrap() {
    if name != field {
      @encode.key(writer, name)
      @canonical.emit_value(value, writer)
    }
  }
  if replacement is Some(wire) {
    @encode.key(writer, field)
    @canonical.emit_value(
      parse_plan_identity_value(wire, 1000000, 100000, 100).unwrap(),
      writer,
    )
  }
  @encode.end_object(writer)
  let value = parse_plan_identity_value(
    @encode.finish(writer),
    1000000,
    100000,
    100,
  ).unwrap()
  @canonical.stringify_value(value, 1000000, 100000, 100)
}

///|
fn target_projection_reseal(
  value : @publication.PublicationContract,
  selection_cid : String?,
) -> @publication.PublicationContract raise @encode.EncodeFailure {
  let body = target_projection_replace_raw_field(
    @publication.publication_contract_json(value),
    @publication.publication_contract_identity_field(value),
    None,
  )
  @publication.seal_publication_contract(
    @publication.publication_contract_name(value),
    target_projection_replace_raw_field(
      body,
      "effect_target_selections_cid",
      selection_cid.map(cid => "\"" + cid + "\""),
    ),
    1000000,
    100000,
    100,
  ).unwrap()
}

///|
test "selection projection is automatic and legacy absence changes no field set" {
  for published in [false, true] {
    let (owner, allowed, definition, _) = target_selection_fixture(published~)
    let expected = client_effect_target_selections_cid(owner)
    let compilation = allowed.compilation
    assert_eq(
      client_task_plan_target_selections_cid(
        compilation.compiled.plan,
        1000000,
        100000,
        100,
      ).unwrap(),
      expected,
    )
    assert_eq(
      @publication.publication_contract_effect_target_selections_cid(
        compilation.compiled.compiled_plan,
      ),
      expected,
    )
    assert_eq(
      @publication.publication_contract_effect_target_selections_cid(definition),
      expected,
    )
    assert_true(
      bind_client_effect_compiled_run(owner, allowed, definition) is Ok(_),
    )
    assert_true(
      client_effect_run_start_current(
        allowed, definition, "2026-10-09T00:00:01.000Z",
      ),
    )
    if !published {
      assert_false(
        @publication.publication_contract_json(definition).contains(
          "effect_target_selections_cid",
        ),
      )
      assert_false(
        @publication.publication_contract_json(
          compilation.compiled.compiled_plan,
        ).contains("effect_target_selections_cid"),
      )
    }
  }
  let (_, original, original_run, _) = target_selection_fixture()
  let (_, renamed, renamed_run, _) = target_selection_fixture(alias="customers")
  assert_eq(
    @publication.publication_contract_json(original_run),
    @publication.publication_contract_json(renamed_run),
  )
  assert_eq(
    @publication.publication_contract_json(
      original.compilation.compiled.compiled_plan,
    ),
    @publication.publication_contract_json(
      renamed.compilation.compiled.compiled_plan,
    ),
  )
}

///|
test "all selection presence combinations bind only exact Plan compilation and Run parity" {
  let (selected, _, _, _) = target_selection_fixture()
  let selected_cid = client_effect_target_selections_cid(selected)
  for plan_selected in [false, true] {
    let (owner, allowed, _, _) = target_selection_fixture(
      published=plan_selected,
    )
    for compiled_selected in [false, true] {
      let compiled = target_projection_reseal(
        allowed.compilation.compiled.compiled_plan,
        if compiled_selected {
          selected_cid
        } else {
          None
        },
      )
      let (prepared, authorization) = issue_client_allowed_run_evidence(
        allowed.compilation.compiled.template,
        compiled,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2026-10-10T00:00:00.000Z",
      ).unwrap()
      assert_eq(
        admit_prepared_client_effect_run_publication(
          owner,
          allowed.compilation.compiled.template,
          prepared,
          authorization,
          compiled,
        )
        is Ok(_),
        plan_selected == compiled_selected,
      )
      // The generic owner admits linked policy evidence, not compilation.
      // Even callers of that lower-level API cannot strip the Run projection
      // or bind it back to a selected prepared owner without exact parity.
      let admission = @publication.admit_run_publication(
        allowed.compilation.compiled.template,
        prepared,
        authorization,
        compiled,
      ).unwrap()
      let original = @publication.issue_run_definition(
        admission,
        "projection",
        "run",
        @publication.empty_initial_input_artifact_set_cid(),
        "2026-10-09T00:00:00.000Z",
        "2026-10-10T00:00:00.000Z",
        1000000,
        100000,
        100,
      ).unwrap()
      assert_eq(
        @publication.publication_contract_effect_target_selections_cid(original),
        if compiled_selected {
          selected_cid
        } else {
          None
        },
      )
      for run_selected in [false, true] {
        let run = target_projection_reseal(
          original,
          if run_selected {
            selected_cid
          } else {
            None
          },
        )
        assert_eq(
          @publication.run_publication_start_current(
            admission, run, "2026-10-09T00:00:01.000Z",
          ),
          compiled_selected == run_selected,
        )
        assert_eq(
          bind_prepared_client_effect_run(owner, admission, run) is Ok(_),
          plan_selected == compiled_selected &&
          compiled_selected == run_selected,
        )
      }
    }
  }
}

///|
test "reidentified compilation and Run projections cannot substitute original selection" {
  let (owner, allowed, definition, _) = target_selection_fixture()
  let foreign = Some("sha256:" + "f".repeat(64))
  let bounds = run_materials_limits()
  for replacement in [None, foreign] {
    let changed = target_projection_reseal(
      allowed.compilation.compiled.compiled_plan,
      replacement,
    )
    assert_true(
      admit_prepared_client_effect_compilation(
        owner,
        allowed.compilation.compiled.plan.plan.wire,
        allowed.compilation.compiled.plan.plan.fact_manifest_wire,
        @publication.run_evidence_value_json(
          allowed.compilation.compiled.template,
        ),
        @publication.publication_contract_json(changed),
        run_materials_manifests(),
        bounds.sequence,
        bounds.max_sequence_steps,
        bounds.max_sequence_work,
        bounds.max_evidence_bytes,
        bounds.max_evidence_nodes,
        bounds.max_evidence_depth,
      )
      is Err(MismatchedCompilation),
    )
  }
  let compiled = target_projection_reseal(
    allowed.compilation.compiled.compiled_plan,
    foreign,
  )
  let (prepared, authorization) = issue_client_allowed_run_evidence(
    allowed.compilation.compiled.template,
    compiled,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  assert_true(
    admit_prepared_client_effect_run_publication(
      owner,
      allowed.compilation.compiled.template,
      prepared,
      authorization,
      compiled,
    )
    is Err(@publication.RunAdmissionCheckedProgramMismatch),
  )
  let run = target_projection_reseal(definition, foreign)
  assert_false(
    @publication.run_publication_start_current(
      allowed.admission,
      run,
      "2026-10-09T00:00:01.000Z",
    ),
  )
  assert_true(
    bind_prepared_client_effect_run(owner, allowed.admission, run) is Err(_),
  )
  let identity = prepared_client_effect_identity(owner)
  assert_true(
    @publication.check_run_publication_program_binding(
      allowed.admission,
      run,
      identity.program_definition_cid,
      prepared_client_effect_computation_semantics_cid(owner),
      prepared_client_effect_computation_environment_cid(owner),
    )
    is Err(@publication.RunProgramForeignRun),
  )
}

///|
test "executable Plan selection removal and substitution cannot be admitted with old compilation" {
  let (owner, allowed, _, _) = target_selection_fixture()
  let compilation = allowed.compilation.compiled
  let plan = compilation.plan.plan
  let body = parse_plan_identity_value(plan.wire, 1000000, 100000, 100).unwrap()
  let material = @canonical.stringify_value(
    @canonical.object_field(body, "execution_material").unwrap(),
    1000000,
    100000,
    100,
  )
  let selection = prepared_client_effect_target_selections(owner).unwrap()
  let changed = selection.replace(
    old="sha256:" + "9".repeat(64),
    new="sha256:" + "7".repeat(64),
  )
  let bounds = run_materials_limits()
  for replacement in [None, Some(changed), Some("[]")] {
    let material = target_projection_replace_raw_field(
      material, "effect_target_selections", replacement,
    )
    let wire = target_projection_replace_raw_field(
      target_projection_replace_raw_field(
        plan.wire,
        "execution_material",
        Some(material),
      ),
      "executable_plan_cid",
      None,
    )
    let body = parse_plan_identity_value(wire, 1000000, 100000, 100).unwrap()
    let cid = @canonical.cid_value(body, 1000000, 100000, 100)
    let wire = target_projection_replace_raw_field(
      wire,
      "executable_plan_cid",
      Some("\"" + cid + "\""),
    )
    let substituted : ClientTaskExecutablePlan = {
      plan: { ..plan, wire, cid, },
    }
    match
      client_task_plan_target_selections_cid(substituted, 1000000, 100000, 100) {
      Ok(cid) => assert_true(cid != client_effect_target_selections_cid(owner))
      Err(_) => ()
    }
    assert_true(
      admit_prepared_client_effect_compilation(
        owner,
        wire,
        plan.fact_manifest_wire,
        @publication.run_evidence_value_json(compilation.template),
        @publication.publication_contract_json(compilation.compiled_plan),
        run_materials_manifests(),
        bounds.sequence,
        bounds.max_sequence_steps,
        bounds.max_sequence_work,
        bounds.max_evidence_bytes,
        bounds.max_evidence_nodes,
        bounds.max_evidence_depth,
      )
      is Err(MismatchedCompilation),
    )
  }
}

///|
test "compiled Plan and Run projection match independent canonical preimage fixtures" {
  // Copied from the independent projection corpus, never product output.
  let vectors : Array[(String, String, String)] = [
    (
      "compiled_plan", "{\"aoa_contract_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"aoa_ir_version\":\"fixture\",\"aoa_logical_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"compiler_version\":\"fixture\",\"executable_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_definition_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"program_semantics_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"version\":\"actql-compiled-plan/0.1\"}",
      "sha256:df0ab99fce2b64b6c4df397351a0a9e73c8a45688ac6cd426c9c0184cd71f1f7",
    ),
    (
      "compiled_plan", "{\"aoa_contract_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"aoa_ir_version\":\"fixture\",\"aoa_logical_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"compiler_version\":\"fixture\",\"effect_target_selections_cid\":\"sha256:312e3ae46daa9cf148a228e668726d8f251e1f0035c796c882a51d76f3ba22db\",\"executable_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_definition_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"program_semantics_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"version\":\"actql-compiled-plan/0.1\"}",
      "sha256:428f9c45352ed0272a36c68dd847263ed9d90d4689a2c86ce0827ced72880617",
    ),
    (
      "compiled_plan", "{\"aoa_contract_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"aoa_ir_version\":\"fixture\",\"aoa_logical_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"compiler_version\":\"fixture\",\"effect_target_selections_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"executable_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_definition_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"program_semantics_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"version\":\"actql-compiled-plan/0.1\"}",
      "sha256:2b1e10764f6db10695540ac2c429cd70347201437acb296eb2011f3e3b1c071f",
    ),
    (
      "run_definition", "{\"authorization_context_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"compiled_plan_cid\":\"sha256:df0ab99fce2b64b6c4df397351a0a9e73c8a45688ac6cd426c9c0184cd71f1f7\",\"created_at\":\"2026-10-14T00:00:00.000Z\",\"input_artifact_set_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"invocation_template_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"run_id\":\"original-update\",\"scope_id\":\"fixture\",\"valid_until\":\"2026-10-15T00:00:00.000Z\",\"version\":\"actql-run-definition/0.1\"}",
      "sha256:9606a36817b9c126899d0358962450e95c800469a6b9095b0705ed508b11b856",
    ),
    (
      "run_definition", "{\"authorization_context_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"compiled_plan_cid\":\"sha256:428f9c45352ed0272a36c68dd847263ed9d90d4689a2c86ce0827ced72880617\",\"created_at\":\"2026-10-14T00:00:00.000Z\",\"effect_target_selections_cid\":\"sha256:312e3ae46daa9cf148a228e668726d8f251e1f0035c796c882a51d76f3ba22db\",\"input_artifact_set_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"invocation_template_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"run_id\":\"original-update\",\"scope_id\":\"fixture\",\"valid_until\":\"2026-10-15T00:00:00.000Z\",\"version\":\"actql-run-definition/0.1\"}",
      "sha256:c249a66cd63ecfe6e4622830269d68685a1f1d1ed75f3590676948488b1d414d",
    ),
    (
      "run_definition", "{\"authorization_context_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"compiled_plan_cid\":\"sha256:428f9c45352ed0272a36c68dd847263ed9d90d4689a2c86ce0827ced72880617\",\"created_at\":\"2026-10-14T00:00:00.000Z\",\"effect_target_selections_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"input_artifact_set_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"invocation_template_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"run_id\":\"original-update\",\"scope_id\":\"fixture\",\"valid_until\":\"2026-10-15T00:00:00.000Z\",\"version\":\"actql-run-definition/0.1\"}",
      "sha256:77f632d2144ed0f0ba0d67e99b0195d06a0770b34bc33575c26b1757ef5d15fc",
    ),
    (
      "run_definition", "{\"authorization_context_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"compiled_plan_cid\":\"sha256:428f9c45352ed0272a36c68dd847263ed9d90d4689a2c86ce0827ced72880617\",\"created_at\":\"2026-10-14T00:00:00.000Z\",\"input_artifact_set_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"invocation_template_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"run_id\":\"original-update\",\"scope_id\":\"fixture\",\"valid_until\":\"2026-10-15T00:00:00.000Z\",\"version\":\"actql-run-definition/0.1\"}",
      "sha256:cba9137445600ca7ff186a685d862caf6744429de186b9f36a5b2b9e07e61f94",
    ),
  ]
  for (kind, body, cid) in vectors {
    let admitted = @publication.seal_publication_contract(
      kind, body, 100000, 10000, 100,
    ).unwrap()
    assert_eq(@publication.publication_contract_identity(admitted), cid)
  }
}
