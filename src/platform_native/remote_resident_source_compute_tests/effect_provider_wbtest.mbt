// Actual retained Native proposals and a physical HTTPS Provider fixture.
// These observations are not whole-Preview admission, approval or Effect apply.

///|
fn provider_json(wire : String) -> Json {
  @json.parse(wire) catch {
    _ => abort("invalid Provider configuration fixture")
  }
}

///|
fn provider_canonical(value : Json) -> String {
  @canonical.stringify_value(
    @canonical.from_json(value, 20000, 64, 200000),
    200000,
    20000,
    64,
  ) catch {
    _ => abort("invalid Provider configuration fixture")
  }
}

///|
fn provider_binding() -> @catalog.CatalogObservationBinding {
  {
    namespace_id: "namespace-a",
    principal: "principal-a",
    environment: "test",
    connection_revision: "connection-a",
    org_id: "00D000000000001EAA",
    site_key: "retained-native",
    site_generation: 1,
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: retained_runtime_required_env(
      "ACTQL_TEST_NATIVE_HTTP_BEARER_URL",
    ),
    run_invocation_cid: retained_compute_cid("b"),
    dispatch_request_cid: retained_compute_cid("c"),
    sync_occurrence: "sync-a",
  }
}

///|
fn provider_catalog(
  binding : @catalog.CatalogObservationBinding,
) -> @catalog.CatalogObservation {
  let listing = @catalog.project_resource_listing(
    @utf8.encode(
      "{\"sobjects\":[{\"name\":\"ActQL_Test_Record__c\",\"queryable\":true,\"updateable\":true}]}",
    ),
    {
      max_bytes: 4096,
      max_nodes: 100,
      max_depth: 10,
      max_resources: 1,
      max_selected: 1,
      max_name_units: 100,
    },
  ).unwrap()
  let description = @utf8.encode(
    "{\"name\":\"ActQL_Test_Record__c\",\"queryable\":true,\"updateable\":true,\"fields\":[{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false,\"createable\":false,\"updateable\":false},{\"name\":\"Count__c\",\"type\":\"int\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}]}",
  )
  let sync = @catalog.begin_catalog_sync(listing)
  @catalog.catalog_sync_describe(sync, "ActQL_Test_Record__c", description, {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 10,
    max_fields: 2,
    max_name_units: 100,
  }).unwrap()
  @catalog.finish_catalog_sync(sync).unwrap()
  @catalog.prepare_catalog_observation(
    sync,
    binding,
    retained_compute_cid("d"),
    [Some(retained_compute_cid("e"))],
    [Some(@sha.hex(description))],
    8192,
  ).unwrap()
}

///|
fn provider_declaration() -> @catalog.StaticDeclaration {
  let binding = provider_binding()
  @catalog.generate_static_declaration(
    provider_catalog(binding),
    binding,
    @catalog.salesforce_implementation("salesforce/0.1").unwrap(),
    "crm",
    ["ActQL_Test_Record__c"],
    { max_bytes: 200000, max_nodes: 20000, max_depth: 32, },
  ).unwrap()
}

///|
fn provider_mapping() -> @catalog.ExecutionMapping {
  @catalog.prepare_execution_mapping(
    provider_declaration(),
    "ActQL_Test_Record__c",
    @catalog.UpdateById(["Count__c"]),
    { max_bytes: 200000, max_nodes: 20000, max_depth: 32, },
  ).unwrap()
}

