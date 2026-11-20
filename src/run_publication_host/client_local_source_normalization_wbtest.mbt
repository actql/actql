///|
test "original sole-view Source has a nonempty successor journal without changing the old empty profile" {
  let document = local_normalization_document.replace(
    old=",\"view\":\"v\"",
    new="",
  )
  let owner = local_normalization_fixture(document~)
  assert_true(
    _issue_prepared_client_legacy_local_normalization(owner)
    is Err(Inventory(CompletionObserved)),
  )
  let proof = issue_prepared_client_local_normalization(owner).unwrap()
  let evidence = prepared_client_local_normalization_evidence(owner, proof).unwrap()
  let preimage =
    #|{"entries":[{"authored":"null","canonical":"v","path":"$.stages[0].inputs[\"table\"].view","rule":"actql.source.sole-view-completion"}],"rule_catalog_cid":"sha256:6ce13b0a83618ec8ccadb33c3ee5bf4ae12214a0ac16c1e0394b75e1eea78153","version":"actql-normalization-journal/0.1"}
  let wire =
    #|{"entries":[{"authored":"null","canonical":"v","path":"$.stages[0].inputs[\"table\"].view","rule":"actql.source.sole-view-completion"}],"journal_cid":"sha256:6080a84fa2b00c310e8649af5a78dd0f44d1c838339bdea7bde756e3d34aad89","rule_catalog_cid":"sha256:6ce13b0a83618ec8ccadb33c3ee5bf4ae12214a0ac16c1e0394b75e1eea78153","version":"actql-normalization-journal/0.1"}
  assert_eq(
    "sha256:" + @sha.hex(@utf8.encode(preimage)),
    "sha256:6080a84fa2b00c310e8649af5a78dd0f44d1c838339bdea7bde756e3d34aad89",
  )
  assert_eq(@publication.run_evidence_value_json(evidence), wire)
  assert_eq(
    local_normalization_catalog_cid(proof.audit),
    local_source_normalization_catalog_cid(),
  )
  assert_true(
    physical_equal(
      issue_prepared_client_local_normalization(owner).unwrap(),
      proof,
    ),
  )
  assert_true(
    physical_equal(
      restore_prepared_client_local_normalization(
        owner,
        proof,
        wire,
        local_source_normalization_catalog_cid(),
      ).unwrap(),
      evidence,
    ),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      proof,
      wire,
      local_common_normalization_catalog_cid(),
    )
    is Err(ForeignCatalog),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      proof,
      common_local_empty_journal,
      local_source_normalization_catalog_cid(),
    )
    is Err(SubstitutedJournal),
  )
  assert_true(
    prepared_client_local_normalization_evidence(
      local_normalization_fixture(document~),
      proof,
    )
    is Err(ForeignPreparation),
  )
}

///|
test "sole-view successor wire retains exact and one-short original codec limits" {
  let document = local_normalization_document.replace(
    old=",\"view\":\"v\"",
    new="",
  )
  let wire =
    #|{"entries":[{"authored":"null","canonical":"v","path":"$.stages[0].inputs[\"table\"].view","rule":"actql.source.sole-view-completion"}],"journal_cid":"sha256:6080a84fa2b00c310e8649af5a78dd0f44d1c838339bdea7bde756e3d34aad89","rule_catalog_cid":"sha256:6ce13b0a83618ec8ccadb33c3ee5bf4ae12214a0ac16c1e0394b75e1eea78153","version":"actql-normalization-journal/0.1"}
  let bytes = @utf8.encode(wire).length()
  let owner = local_normalization_fixture(document~)
  let (prepared, _) = observe_prepare_client_local_normalization(owner, {
    max_work: 100000,
    max_wire_bytes: bytes,
    max_nodes: 32,
    max_depth: 8,
  })
  let issued = finish_prepared_client_local_normalization(prepared.unwrap()).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, issued).unwrap(),
    ),
    wire,
  )
  let other = local_normalization_fixture(document~)
  let (prepared, _) = observe_prepare_client_local_normalization(other, {
    max_work: 100000,
    max_wire_bytes: bytes - 1,
    max_nodes: 32,
    max_depth: 8,
  })
  assert_true(
    finish_prepared_client_local_normalization(prepared.unwrap()) is Err(_),
  )
}
