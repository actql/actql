///|
test "static Effect declarations retain original entry and checked contract identities" {
  let (original, compiled) = effect_static_computation_fixture()
  let set = client_effect_static_declarations(original, compiled, 1, 100).unwrap()
  assert_eq(set.program, prepared_client_effect_identity(original))
  assert_eq(
    set.compiled_plan_cid,
    @publication.publication_contract_identity(compiled.compiled.compiled_plan),
  )
  assert_eq(
    set.check_environment_cid,
    prepared_client_effect_computation_environment_cid(original),
  )
  assert_eq(set.unit_id, "source")
  assert_eq(set.members.length(), 1)
  let entry = set.members[0]
  assert_eq(entry.member_ordinal, 0)
  assert_eq(entry.stage_ordinal, 0)
  assert_eq(entry.effect_id, "save")
  assert_eq(entry.effect_kind, "update")
  assert_eq(entry.input, ResultDeclaration("out"))
  assert_eq(entry.minimum_approval, ContractMinimumNone)
  guard entry.contract is MappingDeclaration(reference, cid, target) else {
    fail("checked Mapping declaration was replaced by a Command")
  }
  assert_eq(reference, "mapping:crm.account.v1")
  assert_eq(target, "connector://crm/account")
  // Independently hashed from the existing fixture's explicit Mapping input.
  assert_eq(
    cid, "sha256:ce8b7dc9c08beafcd15440c15026a857361f9e04a2c1d9dec4bc8c9ab9f40283",
  )
  assert_eq(
    client_effect_static_declarations(original, compiled, 1, 100).unwrap(),
    set,
  )
  assert_true(original.normalization is None)
  assert_true(original.normalization_custody is None)
  // A caller's mutable display snapshot cannot replace the original inventory.
  set.members.clear()
  let again = client_effect_static_declarations(original, compiled, 1, 100).unwrap()
  assert_eq(again.members.length(), 1)
  assert_eq(again.members[0].minimum_approval, ContractMinimumNone)
}

///|
test "static approval minimum follows the original contract rather than another environment" {
  let (document, environment, limits) = local_update_normalization_fixture()
  let writer = @encode.writer(65536, 4096, 64)
  @environment.emit(@checked.checking_environment_wire(environment), writer)
  // Construct a second independently admitted fixture input. The expected
  // Mapping CID is independently hashed from the explicit required contract.
  let input = @encode.finish(writer)
    .replace(
      old="\"minimum_approval\":\"none\"",
      new="\"minimum_approval\":\"required\"",
    )
    .replace(
      old="sha256:ce8b7dc9c08beafcd15440c15026a857361f9e04a2c1d9dec4bc8c9ab9f40283",
      new="sha256:c99f6697a8b40c16a418a156177be2a6144be3ba5ebbc36020c819789d021cd4",
    )
  let root = parse_plan_identity_value(input, 65536, 4096, 64).unwrap()
  let preimage = @canonical.object_without_field(root, "evidence_bundle_cid").unwrap()
  let body = @canonical.stringify_value(preimage, 65536, 4096, 64)
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let value = @canonical.object_with_string_field(
    preimage, "evidence_bundle_cid", cid,
  ).unwrap()
  let wire = @environment.read(
    @utf8.encode(@canonical.stringify_value(value, 65536, 4096, 64)),
    cid,
    limits.mapping,
  ).unwrap()
  let required_environment = @checked.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let required = prepare_client_effect_computation(
    document,
    Json,
    required_environment,
    None,
    [],
    limits,
  ).unwrap()
  let bounds = run_materials_limits()
  let required_compiled = issue_prepared_client_effect_compilation(
    required,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let set = client_effect_static_declarations(
    required, required_compiled, 1, 100,
  ).unwrap()
  assert_eq(set.members[0].minimum_approval, ContractMinimumRequired)
  guard set.members[0].contract is MappingDeclaration(_, actual, _) else {
    fail("required fixture lacks its original Mapping")
  }
  assert_eq(
    actual, "sha256:c99f6697a8b40c16a418a156177be2a6144be3ba5ebbc36020c819789d021cd4",
  )
  let (original, original_compiled) = effect_static_computation_fixture()
  assert_eq(set.program, prepared_client_effect_identity(original))
  assert_true(
    set.check_environment_cid !=
    prepared_client_effect_computation_environment_cid(original),
  )
  assert_true(
    client_effect_static_declarations(required, original_compiled, 1, 100)
    is Err(ClientEffectStaticDeclarationIssue::ForeignCompilation),
  )
  assert_eq(
    client_effect_static_declarations(original, original_compiled, 1, 100).unwrap().members[0].minimum_approval,
    ContractMinimumNone,
  )
  assert_true(required.normalization is None)
  assert_true(required.normalization_custody is None)
}

///|
test "static Effect set preserves both original members and one total work allowance" {
  let (document, environment, limits) = local_update_normalization_fixture()
  let body =
    #|{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"},"id":"id","set":{"Name":{"field":"value"}}}}
  let document = document.replace(
    old="\"effects\":{\"save\":" + body + "}",
    new="\"effects\":{\"save\":" + body + ",\"save2\":" + body + "}",
  )
  let original = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    {
      ..limits,
      max_members: 2,
      effects: { ..limits.effects, max_members: 2, },
    },
  ).unwrap()
  let bounds = run_materials_limits()
  let compiled = issue_prepared_client_effect_compilation(
    original,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  assert_true(
    client_effect_static_declarations(original, compiled, 1, 100)
    is Err(ClientEffectStaticDeclarationIssue::IncompleteInventory),
  )
  // Each descriptor costs four, with a two-shape minimum scan, three body
  // reads and one outer read. Twenty total units must not reset per entry.
  assert_true(
    client_effect_static_declarations(original, compiled, 2, 10)
    is Err(ClientEffectStaticDeclarationIssue::WorkLimit),
  )
  assert_true(
    client_effect_static_declarations(original, compiled, 2, 19)
    is Err(ClientEffectStaticDeclarationIssue::WorkLimit),
  )
  let set = client_effect_static_declarations(original, compiled, 2, 20).unwrap()
  assert_eq(set.members.length(), 2)
  assert_eq(
    set.members.map(entry => {
      (entry.member_ordinal, entry.stage_ordinal, entry.effect_id, entry.input)
    }),
    [
      (0, 0, "save", ResultDeclaration("out")),
      (1, 0, "save2", ResultDeclaration("out")),
    ],
  )
  assert_eq(set.members[0].contract, set.members[1].contract)
  assert_true(original.normalization is None)
  assert_true(original.normalization_custody is None)
}

///|
test "static Effect declarations refuse copied identity and invalid total bounds" {
  let (original, compiled) = effect_static_computation_fixture()
  let (foreign, _) = effect_static_computation_fixture()
  assert_eq(
    prepared_client_effect_identity(original),
    prepared_client_effect_identity(foreign),
  )
  assert_true(
    client_effect_static_declarations(foreign, compiled, 1, 100)
    is Err(ClientEffectStaticDeclarationIssue::ForeignCompilation),
  )
  for (members, work) in [(0, 100), (65, 100), (1, 0), (1, 10001)] {
    assert_true(
      client_effect_static_declarations(original, compiled, members, work)
      is Err(ClientEffectStaticDeclarationIssue::InvalidLimits),
    )
  }
  assert_true(
    client_effect_static_declarations(original, compiled, 1, 6)
    is Err(ClientEffectStaticDeclarationIssue::WorkLimit),
  )
  assert_eq(
    client_effect_static_declarations(original, compiled, 1, 7).unwrap().members.length(),
    1,
  )
}
