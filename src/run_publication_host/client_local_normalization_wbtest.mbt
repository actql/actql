///|
let local_normalization_document : String =
  #|{"version":"actql/0.1","id":"local.normalization","stages":[{"id":"source","inputs":{"table":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"filter":{"gte":[{"field":"id"},{"literal":0}]}},{"select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}},{"id":"derive","inputs":{"input":{"result":{"stage":"source","result":"out"}}},"steps":[{"derive":{"value":"id + 1"},"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}}},{"id":"finish","inputs":{"input":{"result":{"stage":"derive","result":"out"}}},"steps":[{"derive":{"next":"value * 2 - 1"},"as":"derived"},{"select":["next"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["next"]}}}],"results":{"published":{"from":{"stage":"finish","result":"out"}}}}

///|
fn local_normalization_fixture(
  document? : String = local_normalization_document,
) -> PreparedClientProgram {
  let environment = admit_client_check_environment(
    client_composed_acquired_effect_environment,
    "sha256:cd4aeacdc39164df2cf7e7cb74faf349a157677a5927d9e84379d0d8df2d91e7",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "Local three-stage typed Derive has independent journal bytes and exact original custody" {
  let owner = local_normalization_fixture()
  let issued = issue_prepared_client_local_normalization(owner).unwrap()
  let journal = prepared_client_local_normalization_evidence(owner, issued).unwrap()
  let preimage =
    #|{"entries":[],"rule_catalog_cid":"sha256:690a1e3eea6e0ce89e54937db070a578ec66c2c456061c28a29c7c4dba1b6587","version":"actql-normalization-journal/0.1"}
  // The complete closed wire includes its self CID; the independently hashed
  // preimage omits it. Neither expectation is copied from the issuer's output.
  let complete =
    #|{"entries":[],"journal_cid":"sha256:068f6d7eefb587836c72426fb4d579406247a97b27120621880cbd4a23874880","rule_catalog_cid":"sha256:690a1e3eea6e0ce89e54937db070a578ec66c2c456061c28a29c7c4dba1b6587","version":"actql-normalization-journal/0.1"}
  assert_eq(@publication.run_evidence_value_json(journal), complete)
  assert_eq(
    "sha256:" + @sha.hex(@utf8.encode(preimage)),
    "sha256:068f6d7eefb587836c72426fb4d579406247a97b27120621880cbd4a23874880",
  )
  assert_eq(
    @publication.run_evidence_value_identity(journal),
    "sha256:068f6d7eefb587836c72426fb4d579406247a97b27120621880cbd4a23874880",
  )
  assert_true(@checked.local_completion_free_inventory_work(issued.audit) > 0)
  assert_true(
    physical_equal(
      issued,
      issue_prepared_client_local_normalization(owner).unwrap(),
    ),
  )
  assert_true(
    prepared_client_local_normalization_evidence(
      local_normalization_fixture(),
      issued,
    )
    is Err(ForeignPreparation),
  )
  let copied : ClientLocalNormalization = {
    preparation: issued.preparation,
    audit: issued.audit,
    evidence: issued.evidence,
  }
  assert_true(
    prepared_client_local_normalization_evidence(owner, copied)
    is Err(ForeignPreparation),
  )
  let copied_owner : PreparedClientProgram = { ..owner, }
  assert_true(
    issue_prepared_client_local_normalization(copied_owner)
    is Err(ForeignPreparation),
  )
}

///|
test "Local original sole-view resolution remains a completion and preserves source input" {
  let document = local_normalization_document.replace(
    old=",\"view\":\"v\"",
    new="",
  )
  let owner = local_normalization_fixture(document~)
  assert_true(
    issue_prepared_client_local_normalization(owner)
    is Err(Inventory(CompletionObserved)),
  )
  assert_true(owner.local_normalization is None)
}

///|
test "Local uninstalled operation and actual template completion cannot issue empty evidence" {
  let take = local_normalization_document.replace(
    old="\"select\":[\"next\"],",
    new="\"take\":1},{\"select\":[\"next\"],",
  )
  let owner = local_normalization_fixture(document=take)
  assert_true(
    issue_prepared_client_local_normalization(owner)
    is Err(Inventory(ProfileNotInstalled)),
  )
  assert_true(owner.local_normalization is None)
  let template = local_normalization_document.replace(
    old="\"filter\":{\"gte\":[{\"field\":\"id\"},{\"literal\":0}]}",
    new="\"filter\":{\"eq\":[{\"template\":\"{id}\"},{\"literal\":\"1\"}]}",
  )
  let owner = local_normalization_fixture(document=template)
  assert_true(
    issue_prepared_client_local_normalization(owner)
    is Err(Inventory(CompletionObserved)),
  )
  assert_true(owner.local_normalization is None)
}

///|
test "Local saved normalization bytes cannot be reissued under another catalog or preparation" {
  let owner = local_normalization_fixture()
  let issued = issue_prepared_client_local_normalization(owner).unwrap()
  let journal = prepared_client_local_normalization_evidence(owner, issued).unwrap()
  let wire = @publication.run_evidence_value_json(journal)
  assert_eq(
    @publication.run_evidence_value_json(
      restore_prepared_client_local_normalization(
        owner,
        issued,
        wire,
        client_local_completion_free_catalog_cid(),
      ).unwrap(),
    ),
    wire,
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      issued,
      wire,
      client_effect_completion_free_catalog_cid(),
    )
    is Err(ForeignCatalog),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      issued,
      wire.replace(old="\"entries\":[]", new="\"entries\":[{}]"),
      client_local_completion_free_catalog_cid(),
    )
    is Err(SubstitutedJournal),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      local_normalization_fixture(),
      issued,
      wire,
      client_local_completion_free_catalog_cid(),
    )
    is Err(ForeignPreparation),
  )
}
