///|
// Copy the independent complete preimages, not product-derived identities.
// Installed Reference issuance and current permissions are not proved here.
fn published_store_environment(kind : String) -> @environment.WireEnvironment {
  let (wire, cid) = match kind {
    "object" =>
      (
        (
          #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:b68e536b6a4324573fc3ac3d39904dcab677c9ec0f1c624f12994b920270a2dd","commands":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"evidence_bundle_cid":"sha256:a3fc9bc8b36a77651425b10479d518ccfcaf89a0f6bb05a8c38690b003232a2a","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:8cb37a084de7d9c2092baffabb3ab29a8663aad8ad9a4b9d806e15fd98e77295","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"store","permissions":["scope:write"],"selector_class":"none","write_fields":["id","value"]}],"primary_identity":"id","required_fields":["id","value"],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"id":{"field":"id","null_behavior":"reject"},"value":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:b68e536b6a4324573fc3ac3d39904dcab677c9ec0f1c624f12994b920270a2dd","command_contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","command_ref":"command:fixture.upload.v1"},"target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bd89154b566792abefae13b781921bdb85725e117f241b99ce245d14d0efa37a","version":"fixture-1","writable_fields":["id","value"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
        "sha256:a3fc9bc8b36a77651425b10479d518ccfcaf89a0f6bb05a8c38690b003232a2a",
      )
    "collection" =>
      (
        (
          #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:a937153e39e2f69f5d6893275d3b6a7457498cc22627a1152627d473897f8757","commands":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"evidence_bundle_cid":"sha256:7f95bc33d267e6ed3009a7a920c1cd7adc2f08736456b60e45068812bf4f0cb6","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:7d2514050811313eeb33ef05a6a694c0dfb5bbfd6cf1347a072853b6320b459a","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"create","permissions":["scope:write"],"selector_class":"none","write_fields":["content","path"]}],"primary_identity":null,"required_fields":["content","path"],"required_permissions":[],"resource_identity_cid":"sha256:e3d4f3b2c3b392c4c889b78ea6b4794bc6a715d39a740275ab3c936d20ec6759","row_mapping":{"content":{"field":"content","null_behavior":"reject"},"path":{"field":"path","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:a937153e39e2f69f5d6893275d3b6a7457498cc22627a1152627d473897f8757","command_contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","command_ref":"command:fixture.upload.v1"},"target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:793f546b62fd8f3db0862d0369fc5451de8cee5fce0bd2408d7749efc6c3c336","version":"fixture-1","writable_fields":["content","path"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
        "sha256:7f95bc33d267e6ed3009a7a920c1cd7adc2f08736456b60e45068812bf4f0cb6",
      )
    "collectionWithoutCommand" =>
      (
        (
          #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:a937153e39e2f69f5d6893275d3b6a7457498cc22627a1152627d473897f8757","commands":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"evidence_bundle_cid":"sha256:4111196f24f43e7e6ca25ea0d2c952e742e0ae7c7f9f98340728dd3e9e5bd775","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:4d00b207b84dde08ce838671cd849200b4964537e3959d0422c7ba85e7e8b967","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"create","permissions":["scope:write"],"selector_class":"none","write_fields":["content","path"]}],"primary_identity":null,"required_fields":["content","path"],"required_permissions":[],"resource_identity_cid":"sha256:e3d4f3b2c3b392c4c889b78ea6b4794bc6a715d39a740275ab3c936d20ec6759","row_mapping":{"content":{"field":"content","null_behavior":"reject"},"path":{"field":"path","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:793f546b62fd8f3db0862d0369fc5451de8cee5fce0bd2408d7749efc6c3c336","version":"fixture-1","writable_fields":["content","path"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
        "sha256:4111196f24f43e7e6ca25ea0d2c952e742e0ae7c7f9f98340728dd3e9e5bd775",
      )
    "collectionForeignCatalog" =>
      (
        (
          #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:a937153e39e2f69f5d6893275d3b6a7457498cc22627a1152627d473897f8757","commands":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"evidence_bundle_cid":"sha256:a62efc3aa9a23d4355f511b1e819f1bd549e475734990d4b84a28347bc407067","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:ee7b2d448c4cf51acb038f24bf3ce37721b8e89e84f098dd1925e1d99f602e70","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"create","permissions":["scope:write"],"selector_class":"none","write_fields":["content","path"]}],"primary_identity":null,"required_fields":["content","path"],"required_permissions":[],"resource_identity_cid":"sha256:e3d4f3b2c3b392c4c889b78ea6b4794bc6a715d39a740275ab3c936d20ec6759","row_mapping":{"content":{"field":"content","null_behavior":"reject"},"path":{"field":"path","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","command_contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","command_ref":"command:fixture.upload.v1"},"target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:793f546b62fd8f3db0862d0369fc5451de8cee5fce0bd2408d7749efc6c3c336","version":"fixture-1","writable_fields":["content","path"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
        "sha256:a62efc3aa9a23d4355f511b1e819f1bd549e475734990d4b84a28347bc407067",
      )
    _ => abort("unknown original STORE preimage")
  }
  @environment.read(@utf8.encode(wire), cid, {
    max_bytes: 40000,
    max_nodes: 4000,
    max_depth: 100,
    max_members: 100,
  }).unwrap()
}

///|
fn published_store_parts(
  environment : @environment.WireEnvironment,
) -> (@environment.MappingContractShapes, @environment.CatalogReferences) {
  let limits : @environment.Limits = {
    max_bytes: 40000,
    max_nodes: 4000,
    max_depth: 100,
    max_members: 100,
  }
  let mappings = @environment.check_mapping_contract_shapes(
    environment, limits, 10000,
  ).unwrap()
  let registry = @environment.check_contract_registry(environment, limits).unwrap()
  let catalogs = @environment.check_catalog_contents(registry, limits).unwrap()
  let references = @environment.check_catalog_references(catalogs, {
    max_work: 10000,
    max_references: 100,
  }).unwrap()
  (mappings, references)
}

///|
fn published_store_result_bindings(
  target? : String = "connector://storage/archive",
  mapping? : String = "mapping:fixture.archive.v1",
  contract? : String = "command:fixture.upload.v1",
) -> EffectResultBindings {
  let effects = "{\"upload\":{\"command\":{\"from\":{\"result\":\"r\"},\"target\":{\"published_store\":{\"target_ref\":\"" +
    target +
    "\",\"mapping_ref\":\"" +
    mapping +
    "\"}},\"contract\":\"" +
    contract +
    "\",\"input\":{}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  bind_effect_results(headers, checked, 100).unwrap()
}

///|
test "published STORE target keeps original collection pair and Effect occurrence without a row Ref" {
  let (mappings, references) = published_store_parts(
    published_store_environment("collection"),
  )
  let effects = published_store_result_bindings()
  let targets = bind_effect_command_targets(
    effects,
    references,
    100,
    mappings=Some(mappings),
  ).unwrap()
  assert_eq(effect_command_target_count(targets), 2)
  for index in 0..<2 {
    let binding = effect_command_target_at(targets, index).unwrap()
    let effect = effect_result_binding_at(effects, index).unwrap()
    assert_true(physical_equal(effect_command_target_effect(binding), effect))
    assert_eq(effect_result_field_binding_count(effect), 0)
    let pair = effect_command_target_store_binding(binding).unwrap()
    assert_true(
      physical_equal(
        @environment.store_command_mapping(pair),
        @environment.mapping_shape_for(mappings, "mapping:fixture.archive.v1").unwrap(),
      ),
    )
    assert_true(
      physical_equal(
        @environment.store_command_target(pair),
        effect_command_target_contract(binding),
      ),
    )
    assert_eq(
      @environment.store_command_mapping_operation(pair),
      ("create", "none"),
    )
    assert_eq(
      @environment.command_target_cid(effect_command_target_contract(binding)),
      "sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2",
    )
    assert_eq(
      @syntax.effect_header_stage(effect_result_binding_header(effect)),
      index,
    )
  }
  let work = effect_command_targets_work(targets)
  assert_true(
    bind_effect_command_targets(
      effects,
      references,
      work,
      mappings=Some(mappings),
    )
    is Ok(_),
  )
  assert_eq(
    effect_command_target_issue_kind(
      bind_effect_command_targets(
        effects,
        references,
        work - 1,
        mappings=Some(mappings),
      ).unwrap_err(),
    ),
    WorkLimit,
  )
}

///|
test "published STORE selection refuses missing copied and unrelated original metadata" {
  let (mappings, references) = published_store_parts(
    published_store_environment("collection"),
  )
  let effects = published_store_result_bindings()
  assert_eq(
    effect_command_target_issue_kind(
      bind_effect_command_targets(effects, references, 100).unwrap_err(),
    ),
    MissingStoreMappings,
  )
  let (copied, _) = published_store_parts(
    published_store_environment("collection"),
  )
  assert_eq(
    effect_command_target_issue_kind(
      bind_effect_command_targets(
        effects,
        references,
        100,
        mappings=Some(copied),
      ).unwrap_err(),
    ),
    ForeignEnvironment,
  )
  for
    (effects, expected) in [
      (
        published_store_result_bindings(mapping="mapping:fixture.missing.v1"),
        EffectCommandTargetIssueKind::MissingStoreMapping(
          "mapping:fixture.missing.v1",
        ),
      ),
      (
        published_store_result_bindings(target="connector://storage/other"),
        EffectCommandTargetIssueKind::StoreTargetMismatch,
      ),
      (
        published_store_result_bindings(contract="command:fixture.other.v1"),
        EffectCommandTargetIssueKind::StoreContractMismatch,
      ),
    ] {
    let issue = bind_effect_command_targets(
      effects,
      references,
      100,
      mappings=Some(mappings),
    ).unwrap_err()
    assert_eq(effect_command_target_issue_kind(issue), expected)
    assert_eq(effect_command_target_issue_stage(issue), 0)
    assert_eq(effect_command_target_issue_effect(issue), "upload")
  }
}

///|
test "published STORE refuses missing relationship and foreign Catalog instead of inferring a Command" {
  for
    (kind, expected) in [
      (
        "collectionWithoutCommand",
        @environment.StoreCommandIssue::MissingRelationship,
      ),
      (
        "collectionForeignCatalog",
        @environment.StoreCommandIssue::ForeignCatalog,
      ),
    ] {
    let (mappings, references) = published_store_parts(
      published_store_environment(kind),
    )
    let issue = bind_effect_command_targets(
      published_store_result_bindings(),
      references,
      100,
      mappings=Some(mappings),
    ).unwrap_err()
    assert_eq(effect_command_target_issue_kind(issue), StoreBinding(expected))
  }
}

///|
test "static candidate passes its same admitted Mapping owner into published STORE selection" {
  let environment = published_store_environment("object")
  let (mappings, references) = published_store_parts(environment)
  let effects = "{\"upload\":{\"command\":{\"from\":{\"result\":\"r\"},\"target\":{\"published_store\":{\"target_ref\":\"connector://storage/archive\",\"mapping_ref\":\"mapping:fixture.archive.v1\"}},\"contract\":\"command:fixture.upload.v1\",\"input\":{\"id\":{\"literal\":\"one\"},\"value\":{\"literal\":\"original\"}}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let candidate = prepare_effect_static_candidate(
    headers,
    checked,
    environment,
    mappings,
    references,
    effect_static_candidate_limits(),
  ).unwrap()
  assert_eq(
    effect_command_input_count(
      effect_static_candidate_command_inputs(candidate),
    ),
    2,
  )
  assert_eq(
    effect_mapping_rule_count(effect_static_candidate_mapping_rules(candidate)),
    0,
  )
  // Structural selection cannot act as an installed ReferenceIssuer. The old
  // row-only projection must refuse instead of manufacturing a target.
  let input = effect_command_input_at(
    effect_static_candidate_command_inputs(candidate),
    0,
  ).unwrap()
  assert_eq(
    project_effect_command_row(
      input,
      effect_plan_test_row("{\"amount\":1}"),
      10,
      100,
      1000,
      100,
      10,
    ).unwrap_err(),
    EffectCommandRowIssue::MissingTarget,
  )
  let targets = effect_static_candidate_command_targets(candidate)
  assert_true(
    effect_command_target_store_binding(
      effect_command_target_at(targets, 0).unwrap(),
    )
    is Some(_),
  )
  let work = effect_static_candidate_work(candidate)
  assert_true(
    prepare_effect_static_candidate(
      headers,
      checked,
      environment,
      mappings,
      references,
      effect_static_candidate_limits(work~),
    )
    is Ok(_),
  )
  assert_true(
    prepare_effect_static_candidate(
      headers,
      checked,
      environment,
      mappings,
      references,
      effect_static_candidate_limits(work=work - 1),
    )
    is Err(_),
  )
}
