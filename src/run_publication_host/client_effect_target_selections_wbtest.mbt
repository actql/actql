///|
test "selection encoder matches independent identity corpus original preimage" {
  // Frozen from portability/corpus/effect-target-selection.json, not compiler
  // output. Neither this digest nor the selection grants execution authority.
  let selected : ClientEffectUpdateTargetSelection = {
    stage_index: 0,
    effect_id: "update",
    target_ref: "connector://crm/account",
    mapping_ref: "mapping:crm.account.v1",
    mapping_cid: "sha256:" + "b".repeat(64),
    check_environment_cid: "sha256:" + "a".repeat(64),
    installation_binding_cid: "sha256:" + "c".repeat(64),
    installation_owner_cid: "sha256:82b29228f604437218a51df3d6504e813219649a14e80c4b7c24f505eea6c1e9",
  }
  let expected =
    #|[{"check_environment_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","effect_id":"update","installation_binding_cid":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","installation_owner_cid":"sha256:82b29228f604437218a51df3d6504e813219649a14e80c4b7c24f505eea6c1e9","mapping_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","mapping_ref":"mapping:crm.account.v1","stage_index":0,"target_ref":"connector://crm/account"}]
  let input = [selected]
  let actual = encode_client_effect_target_selections(input).unwrap()
  input.clear()
  assert_eq(actual.entries.length(), 1)
  assert_true(physical_equal(actual.entries[0], selected))
  assert_eq(actual.wire, expected)
  assert_eq(
    client_effect_target_selection_cid(actual),
    "sha256:312e3ae46daa9cf148a228e668726d8f251e1f0035c796c882a51d76f3ba22db",
  )
  assert_true(encode_client_effect_target_selections([]) is Err(Limit))
  assert_true(
    encode_client_effect_target_selections(Array::make(1025, selected))
    is Err(Limit),
  )
  assert_true(
    encode_client_effect_target_selections([selected, selected])
    is Err(ForeignSelection),
  )
}

///|
fn target_selection_fixture(
  published? : Bool = true,
  target_alias? : String = "account",
  owner_cid? : String = "sha256:" + "9".repeat(64),
  normalized? : Bool = false,
) -> (
  PreparedClientEffectComputation,
  ClientEffectAllowedRun,
  @publication.PublicationContract,
  ClientRequestIdentity,
) {
  let (document, environment, limits) = local_update_normalization_fixture()
  let publication = if published {
    let mappings = @environment.check_mapping_contract_shapes(
      @checked.checking_environment_wire(environment),
      limits.mapping,
      limits.max_mapping_work,
    ).unwrap()
    Some(
      @update_targets.bind_update_target_publication(
        mappings,
        [
          {
            name: [
              { value: "crm", quoted: false, },
              { value: target_alias, quoted: false, },
            ],
            target_ref: "connector://crm/account",
            installation_binding_cid: "sha256:" + "8".repeat(64),
            installation_owner_cid: owner_cid,
          },
        ],
        1000,
      ).unwrap(),
    )
  } else {
    None
  }
  let prepared = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
    update_targets=publication,
  ).unwrap()
  let bounds = run_materials_limits()
  let normalization = if normalized {
    Some(
      issue_prepared_client_effect_local_update_normalization(prepared).unwrap(),
    )
  } else {
    None
  }
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
    normalization~,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "selected-update-scope", "selected-update-run", "2026-10-09T00:00:00.000Z",
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "selected-update-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  (prepared, allowed, definition, request)
}

///|
fn target_selection_materials_admit(
  wire : String,
  run_cid : String,
  request : ClientRequestIdentity?,
) -> Result[ClientEffectRunMaterials, ClientEffectRunMaterialsIssue] {
  let (_, _, effect_limits) = local_update_normalization_fixture()
  admit_client_effect_run_materials(
    wire,
    run_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    run_materials_limits(),
    effect_limits,
    expected_request=request,
  )
}

