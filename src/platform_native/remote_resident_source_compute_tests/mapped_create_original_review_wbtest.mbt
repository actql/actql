///|
/// Independently installed Catalog response/configuration for the bounded
/// Native create fixture. It is not a physical target observation or grant.
fn native_mapped_create_binding() -> @catalog.CatalogObservationBinding {
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
    resource_origin: @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_BEARER_URL").unwrap_or(
      "https://example.invalid",
    ),
    run_invocation_cid: retained_compute_cid("b"),
    dispatch_request_cid: retained_compute_cid("c"),
    sync_occurrence: "sync-a",
  }
}

///|
fn native_mapped_create_catalog(
  binding : @catalog.CatalogObservationBinding,
) -> @catalog.CatalogObservation {
  let listing = @catalog.project_resource_listing(
    @utf8.encode(
      "{\"sobjects\":[{\"name\":\"ActQL_Test_Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true}]}",
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
    "{\"name\":\"ActQL_Test_Record__c\",\"queryable\":true,\"createable\":true,\"updateable\":true,\"fields\":[{\"name\":\"Id\",\"type\":\"id\",\"nillable\":false,\"createable\":false,\"updateable\":false},{\"name\":\"Count__c\",\"type\":\"int\",\"nillable\":true,\"defaultedOnCreate\":false,\"createable\":true,\"updateable\":true}]}",
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
fn native_mapped_create_declaration() -> @catalog.StaticDeclaration {
  let binding = native_mapped_create_binding()
  @catalog.generate_static_declaration(
    native_mapped_create_catalog(binding),
    binding,
    @catalog.salesforce_implementation("salesforce/0.1").unwrap(),
    "crm",
    ["ActQL_Test_Record__c"],
    { max_bytes: 200000, max_nodes: 20000, max_depth: 32, },
  ).unwrap()
}

///|
fn native_mapped_create_mapping() -> @catalog.ExecutionMapping {
  @catalog.prepare_execution_mapping(
    native_mapped_create_declaration(),
    "ActQL_Test_Record__c",
    @catalog.CreateFromResult([
      { target: "Count__c", source: "id", null_behavior: "reject", },
    ]),
    { max_bytes: 200000, max_nodes: 20000, max_depth: 32, },
  ).unwrap()
}

///|
/// Compose authoring inputs only. The original preparation audits this actual
/// Program and issues normalization/material custody; none is copied here.
fn native_mapped_create_authoring() -> (String, String, String) {
  let declaration = native_mapped_create_declaration()
  let mapping = native_mapped_create_mapping()
  let environment = provider_json(native_completion_free_environment)
  guard environment is Object(fields) &&
    fields["connector_catalogs"] is Array(catalogs) &&
    fields["contract_registry"] is Array(contracts) &&
    fields["source_views"] is Array(views) &&
    fields["connector_manifest"] is Object(manifest) else {
    abort("explicit Source configuration")
  }
  catalogs.push(provider_json(declaration.catalog))
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
  for section in ["connector_catalogs", "contract_registry", "source_views"] {
    guard fields[section] is Array(entries) else {
      abort("configuration inventory")
    }
    let indexed = entries.map(value => {
      (@sha.hex(@utf8.encode(provider_canonical(value))), value)
    })
    indexed.sort_by((a, b) => a.0.compare(b.0))
    fields[section] = Json::array(indexed.map(value => value.1))
  }
  fields.remove("evidence_bundle_cid") |> ignore
  let cid = "sha256:" + @sha.hex(@utf8.encode(provider_canonical(environment)))
  fields["evidence_bundle_cid"] = Json::string(cid)
  let document = provider_json(native_completion_free_document)
  guard document is Object(program) &&
    program["stages"] is Array(stages) &&
    stages[1] is Object(consumer) &&
    consumer["effects"] is Object(effects) &&
    effects["save"] is Object(effect_member) &&
    effect_member["create"] is Object(create) else {
    abort("finite mapped create authoring")
  }
  create["target"] = Json::string(declaration.writables[0].target_ref)
  create["mapping"] = Json::string(mapping.mapping_ref)
  (provider_canonical(environment), cid, provider_canonical(document))
}

///|
/// Real original producer/receiver custody, actual consumer Result and existing
/// Receipt/Preview/Captured Run Owners. No target I/O, approval or write is
/// substituted by this fixture. A full Effect acceptance must extend it.
fn native_mapped_create_context_review(
  holder : @resident.ResidentRetainedConsumer,
  journal : @dispatch_journal.Journal,
  producer : @resident.ResidentEffectProducerExecuted,
  producer_journal : @dispatch_journal.Journal,
  approved_row? : Bool = false,
  journal_path? : String? = None,
) -> Unit raise {
  let consumer = holder.effect_computation(journal).unwrap()
  println("native-mapped-create: original Source and consumer completed")
  let source = producer.source_for_capture(producer_journal).unwrap()
  let source_usage = source.usage()
  let consumer_usage = consumer.usage()
  let context = holder
    .prepare_effect_review_inputs(
      journal,
      producer,
      producer_journal,
      1,
      0,
      retained_compute_effect_retention(),
      resident_compute_limits(),
      4,
      10000,
      65536,
      4096,
      64,
    )
    .unwrap()
  let facts = context.facts(journal).unwrap()
  let original_request = producer.request_for_capture(producer_journal).unwrap()
  assert_eq(facts.materials.request, Some(original_request))
  let normalization = @host.restore_client_effect_run_normalization(
    facts.materials,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(normalization),
    "sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087",
  )
  let invocation = producer
    .invocation_for_capture(producer_journal, 65536, 4096, 64)
    .unwrap().1
  let policy = retained_holder_review_policy(
    holder,
    facts.inputs,
    invocation,
    mapped_create=true,
  )
  let work = @effect_provider.prepare_native_resident_effect_review_from_original_materials(
    holder, journal, context, policy,
  ).unwrap()
  let output = work.result_capture().unwrap().output
  assert_eq(
    output.result_schema_wire().unwrap(),
    retained_effect_expected_schema(false),
  )
  assert_eq(output.row_count().unwrap(), 1)
  let reader = output.replay().unwrap()
  let rows = StringBuilder()
  while reader.next().unwrap() is Some(chunk) {
    rows.write_string(chunk)
  }
  rows.write_string(reader.finish().unwrap())
  assert_eq(rows.to_string(), "[{\"id\":3}]")
  let target_reads = Ref(0)
  let observe = () => {
    work.observe((_, _) => {
      target_reads.val += 1
      abort("mapped create attempted a target read")
    })
  }
  assert_eq(observe().unwrap().length(), 0)
  assert_eq(observe().unwrap().length(), 0)
  assert_eq(target_reads.val, 0)
  let complete = work
    .complete(phase_observe=phase => {
      println("native-mapped-create: review " + phase)
    })
    .unwrap()
  assert_true(complete.preview.proof is None)
  assert_eq(complete.preview.keys.length(), 1)
  assert_true(
    complete.preview.wire.contains("\"before\":{\"state\":\"absent\"}"),
  )
  assert_true(
    complete.preview.wire.contains(
      "\"target_guard\":{\"state\":\"not_applicable\"}",
    ),
  )
  // Independent SHA256 of the normative content preimage, not product output:
  // {"value":{"state":"present","value":{"Count__c":3}},"version":"actql-effect-content-row/0.1"}
  assert_true(
    complete.preview.wire.contains(
      "\"target_row_identity\":{\"content_cid\":\"sha256:4f29da598fc804d2fcd0c41a4a034ee4c196f28aa2b4619169586d5a8db391d0\",\"occurrence\":0}",
    ),
  )
  assert_true(
    complete.preview.wire.contains(
      "\"intended_changes\":{\"state\":\"present\",\"value\":{\"Count__c\":3}}",
    ),
  )
  assert_eq(work.complete().unwrap().preview.wire, complete.preview.wire)
  assert_eq(target_reads.val, 0)
  if approved_row {
    // Local trusted signing peer only. The common Owner still admits its
    // exact original report/Resolution and separately checks current send
    // authority. This does not establish a production Cloud approval.
    assert_eq(
      @env.get_env_var("ACTQL_TEST_NATIVE_EFFECT_APPROVED_ROW"),
      Some("1"),
    )
    retained_effect_review_retention_store(
      consumer,
      facts.materials,
      facts.inputs,
      work.result_capture().unwrap(),
      invocation,
      complete.preview.preview,
      complete.captured,
      policy.store_authority_cid,
      complete.preview.wire,
      @publication.run_evidence_value_identity(complete.preview.authoring),
      review_work=Some(work),
      original_journal_path=journal_path,
    )
    assert_true(work.retry_cleanup().unwrap())
  } else {
    native_mapped_create_checkpoint_roundtrip(
      work, journal, consumer, policy, complete,
    )
  }
  assert_false(work.retry_cleanup().unwrap())
  assert_eq(target_reads.val, 0)
  assert_true(context.close())
  assert_true(context.facts(journal) is None)
  assert_eq(source.usage().held_bytes, source_usage.held_bytes)
  assert_eq(
    source.usage().reserved_retention_bytes,
    source_usage.reserved_retention_bytes,
  )
  assert_eq(consumer.usage().held_bytes, consumer_usage.held_bytes)
  assert_eq(
    consumer.usage().reserved_retention_bytes,
    consumer_usage.reserved_retention_bytes,
  )
}
