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
fn native_mapped_create_authoring() -> (String, String, String) raise {
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
  // Replace only the old Effect connection declaration. Keep the separate
  // original Source connections and avoid two versions of the same Catalog.
  fields["connector_catalogs"] = Json::array(
    catalogs.filter(value => {
      guard value is Object(catalog) else { abort("authoring Catalog") }
      catalog["connector_id"] != Json::string("crm")
    }),
  )
  guard fields["connector_catalogs"] is Array(installed_catalogs) &&
    manifest["connectors"] is Array(connectors) else {
    abort("authoring connector inventory")
  }
  installed_catalogs.push(provider_json(declaration.catalog))
  for wire in declaration.contracts {
    contracts.push(provider_json(wire))
  }
  for wire in declaration.view_bodies {
    views.push(provider_json(wire))
  }
  let installed_connectors = connectors.filter(value => {
    guard value is Object(connector) else { abort("authoring connector") }
    connector["connector"] != Json::string("crm")
  })
  installed_connectors.push(provider_json(declaration.manifest_entry))
  let indexed_connectors = installed_connectors.map(value => {
    (@sha.hex(@utf8.encode(provider_canonical(value))), value)
  })
  indexed_connectors.sort_by((a, b) => a.0.compare(b.0))
  manifest["connectors"] = Json::array(indexed_connectors.map(value => value.1))
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
  let wire = provider_canonical(environment)
  match
    @environment.read(@utf8.encode(wire), cid, {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 64,
      max_members: 256,
    }) {
    Ok(_) => ()
    Err(issue) => fail("Mapped create authoring: " + @debug.to_string(issue))
  }
  (wire, cid, provider_canonical(document))
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
  native_mapped_create_phase("original-holders")
  let consumer = holder.effect_computation(journal).unwrap()
  println("native-mapped-create: original Source and consumer completed")
  let source = producer.source_for_capture(producer_journal).unwrap()
  let source_usage = source.usage()
  let consumer_usage = consumer.usage()
  native_mapped_create_phase("context-preparing")
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
  native_mapped_create_phase("context-prepared")
  let facts = context.facts(journal).unwrap()
  let original_request = producer.request_for_capture(producer_journal).unwrap()
  assert_eq(facts.materials.request, Some(original_request))
  native_mapped_create_phase("normalization-restoring")
  let normalization = @host.restore_client_effect_run_normalization(
    facts.materials,
  ).unwrap()
  native_mapped_create_phase("normalization-restored")
  assert_eq(
    @publication.run_evidence_value_identity(normalization),
    "sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087",
  )
  let invocation = producer
    .invocation_for_capture(producer_journal, 65536, 4096, 64)
    .unwrap().1
  let policy = retained_holder_review_policy(
    holder,
    journal,
    facts.inputs,
    invocation,
    mapped_create=true,
  )
  native_mapped_create_phase("review-preparing")
  let work = @effect_provider.prepare_native_resident_effect_review_from_original_materials(
    holder, journal, context, policy,
  ).unwrap()
  native_mapped_create_phase("review-prepared")
  let output = work.result_capture().unwrap().output
  assert_eq(
    output.result_schema_wire().unwrap(),
    retained_effect_expected_schema(false),
  )
  assert_eq(output.row_count().unwrap(), 1)
  native_mapped_create_phase("result-reader-opening")
  let reader = output.replay().unwrap()
  native_mapped_create_phase("result-reader-opened")
  let rows = StringBuilder()
  while reader.next().unwrap() is Some(chunk) {
    native_mapped_create_phase("result-chunk-read")
    rows.write_string(chunk)
  }
  native_mapped_create_phase("result-eof")
  rows.write_string(reader.finish().unwrap())
  assert_eq(rows.to_string(), "[{\"id\":3}]")
  native_mapped_create_phase("result-verified")
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
  native_mapped_create_phase("target-observation-complete")
  let complete = work
    .complete(
      phase_observe=phase => {
        native_mapped_create_phase("review-" + phase)
        println("native-mapped-create: review " + phase)
      },
      capture_progress=(phase, _, _) => {
        let name = match phase {
          Preparing => "preparing"
          Prepared => "prepared"
          Advancing => "advancing"
          Completed => "completed"
        }
        native_mapped_create_phase("capture-" + name)
      },
    )
    .unwrap()
  native_mapped_create_phase("review-completed")
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
  native_mapped_create_phase("cleanup-started")
  if approved_row {
    // Local trusted signing peer only. The common Owner still admits its
    // exact original report/Resolution and separately checks current send
    // authority. This does not establish a production Cloud approval.
    assert_true(
      @env.get_env_var("ACTQL_TEST_NATIVE_EFFECT_APPROVED_ROW") == Some("1") ||
      @env.get_env_var("ACTQL_TEST_NATIVE_EFFECT_CREATE_FIXTURE") == Some("1"),
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
      approved_row=true,
      original_journal_path=journal_path,
      original_context=Some((context, journal)),
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
  native_mapped_create_phase("review-cleanup-confirmed")
}

///|
/// Fixed, nonsecret fixture markers survive a killed test and buffered stdout.
/// They establish only entry at this boundary, never completion of later work.
/// Repeated progress at the same phase keeps a single marker directory.
fn native_mapped_create_phase(phase : String) -> Unit {
  let root = @filesystem.open_root(
    retained_runtime_required_env("ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT"),
  ).unwrap()
  let name = "mapped-create-phase-" + phase
  if root.inspect_directory(name).unwrap() is None {
    root.create_directory(name).unwrap() |> ignore
    root.sync_directory().unwrap()
  }
}

///|
test "mapped create authoring retains original Source and Effect connections" {
  let (materials, request, _) = native_completion_free_effect_fixture(
    authoring=Some(native_mapped_create_authoring()),
  )
  assert_eq(materials.request, Some(request))
  assert_true(
    @host.prepare_client_effect_source_input_binding(
      materials.compilation,
      request=Some(request),
    )
    is Ok(_),
  )
}
