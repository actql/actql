///|
// Independent ASCII Catalog preimages use Python hashlib, not product encoding.
// The original declaration stays crm/main records with no authored view selector.
fn registered_test_context() -> @query.Context raise {
  let result = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:1a93d68f947af00ba389e9d18601b4d3d9ca34d6af94b320f199a9a6dfe2eeff","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{},"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/records#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:78cffc445d46c9bcd0d7d5b7223332587fab9fedbc69f85c88cb6588ff554143","output":{"carrier":"relation","data_policy":{"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","version":"fixture"},"facts":{"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","version":"fixture"},"schema":{"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"contract_registry":[{"body":{},"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/records#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:b1d539c9bc23f85f9a717f5ed953dc2c3aa3803373f723289757eed4462408f4","host_policy_profile":{},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:e73bfa7a6b921c43e087f7d199e5fa714671e920eb4ea361ecab141cfa85d5f7","id":"member-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:78cffc445d46c9bcd0d7d5b7223332587fab9fedbc69f85c88cb6588ff554143","output":{"carrier":"relation","data_policy":{"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","version":"fixture"},"facts":{"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","version":"fixture"},"schema":{"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:b1d539c9bc23f85f9a717f5ed953dc2c3aa3803373f723289757eed4462408f4",
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
  )
  let wire = match result {
    Ok(wire) => wire
    Err(issue) => fail("independent Environment admission: " + @debug.to_string(issue))
  }
  let environment = @check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    graph=true,
  )
  let prepared = @check.prepare_source_catalog(environment, {
    max_work: 1000000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  {
    ..test_context(),
    source_catalog: Some(@check.source_catalog_contracts(prepared)),
  }
}

///|
test "derived JOIN input requires original Source Catalog metadata" {
  let source = "SELECT COUNT(*) AS n FROM records CROSS JOIN (SELECT 1 AS k) AS s MAX_OUTPUT_ROWS 10 WHERE records.id > 0 HAVING COUNT(*) > 1"
  guard lower(source, Sql, Some(test_context())) is Err(QueryLowering(@query.BindingPreparation(MissingSourceCatalog(_)))) else {
    fail("missing Catalog must not acquire an invented schema or Source registration")
  }
  let context = registered_test_context()
  assert_eq(context.inputs[0].name, "source")
  assert_eq(context.inputs[0].relation, [{ value: "records", quoted: false, }])
  assert_eq(context.inputs[0].visible_fields, ["id"])
  guard context.inputs[0].source is @query.Captured(declaration) else {
    fail("the original captured input must be retained")
  }
  let object = @wire.open_object(declaration).unwrap()
  assert_true(@wire.lookup(object, "view") is None)
  assert_true(lower(source, Sql, Some(context)) is Ok(_))
}
