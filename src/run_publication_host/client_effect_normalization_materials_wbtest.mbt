///|
fn normalization_materials_admit(
  wire : String,
  run : String,
) -> ClientEffectRunMaterials {
  let (_, _, limits) = client_composed_effect_base_fixture()
  admit_client_effect_run_materials(
    wire,
    run,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    run_materials_limits(),
    limits,
  ).unwrap()
}

///|
fn normalization_materials_replace(
  wire : String,
  journal : String,
) -> String raise {
  let value = parse_plan_identity_value(wire, 100000, 10000, 100).unwrap()
  let without = @canonical.object_without_field(
    value, "normalization_journal_json",
  ).unwrap_or(value)
  let changed = @canonical.object_with_string_field(
    without, "normalization_journal_json", journal,
  ).unwrap()
  @canonical.stringify_value(changed, 100000, 10000, 100)
}

///|
test "saved Effect normalization restores exact original bytes without journal issuance" {
  let (prepared, allowed, definition) = original_effect_materials_fixture()
  let original = issue_prepared_client_effect_normalization(prepared).unwrap()
  let original_journal = prepared_client_effect_normalization_evidence(
    prepared, original,
  ).unwrap()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    normalization=Some(original),
  ).unwrap()
  let run = @publication.publication_contract_identity(definition)
  let restored = normalization_materials_admit(wire, run)
  // Material admission restores execution ownership once. Journal restoration
  // reuses that Owner and never invokes preparation or the journal issuer.
  assert_true(restored.prepared.normalization is None)
  for _ in 0..<2 {
    let journal = restore_client_effect_run_normalization(restored).unwrap()
    assert_eq(
      @publication.run_evidence_value_json(journal),
      @publication.run_evidence_value_json(original_journal),
    )
    assert_eq(
      @publication.publication_contract_identity(restored.run_definition),
      run,
    )
    assert_true(restored.prepared.normalization is None)
  }
  assert_eq(
    client_effect_normalization_materials_cid(restored),
    Some("sha256:" + @sha.hex(@utf8.encode(wire))),
  )
}

///|
test "normalization material custody refuses copied projection and foreign preparation" {
  let (prepared, allowed, definition) = original_effect_materials_fixture()
  let original = issue_prepared_client_effect_normalization(prepared).unwrap()
  let (foreign, foreign_allowed, _) = original_effect_materials_fixture(
    alternate=true,
  )
  assert_true(
    issue_prepared_client_effect_run_materials(
      foreign_allowed,
      definition,
      normalization=Some(original),
    )
    is Err(_),
  )
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    normalization=Some(original),
  ).unwrap()
  let restored = normalization_materials_admit(
    wire,
    @publication.publication_contract_identity(definition),
  )
  let original_custody = restored.normalization.unwrap()
  let copied : ClientEffectNormalizationMaterialCustody = {
    compilation: original_custody.compilation,
    run_cid: original_custody.run_cid,
    request: original_custody.request,
    journal_wire: original_custody.journal_wire,
    materials_cid: original_custody.materials_cid,
  }
  assert_true(
    restore_client_effect_run_normalization({
      ..restored,
      normalization: Some(copied),
    })
    is Err(ForeignMaterials),
  )
  assert_true(
    restore_client_effect_run_normalization({ ..restored, prepared: foreign, })
    is Err(ForeignMaterials),
  )
}

///|
test "normalization restoration refuses missing original journal and substituted catalog" {
  let (prepared, allowed, definition) = original_effect_materials_fixture()
  let plain = issue_prepared_client_effect_run_materials(allowed, definition).unwrap()
  let run = @publication.publication_contract_identity(definition)
  assert_true(
    restore_client_effect_run_normalization(
      normalization_materials_admit(plain, run),
    )
    is Err(MissingOriginalJournal),
  )
  let original = issue_prepared_client_effect_normalization(prepared).unwrap()
  let journal = prepared_client_effect_normalization_evidence(
    prepared, original,
  ).unwrap()
  let wrong = @publication.seal_run_evidence_value(
    "normalization_journal",
    "{\"entries\":[],\"rule_catalog_cid\":\"sha256:" +
    "a".repeat(64) +
    "\",\"version\":\"actql-normalization-journal/0.1\"}",
    1024,
    32,
    8,
  ).unwrap()
  let changed = normalization_materials_replace(
    plain,
    @publication.run_evidence_value_json(wrong),
  )
  assert_true(
    restore_client_effect_run_normalization(
      normalization_materials_admit(changed, run),
    )
    is Err(SubstitutedJournal),
  )
  assert_true(
    @publication.run_evidence_value_identity(journal) !=
    @publication.run_evidence_value_identity(wrong),
  )
}

///|
test "actual completion cannot supply an empty normalization material projection" {
  let (document, _, _) = client_composed_effect_base_fixture()
  let changed = document.replace(
    old="\"as\":\"selected\"}],",
    new="\"as\":\"selected\"},{\"filter\":{\"eq\":[{\"template\":\"{value}\"},{\"literal\":\"1\"}]}}],",
  )
  let owner = normalization_fixture(document=changed)
  assert_true(
    issue_prepared_client_effect_normalization(owner)
    is Err(Inventory(CompletionObserved)),
  )
  assert_true(owner.normalization is None)
  // Existing compilation refuses this macro before a material Owner exists.
  // Do not relax that refusal to fabricate a restored completion-free Run.
  let bounds = run_materials_limits()
  assert_true(
    issue_prepared_client_effect_compilation(
      owner,
      run_materials_manifests(),
      bounds.sequence,
      bounds.max_sequence_steps,
      bounds.max_sequence_work,
      bounds.max_evidence_bytes,
      bounds.max_evidence_nodes,
      bounds.max_evidence_depth,
    )
    is Err(_),
  )
}

///|
test "ordinary material admission cannot silently discard Effect normalization custody" {
  let (prepared, allowed, definition) = original_effect_materials_fixture()
  let original = issue_prepared_client_effect_normalization(prepared).unwrap()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    normalization=Some(original),
  ).unwrap()
  assert_true(
    admit_client_values_run_materials(
      wire,
      @publication.publication_contract_identity(definition),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_manifests(),
      run_materials_limits(),
    )
    is Err(MaterialsEvidence("normalization_journal")),
  )
}