///|
fn resident_provider_environment() -> (String, String, String) {
  println("native-effect-provider: preparing declaration")
  let declaration = provider_declaration()
  println("native-effect-provider: preparing mapping")
  let mapping = provider_mapping()
  println("native-effect-provider: composing environment")
  let base = provider_json(resident_effect_source_environment)
  guard base is Object(fields) &&
    fields["connector_catalogs"] is Array(catalogs) &&
    fields["contract_registry"] is Array(contracts) &&
    fields["source_views"] is Array(views) &&
    fields["connector_manifest"] is Object(manifest) else {
    abort("existing checked Source configuration fixture")
  }
  // Compose existing Source evidence with the actual declaration Owner's
  // Catalog, manifest, contracts and Mapping; no generated identity is patched.
  fields["connector_catalogs"] = Json::array([
    catalogs[0],
    provider_json(declaration.catalog),
  ])
  for wire in declaration.contracts {
    contracts.push(provider_json(wire))
  }
  for wire in declaration.view_bodies {
    views.push(provider_json(wire))
  }
  manifest["connectors"] = Json::array([
    provider_json(declaration.manifest_entry),
  ])
  fields["mapping_contracts"] = Json::array([provider_json(mapping.body)])
  // Check Environment sections are ordered by their canonical member CID.
  // Composing two independently generated catalogs must preserve that order.
  for section in ["connector_catalogs", "contract_registry", "source_views"] {
    guard fields[section] is Array(entries) else { abort("fixture section") }
    let indexed = entries.map(value => {
      (@sha.hex(@utf8.encode(provider_canonical(value))), value)
    })
    indexed.sort_by((a, b) => a.0.compare(b.0))
    fields[section] = Json::array(indexed.map(value => value.1))
  }
  fields.remove("evidence_bundle_cid") |> ignore
  let cid = "sha256:" + @sha.hex(@utf8.encode(provider_canonical(base)))
  fields["evidence_bundle_cid"] = Json::string(cid)
  let document = provider_json(resident_native_effect_document)
  guard document is Object(program) &&
    program["stages"] is Array(stages) &&
    stages[1] is Object(consumer) &&
    consumer["results"] is Object(results) &&
    results["r"] is Object(result) &&
    consumer["effects"] is Object(effects) &&
    effects["save"] is Object(effect_member) &&
    effect_member["update"] is Object(update) else {
    abort("existing Effect Program fixture")
  }
  consumer["steps"] = provider_json(
    "[{\"filter\":\"id > 2\"},{\"derive\":{\"record\":{\"literal\":\"001000000000001\"}}},{\"as\":\"out\",\"select\":[\"id\",\"record\"]}]",
  )
  result["fields"] = provider_json("[\"id\",\"record\"]")
  update["id"] = Json::string("record")
  update["mapping"] = Json::string(mapping.mapping_ref)
  update["target"] = Json::string(declaration.writables[0].target_ref)
  update["set"] = provider_json("{\"Count__c\":{\"field\":\"id\"}}")
  println("native-effect-provider: generated configuration and Program")
  (provider_canonical(base), cid, provider_canonical(document))
}