///|
fn target_selection_replace_field(
  wire : String,
  field : String,
  replacement : String?,
) -> String raise @encode.EncodeFailure {
  let source = @source.parse_json_bytes(@utf8.encode(wire), {
    max_input_bytes: 1000000,
    max_nodes: 8192,
    max_depth: 64,
  }).unwrap()
  let root = @decode.admit(source, {
    max_nodes: 8192,
    max_depth: 64,
    max_string_bytes: 1000000,
    max_total_string_bytes: 1000000,
  }).unwrap()
  let writer = @encode.writer(1000000, 8192, 64)
  @encode.begin_object(writer)
  for index in 0..<@decode.object_length(root).unwrap() {
    let (name, value) = @decode.field_at(root, index).unwrap()
    if name == field {
      if replacement is Some(replacement) {
        @encode.key(writer, name)
        @encode.string_value(writer, replacement)
      }
    } else {
      @encode.key(writer, name)
      @syntax.emit_admitted_source_value(value, writer)
    }
  }
  @encode.end_object(writer)
  @encode.finish(writer)
}

///|
test "original update selection has an independently fixed canonical concrete tuple" {
  let (prepared, allowed, _, _) = target_selection_fixture()
  let expected =
    #|[{"check_environment_cid":"sha256:dde2a4ab7160672ec8f2fc7fc49e1b9e0ebd7992b7a60851d57e5a9ea161694b","effect_id":"save","installation_binding_cid":"sha256:8888888888888888888888888888888888888888888888888888888888888888","installation_owner_cid":"sha256:9999999999999999999999999999999999999999999999999999999999999999","mapping_cid":"sha256:ce8b7dc9c08beafcd15440c15026a857361f9e04a2c1d9dec4bc8c9ab9f40283","mapping_ref":"mapping:crm.account.v1","stage_index":0,"target_ref":"connector://crm/account"}]
  assert_eq(prepared_client_effect_target_selections(prepared), Some(expected))
  assert_true(allowed.compilation.compiled.plan.plan.wire.contains(expected))
  let (renamed, renamed_allowed, _, _) = target_selection_fixture(
    target_alias="customers",
  )
  assert_eq(
    prepared_client_effect_target_selections(renamed),
    prepared_client_effect_target_selections(prepared),
  )
  assert_eq(
    @publication.publication_contract_identity(
      client_effect_compilation_compiled_plan(allowed.compilation),
    ),
    @publication.publication_contract_identity(
      client_effect_compilation_compiled_plan(renamed_allowed.compilation),
    ),
  )
  let (_, changed, _, _) = target_selection_fixture(
    owner_cid="sha256:" + "7".repeat(64),
  )
  assert_true(
    @publication.publication_contract_identity(
      client_effect_compilation_compiled_plan(allowed.compilation),
    ) !=
    @publication.publication_contract_identity(
      client_effect_compilation_compiled_plan(changed.compilation),
    ),
  )
}

///|
test "absent update publication retains the legacy compilation and material field set" {
  let (legacy, allowed, definition, request) = target_selection_fixture(
    published=false,
  )
  assert_eq(prepared_client_effect_target_selections(legacy), None)
  assert_false(
    allowed.compilation.compiled.plan.plan.wire.contains(
      "effect_target_selections",
    ),
  )
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  assert_false(wire.contains("effect_target_selections_json"))
  let restored = target_selection_materials_admit(
    wire,
    @publication.publication_contract_identity(definition),
    Some(request),
  ).unwrap()
  assert_eq(
    restore_client_effect_run_target_selections(restored).unwrap(),
    None,
  )
  assert_eq(
    issue_prepared_client_effect_run_materials(
      restored.allowed,
      restored.run_definition,
      request=restored.request,
    ).unwrap(),
    wire,
  )
}

