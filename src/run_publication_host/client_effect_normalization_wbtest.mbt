///|
fn normalization_fixture(
  document? : String = "",
) -> PreparedClientEffectComputation {
  let (base, environment, limits) = client_composed_effect_base_fixture()
  prepare_client_effect_computation(
    if document == "" {
      base
    } else {
      document
    },
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
}

///|
test "original preparation normalization has independent fixed bytes and cached issuance" {
  let owner = normalization_fixture()
  let issued = issue_prepared_client_effect_normalization(owner).unwrap()
  let journal = prepared_client_effect_normalization_evidence(owner, issued).unwrap()
  // Independently authored canonical preimage and identities. They are not
  // calculated from the issued journal or changed to match product output.
  let preimage =
    #|{"entries":[],"rule_catalog_cid":"sha256:ea21a2a2ab522cbf960c5e97120648e351db7c127768101502210ed7d8fcfb38","version":"actql-normalization-journal/0.1"}
  assert_eq(
    "sha256:" + @sha.hex(@utf8.encode(preimage)),
    "sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087",
  )
  assert_eq(
    @publication.run_evidence_value_identity(journal),
    "sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087",
  )
  assert_true(
    physical_equal(
      issued,
      issue_prepared_client_effect_normalization(owner).unwrap(),
    ),
  )
  let other = normalization_fixture()
  let second = issue_prepared_client_effect_normalization(other).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(journal),
    @publication.run_evidence_value_json(
      prepared_client_effect_normalization_evidence(other, second).unwrap(),
    ),
  )
}

///|
test "normalization refuses foreign preparation and copied projection before review" {
  let owner = normalization_fixture()
  let original = issue_prepared_client_effect_normalization(owner).unwrap()
  let foreign = normalization_fixture()
  assert_true(
    prepared_client_effect_normalization_evidence(foreign, original)
    is Err(ForeignPreparation),
  )
  let copied : ClientEffectNormalization = {
    owner: original.owner,
    inventory: original.inventory,
    journal: original.journal,
  }
  assert_true(
    prepared_client_effect_normalization_evidence(owner, copied)
    is Err(ForeignPreparation),
  )
}

///|
test "normalization restoration preserves exact bytes and refuses catalog or journal substitution" {
  let owner = normalization_fixture()
  let original = issue_prepared_client_effect_normalization(owner).unwrap()
  let evidence = prepared_client_effect_normalization_evidence(owner, original).unwrap()
  let wire = @publication.run_evidence_value_json(evidence)
  let restored = restore_prepared_client_effect_normalization(
    owner,
    original,
    wire,
    client_effect_completion_free_catalog_cid(),
  ).unwrap()
  assert_eq(@publication.run_evidence_value_json(restored), wire)
  assert_true(
    restore_prepared_client_effect_normalization(
      owner,
      original,
      wire,
      "sha256:" + "a".repeat(64),
    )
    is Err(ForeignCatalog),
  )
  assert_true(
    restore_prepared_client_effect_normalization(
      owner,
      original,
      wire.replace(old="ea21a2a2", new="0a21a2a2"),
      client_effect_completion_free_catalog_cid(),
    )
    is Err(SubstitutedJournal),
  )
}

///|
test "actual checked template macro cannot enter the empty normalization profile" {
  let (document, _, _) = client_composed_effect_base_fixture()
  let changed = document.replace(
    old="\"as\":\"selected\"}],",
    new="\"as\":\"selected\"},{\"filter\":{\"eq\":[{\"template\":\"{value}\"},{\"literal\":\"1\"}]}}],",
  )
  assert_true(changed != document)
  let owner = normalization_fixture(document=changed)
  assert_true(
    issue_prepared_client_effect_normalization(owner)
    is Err(Inventory(CompletionObserved)),
  )
  assert_true(owner.normalization is None)
}

///|
test "unaudited checked processing is explicit profile refusal rather than empty proof" {
  let (document, _, _) = client_composed_effect_base_fixture()
  let changed = document.replace(
    old="\"as\":\"selected\"}],",
    new="\"as\":\"selected\"},{\"take\":1}],",
  )
  assert_true(changed != document)
  let owner = normalization_fixture(document=changed)
  assert_true(
    issue_prepared_client_effect_normalization(owner)
    is Err(Inventory(ProfileNotInstalled)),
  )
  assert_true(owner.normalization is None)
}