///|
fn resident_provider_observe(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  acquired : @host.ClientEffectAcquiredEvidence,
  dispatch : @remote.DispatchRequest,
  root_path : String,
  name : String,
  deny_provider? : Bool = false,
) -> Unit raise {
  let (_, invocation) = producer_dependency_observation(materials, acquired)
  let initial = provider_binding()
  let binding = {
    ..initial,
    run_invocation_cid: @publication.publication_contract_identity(invocation),
    dispatch_request_cid: @remote.dispatch_request_identity(dispatch),
  }
  let catalog = provider_catalog(binding)
  let mapping = provider_mapping()
  let projection = @catalog.prepare_write_projection(
    catalog,
    binding,
    "ActQL_Test_Record__c",
    @catalog.WriteUpdateById,
    ["Count__c"],
    1,
  ).unwrap()
  let scope : @resource.NativeCredentialScope = {
    principal: binding.principal,
    namespace_id: binding.namespace_id,
    environment: binding.environment,
    site_key: binding.site_key,
    site_generation: binding.site_generation,
    runtime_bundle_cid: retained_compute_cid("a"),
    connector_registration: binding.connector_registration,
    connector_revision: binding.connector_revision,
    resource_origin: binding.resource_origin,
    operation: "salesforce:record:observe",
    run_invocation_cid: binding.run_invocation_cid,
    task_attempt: 1,
    dispatch_request_cid: binding.dispatch_request_cid,
  }
  // Trusted local fixture issuer uses the same common grant Owner. Signature
  // admission is covered by the separate physical target-read boundary tests.
  let grant = @credential.prepare_grant(
    "credential-authority-a",
    scope.principal,
    scope.namespace_id,
    scope.environment,
    scope.site_key,
    scope.site_generation,
    scope.runtime_bundle_cid,
    scope.connector_registration,
    scope.connector_revision,
    scope.resource_origin,
    scope.operation,
    scope.run_invocation_cid,
    scope.task_attempt,
    scope.dispatch_request_cid,
    2000000000000L,
    1,
  ).unwrap()
  let sqlite = @sqlite.load_library(
    retained_runtime_required_env("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"),
  ).unwrap()
  let database = sqlite
    .open_database(root_path + "/" + name + ".provider.sqlite", 65536L)
    .unwrap()
  let client = @http.load_library(
      retained_runtime_required_env("ACTQL_TEST_NATIVE_HTTP_LIBRARY"),
    )
    .unwrap()
    .create_authenticated_client(
      retained_runtime_required_env("ACTQL_TEST_NATIVE_HTTP_CA"),
      @http.Bearer(
        retained_runtime_required_env("ACTQL_TEST_NATIVE_HTTP_BEARER_ROOT") +
        "/control",
      ),
      1024L,
      2000,
      5000,
    )
    .unwrap()
  let stages : Array[String] = []
  let service = @resource.install_native_credential_resource_service(
    database,
    client,
    [
      {
        resource_origin: scope.resource_origin,
        operation: scope.operation,
        path: "/services/data/v66.0/sobjects/ActQL_Test_Record__c/001000000000001",
        secret_path: retained_runtime_required_env(
          "ACTQL_TEST_NATIVE_HTTP_BEARER_ROOT",
        ) +
        "/control",
      },
    ],
    authorization => {
      stages.push(authorization.stage)
      !(deny_provider && authorization.stage == "send")
    },
  ).unwrap()
  let local_count = @strategy.captured_effect_local_result_count(inputs)
  let mut selected = -1
  for index in 0..<local_count {
    if @strategy.captured_effect_local_result_matches_member(inputs, index, 0) {
      selected = index
    }
  }
  assert_true(selected >= 0)
  let access_count = Ref(0)
  let observe = (use_id, limits, effect_id) => {
    @effect_provider.observe_native_resident_effect_targets(
      consumer,
      materials,
      inputs,
      1,
      effect_id,
      selected,
      mapping,
      projection,
      catalog,
      "v66.0",
      resident_compute_limits(),
      { max_bytes: 1024, max_nodes: 32, max_depth: 5, },
      { max_path_bytes: 1024, max_target_bytes: 128, max_body_bytes: 1024, },
      {
        max_bytes: 1024,
        max_nodes: 32,
        max_depth: 5,
        max_identity_bytes: 1024,
      },
      limits,
      16,
      10000,
      10000,
      (_, request) => {
        access_count.val += 1
        if @catalog.single_write_request_body(request) != "{\"Count__c\":3}" {
          return Err(@effect_provider.ForeignScope)
        }
        Ok({ service, grant, use_id, scope, credential_org_id: binding.org_id, })
      },
    )
  }
  assert_true(observe("target-a", 0, "save") is Err(InvalidLimits))
  assert_true(observe("target-a", 1, "another-effect") is Err(ForeignMapping))
  assert_eq(access_count.val, 0)
  let outcome = observe("target-a", 1, "save")
  if deny_provider {
    assert_true(outcome is Err(Provider(Credential(_))))
    assert_eq(
      @resource.query_native_credential_use(service, grant, "target-a", scope).unwrap().outcome,
      "failed",
    )
  } else {
    let rows = outcome.unwrap()
    assert_eq(rows.length(), 1)
    assert_eq(
      @catalog.target_preview_row_target_wire(rows[0].3),
      "\"001000000000001\"",
    )
    assert_eq(
      @catalog.target_preview_row_before_wire(rows[0].3),
      "{\"Count__c\":7}",
    )
    assert_eq(
      @catalog.target_preview_row_after_wire(rows[0].3),
      "{\"Count__c\":3}",
    )
    assert_true(rows[0].1.has_prefix("sha256:"))
    assert_eq(stages, ["claim", "send"])
    let saved = @resource.query_native_credential_use(
      service, grant, "target-a", scope,
    ).unwrap()
    assert_eq(saved.use_cid, rows[0].1)
    assert_eq(saved.outcome, "succeeded")
    assert_eq(saved.status, Some(200))
    // A completed grant use cannot silently be repeated under another read id.
    assert_true(observe("target-b", 1, "save") is Err(Provider(Credential(_))))
    let repeated = @resource.query_native_credential_use(
      service, grant, "target-a", scope,
    ).unwrap()
    assert_eq(repeated.use_cid, saved.use_cid)
    assert_eq(repeated.outcome, saved.outcome)
    assert_eq(repeated.status, saved.status)
    // Current authority is still checked on the rejected second claim/query.
    assert_eq(stages, [
      "claim", "send", "query", "return", "claim", "query", "return",
    ])
  }
  assert_true(consumer.usage().held_bytes > 0L)
  database.close_checked().unwrap()
  assert_true(client.close())
}