///|
test "selected update Run restores original concrete custody without a normalization journal" {
  let (prepared, allowed, definition, request) = target_selection_fixture()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let restored = target_selection_materials_admit(
    wire,
    @publication.publication_contract_identity(definition),
    Some(request),
  ).unwrap()
  assert_true(restored.normalization is None)
  assert_true(restored.prepared.normalization is None)
  assert_eq(
    restore_client_effect_run_target_selections(restored).unwrap(),
    prepared_client_effect_target_selections(prepared),
  )
  assert_eq(
    issue_prepared_client_effect_run_materials(
      restored.allowed,
      restored.run_definition,
      request=restored.request,
    ).unwrap(),
    wire,
  )
  assert_true(
    target_selection_materials_admit(
      wire,
      @publication.publication_contract_identity(definition),
      None,
    )
    is Err(Request(IdentityMismatch)),
  )
  assert_true(
    target_selection_materials_admit(
      wire,
      "sha256:" + "f".repeat(64),
      Some(request),
    )
    is Err(RunMismatch),
  )
}

///|
test "selected update Run refuses removed substituted and malformed selection evidence" {
  let (prepared, allowed, definition, request) = target_selection_fixture()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
  ).unwrap()
  let selection = prepared_client_effect_target_selections(prepared).unwrap()
  let changed : Array[String?] = [
    None,
    Some("[]"),
    Some(
      selection.replace(
        old="sha256:dde2a4ab7160672ec8f2fc7fc49e1b9e0ebd7992b7a60851d57e5a9ea161694b",
        new="sha256:" + "5".repeat(64),
      ),
    ),
    Some(
      selection.replace(
        old="sha256:ce8b7dc9c08beafcd15440c15026a857361f9e04a2c1d9dec4bc8c9ab9f40283",
        new="sha256:" + "4".repeat(64),
      ),
    ),
    Some(selection.replace(old="\"stage_index\":0", new="\"stage_index\":1")),
    Some(
      selection.replace(
        old="\"effect_id\":\"save\"",
        new="\"effect_id\":\"other\"",
      ),
    ),
    Some(
      selection.replace(
        old="connector://crm/account",
        new="connector://crm/other",
      ),
    ),
    Some(
      selection.replace(
        old="mapping:crm.account.v1",
        new="mapping:crm.other.v1",
      ),
    ),
    Some(
      selection.replace(
        old="sha256:" + "8".repeat(64),
        new="sha256:" + "7".repeat(64),
      ),
    ),
    Some(
      selection.replace(
        old="sha256:" + "9".repeat(64),
        new="sha256:" + "6".repeat(64),
      ),
    ),
    Some(
      selection.replace(
        old="\"stage_index\":0",
        new="\"stage_index\":0,\"alias\":\"crm.account\"",
      ),
    ),
    Some(selection.replace(old="[{", new="[ {")),
  ]
  for replacement in changed {
    let substituted = target_selection_replace_field(
      wire, "effect_target_selections_json", replacement,
    )
    assert_true(
      target_selection_materials_admit(
        substituted,
        @publication.publication_contract_identity(definition),
        Some(request),
      )
      is Err(_),
    )
  }
  assert_true(
    admit_client_effect_target_selections(
      prepared.candidate,
      "[" +
      selection[1:selection.length() - 1].to_owned() +
      "," +
      selection[1:selection.length() - 1].to_owned() +
      "]",
    )
    is Err(_),
  )
}

///|
test "initial selection refuses an equal CID replacement environment owner" {
  let (document, environment, limits) = local_update_normalization_fixture()
  let (_, foreign_environment, _) = local_update_normalization_fixture()
  assert_eq(
    @checked.checking_environment_cid(environment),
    @checked.checking_environment_cid(foreign_environment),
  )
  let mappings = @environment.check_mapping_contract_shapes(
    @checked.checking_environment_wire(foreign_environment),
    limits.mapping,
    limits.max_mapping_work,
  ).unwrap()
  let publication = @update_targets.bind_update_target_publication(
    mappings,
    [
      {
        name: [
          { value: "crm", quoted: false, },
          { value: "account", quoted: false, },
        ],
        target_ref: "connector://crm/account",
        installation_binding_cid: "sha256:" + "8".repeat(64),
        installation_owner_cid: "sha256:" + "9".repeat(64),
      },
    ],
    1000,
  ).unwrap()
  assert_true(
    prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      limits,
      update_targets=Some(publication),
    )
    is Err(TargetSelection(ForeignEnvironment)),
  )
}