///|
fn normalization_source_fixture(
  explicit_view : Bool,
) -> PreparedClientEffectComputation {
  let document =
    #|{"version":"actql/0.1","id":"normalization-source","stages":[{"id":"source","inputs":{"table":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"filter":{"gte":[{"field":"id"},{"literal":0}]}},{"select":[{"value":"id"}],"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}}},{"id":"apply","inputs":{"input":{"result":{"stage":"source","result":"out"}}},"steps":[{"select":["value"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"apply","result":"out"}}}}
  let environment = admit_client_check_environment(
    local_normalization_environment_wire,
    "sha256:e3da0e91ef758728bdf6e58957c09fe044d97d1fa2a21c9c19e3bdf5109bf45b",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let (_, _, base_limits) = client_composed_effect_base_fixture()
  let limits = {
    ..base_limits,
    program: client_standard_program_preparation_limits(),
  }
  let prepared = prepare_client_effect_computation(
    if explicit_view {
      document
    } else {
      document.replace(old=",\"view\":\"v\"", new="")
    },
    Json,
    environment,
    None,
    [],
    limits,
  )
  match prepared {
    Err(Syntax(_)) => println("normalization Source fixture: Syntax")
    Err(Candidate(_)) => println("normalization Source fixture: Candidate")
    Err(Mapping(_)) => println("normalization Source fixture: Mapping")
    Err(Static(_)) => println("normalization Source fixture: Static")
    Err(Stage(_)) => println("normalization Source fixture: Stage")
    Err(Graph(_)) => println("normalization Source fixture: Graph")
    Err(TargetSelection(_)) =>
      println("normalization Source fixture: TargetSelection")
    Ok(_) => ()
  }
  prepared.unwrap()
}

///|
test "actual explicit Source filter and select have preparation-owned empty inventory" {
  let owner = normalization_source_fixture(true)
  let original = issue_prepared_client_effect_normalization(owner).unwrap()
  let journal = prepared_client_effect_normalization_evidence(owner, original).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(journal),
    "sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087",
  )
  guard original.inventory is MappedCreate(inventory) else {
    fail("create profile")
  }
  assert_true(@checked.completion_free_inventory_work(inventory) > 0)
  let foreign = normalization_fixture()
  assert_true(
    prepared_client_effect_normalization_evidence(foreign, original)
    is Err(ForeignPreparation),
  )
}

///|
test "actual sole-view Source completion cannot issue the empty catalog journal" {
  let owner = normalization_source_fixture(false)
  assert_true(
    issue_prepared_client_effect_normalization(owner)
    is Err(Inventory(CompletionObserved)),
  )
  assert_true(owner.normalization is None)
}

///|
test "retired Effect custody severs cached backedges without discarding escaped original data" {
  let owner = normalization_fixture()
  let original = issue_prepared_client_effect_normalization(owner).unwrap()
  let journal = prepared_client_effect_normalization_evidence(owner, original).unwrap()
  let wire = @publication.run_evidence_value_json(journal)
  assert_true(physical_equal(original, issue_prepared_client_effect_normalization(owner).unwrap()))
  let foreign = normalization_fixture()
  let foreign_original = issue_prepared_client_effect_normalization(foreign).unwrap()
  // The caller has already finished its original logical capacity. This pure
  // domain operation only severs caches; it cannot release escaped aliases.
  clear_prepared_client_effect_custody_after_cleanup(owner)
  assert_true(owner.normalization is None && owner.normalization_custody is None)
  assert_true(prepared_client_effect_normalization_evidence(owner, original) is Err(ForeignPreparation))
  assert_eq(@publication.run_evidence_value_json(original.journal), wire)
  assert_true(physical_equal(foreign_original, issue_prepared_client_effect_normalization(foreign).unwrap()))
  clear_prepared_client_effect_custody_after_cleanup(owner)
}
