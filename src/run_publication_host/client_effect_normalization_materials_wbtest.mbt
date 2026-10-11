///|
fn normalization_materials_admit(
  wire : String,
  run : String,
  original? : ClientEffectIssuedNormalizationMaterials? = None,
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
    original_materials=original,
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
  let issued = issue_prepared_client_effect_normalization_materials(
    allowed, definition, original,
  ).unwrap()
  let wire = client_effect_issued_normalization_materials_wire(issued)
  let run = @publication.publication_contract_identity(definition)
  let restored = normalization_materials_admit(wire, run, original=Some(issued))
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
  let issued = issue_prepared_client_effect_normalization_materials(
    allowed, definition, original,
  ).unwrap()
  let wire = client_effect_issued_normalization_materials_wire(issued)
  let restored = normalization_materials_admit(
    wire,
    @publication.publication_contract_identity(definition),
    original=Some(issued),
  )
  let original_custody = restored.normalization.unwrap()
  let copied : ClientEffectNormalizationMaterialCustody = {
    issued: original_custody.issued,
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
    normalization_materials_untrusted_admission(changed, run)
    is Err(Normalization(UnverifiedOriginalMaterials)),
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

///|
fn normalization_materials_untrusted_admission(
  wire : String,
  run : String,
  original? : ClientEffectIssuedNormalizationMaterials? = None,
) -> Result[ClientEffectRunMaterials, ClientEffectRunMaterialsIssue] {
  let (_, _, limits) = client_composed_effect_base_fixture()
  admit_client_effect_run_materials(
    wire,
    run,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    run_materials_limits(),
    limits,
    original_materials=original,
  )
}

///|
test "fixed empty journal appended after issuance cannot mint original custody" {
  let (prepared, allowed, definition) = original_effect_materials_fixture()
  let plain = issue_prepared_client_effect_run_materials(allowed, definition).unwrap()
  let original = issue_prepared_client_effect_normalization(prepared).unwrap()
  let journal = prepared_client_effect_normalization_evidence(
    prepared, original,
  ).unwrap()
  let changed = normalization_materials_replace(
    plain,
    @publication.run_evidence_value_json(journal),
  )
  let run = @publication.publication_contract_identity(definition)
  assert_true(
    normalization_materials_untrusted_admission(changed, run)
    is Err(Normalization(UnverifiedOriginalMaterials)),
  )
  // Correct journal/Run content still refuses without the original issuance
  // projection, even if its Owner subsequently issues byte-identical material.
  let _ = issue_prepared_client_effect_normalization_materials(
    allowed, definition, original,
  ).unwrap()
  assert_true(
    normalization_materials_untrusted_admission(changed, run)
    is Err(Normalization(UnverifiedOriginalMaterials)),
  )
  assert_true(prepared.normalization_custody is None)
}

///|
test "original issuance proof cannot be copied or applied to other exact bytes" {
  let (prepared, allowed, definition) = original_effect_materials_fixture()
  let original = issue_prepared_client_effect_normalization(prepared).unwrap()
  let proof = issue_prepared_client_effect_normalization_materials(
    allowed, definition, original,
  ).unwrap()
  let wire = client_effect_issued_normalization_materials_wire(proof)
  let run = @publication.publication_contract_identity(definition)
  let copied : ClientEffectIssuedNormalizationMaterials = {
    original: proof.original,
    run_cid: proof.run_cid,
    wire: proof.wire,
  }
  assert_true(
    normalization_materials_untrusted_admission(
      wire,
      run,
      original=Some(copied),
    )
    is Err(Normalization(UnverifiedOriginalMaterials)),
  )
  assert_true(
    normalization_materials_untrusted_admission(
      wire + " ",
      run,
      original=Some(proof),
    )
    is Err(Normalization(UnverifiedOriginalMaterials)),
  )
  assert_true(
    normalization_materials_untrusted_admission(
      wire,
      "sha256:" + "c".repeat(64),
      original=Some(proof),
    )
    is Err(Normalization(UnverifiedOriginalMaterials)),
  )
  assert_true(
    normalization_materials_untrusted_admission(wire, run)
    is Err(Normalization(UnverifiedOriginalMaterials)),
  )
  assert_true(
    physical_equal(
      proof,
      issue_prepared_client_effect_normalization_materials(
        allowed, definition, original,
      ).unwrap(),
    ),
  )
  let restored = normalization_materials_admit(wire, run, original=Some(proof))
  assert_true(restore_client_effect_run_normalization(restored) is Ok(_))
}
