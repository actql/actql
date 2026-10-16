///|
// Source-context admission also needs the Command input/output reference closure.
// The earlier target-kind-only component fixtures deliberately did not claim it.
fn store_source_fixture(kind : String) -> @environment.WireEnvironment {
  let (wire, expected) = match kind {
    "object" =>
      (
        (
          #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:b68e536b6a4324573fc3ac3d39904dcab677c9ec0f1c624f12994b920270a2dd","commands":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"evidence_bundle_cid":"sha256:a3fc9bc8b36a77651425b10479d518ccfcaf89a0f6bb05a8c38690b003232a2a","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:8cb37a084de7d9c2092baffabb3ab29a8663aad8ad9a4b9d806e15fd98e77295","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"store","permissions":["scope:write"],"selector_class":"none","write_fields":["id","value"]}],"primary_identity":"id","required_fields":["id","value"],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"id":{"field":"id","null_behavior":"reject"},"value":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:b68e536b6a4324573fc3ac3d39904dcab677c9ec0f1c624f12994b920270a2dd","command_contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","command_ref":"command:fixture.upload.v1"},"target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bd89154b566792abefae13b781921bdb85725e117f241b99ce245d14d0efa37a","version":"fixture-1","writable_fields":["id","value"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
        "sha256:a3fc9bc8b36a77651425b10479d518ccfcaf89a0f6bb05a8c38690b003232a2a",
      )
    "foreignCatalog" =>
      (
        (
          #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:b68e536b6a4324573fc3ac3d39904dcab677c9ec0f1c624f12994b920270a2dd","commands":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:064d69d0cc1d5179f1349ec9d3c64c49fc620ab725bf3964c8a26a61578cd42b","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"evidence_bundle_cid":"sha256:c9fb61bd279c669b142589ee28e90b3e18030bcc78d60432ed56de8563eecd58","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:152b98bd787fa182f0aaab6a8b7900b82517a285b1147cd65b11a5e43bb70351","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"store","permissions":["scope:write"],"selector_class":"none","write_fields":["id","value"]}],"primary_identity":"id","required_fields":["id","value"],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"id":{"field":"id","null_behavior":"reject"},"value":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","command_contract_cid":"sha256:3768a016ccb69b496ebed661020966ce09ca6d836a89331937e131f891123853","command_ref":"command:fixture.upload.v1"},"target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"string"},"value":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:bd89154b566792abefae13b781921bdb85725e117f241b99ce245d14d0efa37a","version":"fixture-1","writable_fields":["id","value"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
        "sha256:c9fb61bd279c669b142589ee28e90b3e18030bcc78d60432ed56de8563eecd58",
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
    _ => abort("unknown complete Source-catalog preimage")
  }
  @environment.read(@utf8.encode(wire), expected, {
    max_bytes: 40000,
    max_nodes: 4000,
    max_depth: 100,
    max_members: 100,
  }).unwrap()
}

///|
fn store_source_environment(kind : String) -> @check.CheckEnvironment {
  let wire = if kind == "object" ||
    kind == "foreignCatalog" ||
    kind.has_prefix("collection") {
    store_source_fixture(kind)
  } else {
    @environment.mapping_shape_environment(store_target_fixture(kind).0)
  }
  @check.checking_environment(wire, { text_time: false, veca: false, }, {
    rela: true,
    sga: false,
    tea: false,
    calendar: false,
    text_rank: false,
  })
}

///|
fn store_source_publication(environment : @check.CheckEnvironment) -> String {
  "{\"environmentCid\":\"" +
  @check.checking_environment_cid(environment) +
  "\",\"aliases\":[],\"storeTargets\":[{\"name\":\"storage.archive\",\"targetRef\":\"connector://storage/archive\",\"installationBindingCid\":\"sha256:" +
  "d".repeat(64) +
  "\",\"installationOwnerCid\":\"sha256:" +
  "e".repeat(64) +
  "\"}]}"
}

///|
test "Host STORE publication binds original Catalog Mapping and installation" {
  let environment = store_source_environment("object")
  let wire = store_source_publication(environment)
  let publication = @source_publication.published_store_targets(
      environment, wire,
    )
    .unwrap()
    .unwrap()
  let selected = resolve_store_target_binding(
    publication,
    store_target_alias().name,
    100,
  ).unwrap()
  assert_eq(
    resolved_store_target(selected),
    ("connector://storage/archive", "mapping:fixture.archive.v1"),
  )
  assert_true(
    physical_equal(
      store_target_publication_environment(publication),
      @check.checking_environment_wire(environment),
    ),
  )
  let command = @environment.store_command_target(
    resolved_store_target_command(selected).unwrap(),
  )
  assert_eq(
    @environment.command_target_id(command),
    "command:fixture.upload.v1",
  )
  assert_eq(
    resolved_store_target_identity(selected),
    (
      @check.checking_environment_cid(environment),
      "sha256:8cb37a084de7d9c2092baffabb3ab29a8663aad8ad9a4b9d806e15fd98e77295",
      store_target_alias().installation_binding_cid,
      store_target_alias().installation_owner_cid,
    ),
  )
  // Actual source-context caller admits the complete section. No Source I/O,
  // Reference issuance or Effect execution occurs at this metadata boundary.
  assert_true(
    @source_publication.bind_published_query_context(environment, wire, None)
    is Ok(_),
  )
}

///|
test "Host STORE publication preserves canonical relation-store and ambiguity" {
  let environment = store_source_environment("relation")
  let publication = @source_publication.published_store_targets(
      environment,
      store_source_publication(environment),
    )
    .unwrap()
    .unwrap()
  let selected = resolve_store_target_binding(
    publication,
    store_target_alias().name,
    100,
  ).unwrap()
  assert_true(resolved_store_target_command(selected) is None)
  let environment = store_source_environment("ambiguous")
  let publication = @source_publication.published_store_targets(
      environment,
      store_source_publication(environment),
    )
    .unwrap()
    .unwrap()
  assert_eq(
    resolve_store_target_binding(publication, store_target_alias().name, 100).unwrap_err(),
    AmbiguousMapping,
  )
}

///|
test "Host STORE publication refuses malformed and foreign section before context" {
  let environment = store_source_environment("object")
  let wire = store_source_publication(environment)
  let name = "\"storage.archive\""
  for
    changed in [
      wire.replace(old="\"storeTargets\":[", new="\"unknownTargets\":["),
      wire.replace(old=name, new="null"),
      wire.replace(old=name, new="\"bad..path\""),
      wire.replace(old="\"targetRef\":", new="\"unknown\":true,\"targetRef\":"),
      wire.replace(
        old=store_target_alias().installation_binding_cid,
        new="not-a-cid",
      ),
      wire.replace(
        old=store_target_alias().installation_owner_cid,
        new="not-a-cid",
      ),
      wire.replace(
        old=@check.checking_environment_cid(environment),
        new="sha256:" + "a".repeat(64),
      ),
    ] {
    assert_true(
      @source_publication.published_store_targets(environment, changed)
      is Err(_),
    )
    assert_true(
      @source_publication.bind_published_query_context(
        environment,
        changed,
        None,
      )
      is Err(_),
    )
  }
  let prefix = "{\"environmentCid\":\"" +
    @check.checking_environment_cid(environment) +
    "\",\"aliases\":[],\"storeTargets\":"
  for section in ["null", "{}", "[null]", "[{}]"] {
    let changed = prefix + section + "}"
    assert_true(
      @source_publication.published_store_targets(environment, changed)
      is Err(_),
    )
    assert_true(
      @source_publication.bind_published_query_context(
        environment,
        changed,
        None,
      )
      is Err(_),
    )
  }
}

///|
test "Host STORE publication cannot hide invalid Command behind a read context" {
  let environment = store_source_environment("foreignCatalog")
  let wire = store_source_publication(environment)
  assert_true(
    @source_publication.published_store_targets(environment, wire) is Err(_),
  )
  assert_true(
    @source_publication.bind_published_query_context(environment, wire, None)
    is Err(_),
  )
}

///|
test "absent or empty Host STORE publication preserves old original inputs" {
  let environment = store_source_environment("foreignCatalog")
  let prefix = "{\"environmentCid\":\"" +
    @check.checking_environment_cid(environment) +
    "\",\"aliases\":[]"
  for wire in [prefix + "}", prefix + ",\"storeTargets\":[]}"] {
    assert_true(
      @source_publication.published_store_targets(environment, wire).unwrap()
      is None,
    )
    assert_true(
      @source_publication.published_update_targets(environment, wire).unwrap()
      is None,
    )
    assert_true(
      @source_publication.bind_published_query_context(environment, wire, None)
      is Ok(_),
    )
  }
}

///|
test "Host STORE collection retains create none without inventing a row identity" {
  let environment = store_source_environment("collection")
  let wire = store_source_publication(environment)
  let publication = @source_publication.published_store_targets(
      environment, wire,
    )
    .unwrap()
    .unwrap()
  let selected = resolve_store_target_binding(
    publication,
    store_target_alias().name,
    100,
  ).unwrap()
  let mapping = resolved_store_target_mapping(selected)
  assert_true(@environment.mapping_shape_primary_identity(mapping) is None)
  assert_eq(
    @environment.mapping_supports_operation(mapping, "create", "none", 100).unwrap().0,
    true,
  )
  assert_eq(
    @environment.mapping_supports_operation(mapping, "store", "none", 100).unwrap().0,
    false,
  )
  assert_true(resolved_store_target_command(selected) is Some(_))
  assert_true(
    @source_publication.bind_published_query_context(environment, wire, None)
    is Ok(_),
  )
  let unselected = store_source_environment("collectionWithoutCommand")
  let publication = @source_publication.published_store_targets(
      unselected,
      store_source_publication(unselected),
    )
    .unwrap()
    .unwrap()
  assert_eq(
    resolve_store_target_binding(publication, store_target_alias().name, 100).unwrap_err(),
    UnresolvedMapping,
  )
  let foreign = store_source_environment("collectionForeignCatalog")
  assert_true(
    @source_publication.published_store_targets(
      foreign,
      store_source_publication(foreign),
    )
    is Err(_),
  )
}
