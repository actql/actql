///|
test "selected normalization supplier reuses each original kind proof" {
  let (created, _, _) = original_effect_materials_fixture(normalized=true)
  let original_create = issue_prepared_client_effect_normalization(created).unwrap()
  let selected_create = issue_prepared_client_effect_selected_normalization(
    created,
  ).unwrap()
  assert_true(physical_equal(original_create, selected_create))
  assert_true(selected_create.inventory is MappedCreate(_))
  assert_eq(
    client_effect_normalization_catalog_cid(selected_create),
    client_effect_completion_free_catalog_cid(),
  )
  assert_true(
    issue_prepared_client_effect_local_update_normalization(created)
    is Err(Inventory(ProfileNotInstalled)),
  )
  let updated = local_update_source_normalization_fixture(true)
  let selected_update = issue_prepared_client_effect_selected_normalization(
    updated,
  ).unwrap()
  let original_update = issue_prepared_client_effect_local_update_normalization(
    updated,
  ).unwrap()
  assert_true(physical_equal(selected_update, original_update))
  assert_true(
    physical_equal(
      selected_update,
      issue_prepared_client_effect_selected_normalization(updated).unwrap(),
    ),
  )
  assert_true(selected_update.inventory is LocalUpdate(_))
  assert_eq(
    client_effect_normalization_catalog_cid(selected_update),
    client_effect_local_update_completion_free_catalog_cid(),
  )
  assert_true(
    issue_prepared_client_effect_normalization(updated)
    is Err(Inventory(ProfileNotInstalled)),
  )
}

///|
test "selected normalization records the original implicit Source completion" {
  let completed = local_update_source_normalization_fixture(false)
  assert_true(
    issue_prepared_client_effect_selected_normalization(completed)
    is Err(Inventory(CompletionObserved)),
  )
  assert_true(completed.normalization is None)
  let proof = issue_prepared_client_effect_selected_normalization(
    completed,
    allow_source_completion=true,
  ).unwrap()
  assert_true(proof.inventory is SourceCompletedUpdate(_))
  let journal = prepared_client_effect_normalization_evidence(completed, proof).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(journal),
    (
      #|{"entries":[{"authored":"null","canonical":"v","path":"$.stages[0].inputs[\"table\"].view","rule":"actql.source.sole-view-completion"}],"journal_cid":"sha256:2481749e9a10d56cc31b1e621868cf6d802a8de3194e0e295b7dcc4bd4d2bbfe","rule_catalog_cid":"sha256:2ec2fd95b3aa1bfcddaf87bcf2a383321fb0d17b39917b65da6f3cde10a6dae8","version":"actql-normalization-journal/0.1"}
    ),
  )
  assert_true(
    physical_equal(
      proof,
      issue_prepared_client_effect_selected_normalization(
        completed,
        allow_source_completion=true,
      ).unwrap(),
    ),
  )
}

///|
test "selected normalization supplier refuses copied and substituted original proof custody" {
  let original = local_update_source_normalization_fixture(true)
  let proof = issue_prepared_client_effect_selected_normalization(original).unwrap()
  let copied = { ..original, }
  assert_true(
    issue_prepared_client_effect_selected_normalization(copied)
    is Err(ForeignPreparation),
  )
  let (created, _, _) = original_effect_materials_fixture(normalized=true)
  let create_proof = issue_prepared_client_effect_normalization(created).unwrap()
  let substituted = local_update_source_normalization_fixture(true)
  substituted.normalization = Some(create_proof)
  assert_true(
    issue_prepared_client_effect_selected_normalization(substituted)
    is Err(Inventory(ProfileNotInstalled)),
  )
  assert_true(physical_equal(substituted.normalization.unwrap(), create_proof))
  assert_true(physical_equal(original.normalization.unwrap(), proof))
  assert_true(
    physical_equal(
      issue_prepared_client_effect_selected_normalization(original).unwrap(),
      proof,
    ),
  )
}

///|
fn common_update_normalization_fixture(
  completion? : Bool = false,
) -> PreparedClientEffectComputation {
  let (document, environment, limits) = local_update_normalization_fixture()
  let document = if completion {
    document
    .replace(
      old="\"schema\":{",
      new="\"schema\":{\"spare\":{\"type\":\"number\",\"nullable\":false},",
    )
    .replace(old="\"rows\":[{", new="\"rows\":[{\"spare\":1,")
    .replace(
      old="\"as\":\"selected\"}]",
      new="\"as\":\"raw\"},{\"drop\":[\"spare\"],\"as\":\"selected\"}]",
    )
  } else {
    document
  }
  let document = document.replace(
    old="\"as\":\"selected\"}]",
    new="\"as\":\"original\"},{\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"selected\"}]",
  )
  prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
}

///|
test "common update normalization retains actual zero-completion closure and distinct first compiler profile" {
  let owner = common_update_normalization_fixture()
  assert_true(
    issue_prepared_client_effect_local_update_normalization(owner)
    is Err(Inventory(ProfileNotInstalled)),
  )
  // The Effect-free entry remains Effect-free; only the static Effect owner
  // can connect its complete computation and original Mapping proof.
  assert_true(
    @checked.local_program_common_normalization_inventory(
      @checked.effect_program_static_checked_computation(owner.candidate),
      10000,
    )
    is Err(UnsupportedRequirement),
  )
  let proof = issue_prepared_client_effect_selected_normalization(owner).unwrap()
  assert_true(proof.inventory is CommonUpdate(_))
  assert_eq(
    client_effect_normalization_catalog_cid(proof),
    "sha256:1263116a02d125a0c66f2445a175075d4ec333e56f3d003d35e9d51065fecf8f",
  )
  assert_eq(
    @publication.run_evidence_value_identity(
      prepared_client_effect_normalization_evidence(owner, proof).unwrap(),
    ),
    "sha256:8b5172ca35db5cd4f35b8e6bbde52243d92b9e9027c2fc4568b8d66a5334ffb1",
  )
  assert_true(
    physical_equal(
      proof,
      issue_prepared_client_effect_selected_normalization(owner).unwrap(),
    ),
  )
  let copied = { ..owner, }
  assert_true(
    issue_prepared_client_effect_selected_normalization(copied)
    is Err(ForeignPreparation),
  )
  assert_true(
    prepared_client_effect_normalization_evidence(
      common_update_normalization_fixture(),
      proof,
    )
    is Err(ForeignPreparation),
  )
  let manifests = admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = issue_prepared_client_effect_compilation(
    owner,
    manifests,
    client_standard_values_sequence_limits(),
    1000,
    1000,
    100000,
    10000,
    100,
    normalization=Some(proof),
  ).unwrap()
  assert_true(compilation.normalization_profile is Some(CommonUpdate(_)))
}

///|
test "common update normalization never drops a real original projection completion" {
  let owner = common_update_normalization_fixture(completion=true)
  assert_true(
    issue_prepared_client_effect_local_update_normalization(owner)
    is Err(Inventory(ProfileNotInstalled)),
  )
  assert_true(
    issue_prepared_client_effect_selected_normalization(owner)
    is Err(Inventory(CompletionObserved)),
  )
  assert_true(owner.normalization is None)
}
