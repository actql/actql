///|
// Retain the accepted independent ASCII Catalog preimages from the existing
// registered Source fixture. This is typed metadata, not a read permission.
fn prepared_publication_source_environment() -> @program_check.CheckEnvironment {
  let body =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:1a93d68f947af00ba389e9d18601b4d3d9ca34d6af94b320f199a9a6dfe2eeff","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{},"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/records#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:78cffc445d46c9bcd0d7d5b7223332587fab9fedbc69f85c88cb6588ff554143","output":{"carrier":"relation","data_policy":{"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","version":"fixture"},"facts":{"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","version":"fixture"},"schema":{"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"contract_registry":[{"body":{},"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/records#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:b1d539c9bc23f85f9a717f5ed953dc2c3aa3803373f723289757eed4462408f4","host_policy_profile":{},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:78cffc445d46c9bcd0d7d5b7223332587fab9fedbc69f85c88cb6588ff554143","output":{"carrier":"relation","data_policy":{"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","version":"fixture"},"facts":{"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","version":"fixture"},"schema":{"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}
  let wire = @check_environment.read(
    @utf8.encode(body),
    "sha256:b1d539c9bc23f85f9a717f5ed953dc2c3aa3803373f723289757eed4462408f4",
    { max_bytes: 1048576, max_nodes: 16384, max_depth: 32, max_members: 32768, },
  ).unwrap()
  @program_check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
}

///|
fn prepared_publication_source_wire(
  environment : @program_check.CheckEnvironment,
) -> String {
  "{\"environmentCid\":\"" +
  @program_check.checking_environment_cid(environment) +
  "\",\"aliases\":[{\"name\":\"records\",\"sourceRef\":\"connector://crm/main/records#v\",\"sourceViewContractCid\":\"sha256:78cffc445d46c9bcd0d7d5b7223332587fab9fedbc69f85c88cb6588ff554143\",\"schemaContractCid\":\"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759\"}]}"
}

///|
test "new queries retain one original public Environment preparation" {
  let environment = prepared_publication_source_environment()
  let wire = prepared_publication_source_wire(environment)
  let reads = Ref(0)
  let catalog_reads = Ref(0)
  let catalogs : Array[@program_check.PreparedSourceCatalog] = []
  let documents : Array[String] = []
  let prepared = prepare_published_query_environment_with_readers(
    environment,
    wire,
    original => {
      reads.val += 1
      source_publication_cursor(original)
    },
    (owner, limits, contents_limits) => {
      catalog_reads.val += 1
      publication_read_catalog(owner, limits, contents_limits)
    },
  ).unwrap()
  for
    query in ["SELECT id FROM records", "SELECT id + 1 AS next_id FROM records"] {
    let (lowered, catalog) = lower_prepared_published_query(
      prepared,
      environment,
      query,
      @source_frontend.Sql,
      None,
    ).unwrap()
    assert_true(lowered.program is Some(_))
    catalogs.push(catalog)
    documents.push(lowered.document)
  }
  assert_true(documents[0] != documents[1])
  assert_eq(reads.val, 1)
  assert_eq(catalog_reads.val, 1)
  assert_true(physical_equal(catalogs[0], catalogs[1]))
}

///|
test "prepared public Environment rejects an equal-CID foreign checker owner" {
  let environment = prepared_publication_source_environment()
  let prepared = prepare_published_query_environment(
    environment,
    prepared_publication_source_wire(environment),
  ).unwrap()
  let foreign = @program_check.checking_environment(
    @program_check.checking_environment_wire(environment),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  assert_eq(
    @program_check.checking_environment_cid(environment),
    @program_check.checking_environment_cid(foreign),
  )
  assert_false(prepared_published_query_environment_matches(prepared, foreign))
  let publication = prepared_publication_source_wire(environment)
  assert_true(
    prepared_published_query_environment_publication_matches(
      prepared, environment, publication,
    ),
  )
  assert_false(
    prepared_published_query_environment_publication_matches(
      prepared, foreign, publication,
    ),
  )
  assert_false(
    prepared_published_query_environment_publication_matches(
      prepared,
      environment,
      publication + " ",
    ),
  )
  assert_true(
    prepared_published_query_catalog(prepared, foreign)
    is Err(ForeignEnvironment),
  )
  assert_true(
    lower_prepared_published_query(
      prepared,
      foreign,
      "SELECT id FROM records",
      @source_frontend.Sql,
      None,
    )
    is Err(ForeignEnvironment),
  )
  assert_true(
    prepared_published_effect_parts(prepared, foreign)
    is Err(ForeignEnvironment),
  )
  let (_, _, _, original) = prepared_published_effect_parts(
    prepared, environment,
  ).unwrap()
  assert_true(physical_equal(original, prepared.catalog))
  assert_true(
    physical_equal(
      prepared_published_query_catalog(prepared, environment).unwrap(),
      original,
    ),
  )
}

///|
test "prepared public Environment admits each new declaration independently" {
  let environment = prepared_publication_source_environment()
  let prepared = prepare_published_query_environment(
    environment,
    prepared_publication_source_wire(environment),
  ).unwrap()
  let (number, _) = lower_prepared_published_query(
    prepared,
    environment,
    "SELECT @p AS n",
    @source_frontend.Sql,
    Some("{\"p\":{\"type\":\"number\"}}"),
  ).unwrap()
  let (text, _) = lower_prepared_published_query(
    prepared,
    environment,
    "SELECT @p AS n",
    @source_frontend.Sql,
    Some("{\"p\":{\"type\":\"string\"}}"),
  ).unwrap()
  assert_true(number.document != text.document)
  assert_true(prepared.context.parameter_declarations is None)
  assert_true(
    lower_prepared_published_query(
      prepared,
      environment,
      "SELECT 1 AS n",
      @source_frontend.Sql,
      Some("null"),
    )
    is Err(Publication(Declarations)),
  )
  assert_true(
    lower_prepared_published_query(
      prepared,
      environment,
      "SELECT id FROM records",
      @source_frontend.Sql,
      None,
    )
    is Ok(_),
  )
}

///|
test "prepared public Environment validates unused sections and distinct publications" {
  let environment = publication_parts_environment()
  let wire = publication_parts_wire(environment)
  for name in ["tableWrites", "updateTargets", "storeTargets", "commandTargets"] {
    for invalid in ["null", "{}", "[{}]"] {
      assert_true(
        prepare_published_query_environment(
          environment,
          wire.replace(old="\"\{name}\":[]", new="\"\{name}\":\{invalid}"),
        )
        is Err(_),
      )
    }
  }
  let source = prepared_publication_source_environment()
  let original = prepared_publication_source_wire(source)
  let first = prepare_published_query_environment(source, original).unwrap()
  let next = prepare_published_query_environment(
    source,
    original.replace(old="\"records\"", new="\"renamed\""),
  ).unwrap()
  assert_true(
    lower_prepared_published_query(
      first,
      source,
      "SELECT id FROM renamed",
      @source_frontend.Sql,
      None,
    )
    is Err(Frontend(_)),
  )
  assert_true(
    lower_prepared_published_query(
      next,
      source,
      "SELECT id FROM renamed",
      @source_frontend.Sql,
      None,
    )
    is Ok(_),
  )
  assert_true(physical_equal(first.environment, next.environment))
  assert_false(physical_equal(first.context, next.context))
}

///|
test "publication constructor shares Catalog indices only under proven target bounds" {
  let environment = prepared_publication_source_environment()
  let reads = Ref(0)
  let depths : Array[Int] = []
  let contents_depths : Array[Int] = []
  let admission : PublicationEnvironmentAdmission = {
    environment,
    read_catalog: (owner, limits, contents_limits) => {
      reads.val += 1
      depths.push(limits.max_depth)
      contents_depths.push(contents_limits.unwrap().max_depth)
      publication_read_catalog(owner, limits, contents_limits)
    },
    catalog: None,
    catalog_contents_bounded: false,
    mappings: None,
  }
  let first = publication_admission_contents(admission)
  let second = publication_admission_contents(admission)
  assert_true(physical_equal(first, second))
  assert_eq(reads.val, 1)
  assert_eq(depths, [64])
  assert_eq(contents_depths, [32])
  let first_mapping = publication_admission_mappings(admission)
  assert_true(
    physical_equal(first_mapping, publication_admission_mappings(admission)),
  )
  let source_only : PublicationEnvironmentAdmission = {
    environment,
    read_catalog: publication_read_catalog,
    catalog: None,
    catalog_contents_bounded: false,
    mappings: None,
  }
  let _ = publication_admission_catalog(source_only)
  assert_true(
    try {
      let _ = publication_admission_contents(source_only)
      false
    } catch {
      PublicationStop(Publication) => true
      _ => false
    },
  )
}
