///|
test "original normalization profile is bound through Template and original Run" {
  let (prepared, allowed, definition) = original_effect_materials_fixture(
    normalized=true,
  )
  let original = issue_prepared_client_effect_normalization(prepared).unwrap()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    normalization=Some(original),
  ).unwrap()
  let run = @publication.publication_contract_identity(definition)
  let restored = normalization_materials_admit(wire, run)
  assert_true(restored.compilation.normalization_profile)
  assert_true(restored.prepared.normalization is None)
  assert_true(restored.normalization.unwrap().issued is None)
  let template = @publication.run_evidence_value_json(
    client_effect_compilation_template(restored.compilation),
  )
  assert_true(template.contains("actql-resident-effect-completion-free/0.1"))
  assert_true(template.contains(client_effect_completion_free_catalog_cid()))
  for _ in 0..<2 {
    let journal = restore_client_effect_run_normalization(restored).unwrap()
    assert_eq(
      @publication.run_evidence_value_json(journal),
      @publication.run_evidence_value_json(
        prepared_client_effect_normalization_evidence(prepared, original).unwrap(),
      ),
    )
    assert_true(restored.prepared.normalization is None)
  }
  let (_, _, legacy) = original_effect_materials_fixture()
  assert_true(run != @publication.publication_contract_identity(legacy))
  assert_true(
    issue_prepared_client_effect_run_materials(allowed, definition)
    is Err(Normalization(MissingOriginalJournal)),
  )
}

///|
test "profile cannot be grafted onto an original legacy Run or another original identity" {
  let (prepared, allowed, legacy) = original_effect_materials_fixture()
  let original = issue_prepared_client_effect_normalization(prepared).unwrap()
  let legacy_wire = issue_prepared_client_effect_run_materials(allowed, legacy).unwrap()
  let grafted = normalization_materials_replace(
    legacy_wire,
    @publication.run_evidence_value_json(
      prepared_client_effect_normalization_evidence(prepared, original).unwrap(),
    ),
  )
  assert_true(
    normalization_materials_untrusted_admission(
      grafted,
      @publication.publication_contract_identity(legacy),
    )
    is Err(Normalization(UnverifiedOriginalMaterials)),
  )
  let (current, normalized_allowed, normalized_run) = original_effect_materials_fixture(
    normalized=true,
  )
  let proof = issue_prepared_client_effect_normalization(current).unwrap()
  let wire = issue_prepared_client_effect_run_materials(
    normalized_allowed,
    normalized_run,
    normalization=Some(proof),
  ).unwrap()
  assert_true(
    normalization_materials_untrusted_admission(
      wire,
      @publication.publication_contract_identity(legacy),
    )
    is Err(RunMismatch),
  )
  assert_true(
    normalization_materials_untrusted_admission(
      wire + " ",
      @publication.publication_contract_identity(normalized_run),
    )
    is Err(Normalization(UnverifiedOriginalMaterials)),
  )
}

///|
test "normalized original material canonical bytes reject omission and value substitution" {
  let (prepared, allowed, definition) = original_effect_materials_fixture(
    normalized=true,
  )
  let original = issue_prepared_client_effect_normalization(prepared).unwrap()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    normalization=Some(original),
  ).unwrap()
  let run = @publication.publication_contract_identity(definition)
  let value = parse_plan_identity_value(wire, 100000, 10000, 100).unwrap()
  let stripped = @canonical.object_without_field(
    value, "normalization_journal_json",
  ).unwrap()
  let stripped_wire = @canonical.stringify_value(stripped, 100000, 10000, 100)
  assert_true(
    normalization_materials_untrusted_admission(stripped_wire, run)
    is Err(Binding(_)),
  )
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
    wire,
    @publication.run_evidence_value_json(wrong),
  )
  assert_true(
    normalization_materials_untrusted_admission(changed, run)
    is Err(Normalization(SubstitutedJournal)),
  )
}

///|
test "wire-only profile restoration requires the independently selected original request" {
  let (prepared, allowed, definition) = original_effect_materials_fixture(
    normalized=true,
  )
  let original = issue_prepared_client_effect_normalization(prepared).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let other = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "other-caller",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let wire = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(request),
    normalization=Some(original),
  ).unwrap()
  let changed = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    request=Some(other),
    normalization=Some(original),
  ).unwrap()
  let run = @publication.publication_contract_identity(definition)
  assert_true(
    normalization_materials_untrusted_admission(wire, run)
    is Err(Request(IdentityMismatch)),
  )
  assert_true(
    normalization_materials_untrusted_admission(
      changed,
      run,
      expected_request=Some(request),
    )
    is Err(Request(IdentityMismatch)),
  )
  let omitted = issue_prepared_client_effect_run_materials(
    allowed,
    definition,
    normalization=Some(original),
  ).unwrap()
  assert_true(
    normalization_materials_untrusted_admission(
      omitted,
      run,
      expected_request=Some(request),
    )
    is Err(Request(IdentityMismatch)),
  )
  let restored = normalization_materials_admit(
    wire,
    run,
    expected_request=Some(request),
  )
  assert_eq(restored.request, Some(request))
  assert_true(restore_client_effect_run_normalization(restored) is Ok(_))
}