///|
test "held original selection restores only the independently pinned compiled plan" {
  for normalized in [false, true] {
    let (prepared, allowed, _, _) = target_selection_fixture(normalized~)
    let original = issue_client_effect_prepared_original(allowed.compilation).unwrap()
    let cid = @publication.publication_contract_identity(
      client_effect_compilation_compiled_plan(allowed.compilation),
    )
    let (_, _, effect_limits) = local_update_normalization_fixture()
    let restore = fn(wire : String, expected : String) {
      admit_client_effect_prepared_original(
        wire,
        expected,
        { text_time: false, veca: false, },
        {
          rela: true,
          sga: false,
          tea: false,
          calendar: false,
          text_rank: false,
        },
        run_materials_manifests(),
        run_materials_limits(),
        effect_limits,
      )
    }
    let restored = restore(original, cid).unwrap()
    assert_eq(
      prepared_client_effect_target_selections(
        client_effect_prepared_original_prepared(restored),
      ),
      prepared_client_effect_target_selections(prepared),
    )
    assert_true(restored.prepared.normalization is None)
    assert_eq(
      issue_client_effect_prepared_original(restored.compilation).unwrap(),
      original,
    )
    assert_true(
      restore(original, "sha256:" + "f".repeat(64))
      is Err(TargetSelection(ForeignSelection)),
    )
    assert_true(
      restore(
        target_selection_replace_field(
          original,
          "effect_target_selections_json",
          None,
        ),
        cid,
      )
      is Err(_),
    )
    assert_true(
      restore(
        original.replace(
          old="sha256:" + "9".repeat(64),
          new="sha256:" + "7".repeat(64),
        ),
        cid,
      )
      is Err(_),
    )
    if normalized {
      assert_true(
        restore(
          target_selection_replace_field(
            original,
            "normalization_profile_key",
            None,
          ),
          cid,
        )
        is Err(_),
      )
    }
  }
}

///|
test "selection identity stays attached to its admitted original across Run bindings" {
  let (owner, allowed, definition, _) = target_selection_fixture()
  let selection = client_effect_target_selection_original(owner)[0]
  let expected = "sha256:" + @sha.hex(@utf8.encode(selection.wire))
  assert_eq(selection.cid, expected)
  for _ in 0..<3 {
    assert_eq(client_effect_target_selection_cid(selection), expected)
    assert_eq(client_effect_target_selections_cid(owner), Some(expected))
    assert_true(
      bind_client_effect_compiled_run(owner, allowed, definition) is Ok(_),
    )
  }
  let restored = admit_client_effect_target_selections(
    owner.candidate,
    selection.wire,
  ).unwrap()
  assert_eq(restored.cid, expected)
  assert_false(client_effect_target_selection_matches_prepared(restored, owner))
  let (foreign, _, foreign_definition, _) = target_selection_fixture(
    owner_cid="sha256:" + "7".repeat(64),
  )
  assert_true(client_effect_target_selections_cid(foreign) != Some(expected))
  assert_true(
    bind_client_effect_compiled_run(owner, allowed, foreign_definition)
    is Err(_),
  )
  assert_false(
    client_effect_run_start_current(
      allowed, definition, "2026-10-10T00:00:00.000Z",
    ),
  )
  let (legacy, _, _, _) = target_selection_fixture(published=false)
  assert_eq(client_effect_target_selections_cid(legacy), None)
}
