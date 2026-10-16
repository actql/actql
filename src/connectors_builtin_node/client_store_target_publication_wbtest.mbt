///|
// Actual public Node bridge caller, with independent complete Source/catalog
// preimages. This validates metadata only: no issuer, Run, Source or Provider.
fn store_public_bridge_fixture(
  kind : String,
) -> @program_check.CheckEnvironment {
  let (wire, expected) = match kind {
    "collection" =>
      (
        (
          #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:a937153e39e2f69f5d6893275d3b6a7457498cc22627a1152627d473897f8757","commands":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"evidence_bundle_cid":"sha256:7f95bc33d267e6ed3009a7a920c1cd7adc2f08736456b60e45068812bf4f0cb6","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:7d2514050811313eeb33ef05a6a694c0dfb5bbfd6cf1347a072853b6320b459a","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"create","permissions":["scope:write"],"selector_class":"none","write_fields":["content","path"]}],"primary_identity":null,"required_fields":["content","path"],"required_permissions":[],"resource_identity_cid":"sha256:e3d4f3b2c3b392c4c889b78ea6b4794bc6a715d39a740275ab3c936d20ec6759","row_mapping":{"content":{"field":"content","null_behavior":"reject"},"path":{"field":"path","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:a937153e39e2f69f5d6893275d3b6a7457498cc22627a1152627d473897f8757","command_contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","command_ref":"command:fixture.upload.v1"},"target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:793f546b62fd8f3db0862d0369fc5451de8cee5fce0bd2408d7749efc6c3c336","version":"fixture-1","writable_fields":["content","path"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
        "sha256:7f95bc33d267e6ed3009a7a920c1cd7adc2f08736456b60e45068812bf4f0cb6",
      )
    "collectionForeignCatalog" =>
      (
        (
          #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"fixture-1"}],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:a937153e39e2f69f5d6893275d3b6a7457498cc22627a1152627d473897f8757","commands":[{"atomicity":"single_target","command_id":"command:fixture.upload.v1","connector_id":"storage","contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}}},"input_schema":{"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","version":"fixture-1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","version":"fixture-1"},"permissions":["scope:write"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"fixture-1"}],"connector_id":"storage","connector_version":"fixture-1","contracts":[{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"fixture","connector_id":"storage","connector_version":"fixture-1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:0146ce90a7071e37336a39b05f68d2f1505847a80a6f37731140fbb60ae54312","id":"fixture.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"fixture-1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:7412c07a4deb13f8d3dbe75a93ae44e657f2c9728d99cff3c90c0f65555f52dc","id":"fixture.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"fixture-1"}],"evidence_bundle_cid":"sha256:a62efc3aa9a23d4355f511b1e819f1bd549e475734990d4b84a28347bc407067","host_policy_profile":{},"mapping_contracts":[{"connector_manifest_cid":"sha256:6960590acec3fcbd045e40dbb94ec08f77c3a2d271943b019a8ada57283a3208","conversions":[],"mapping_contract_cid":"sha256:ee7b2d448c4cf51acb038f24bf3ce37721b8e89e84f098dd1925e1d99f602e70","mapping_ref":"mapping:fixture.archive.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"create","permissions":["scope:write"],"selector_class":"none","write_fields":["content","path"]}],"primary_identity":null,"required_fields":["content","path"],"required_permissions":[],"resource_identity_cid":"sha256:e3d4f3b2c3b392c4c889b78ea6b4794bc6a715d39a740275ab3c936d20ec6759","row_mapping":{"content":{"field":"content","null_behavior":"reject"},"path":{"field":"path","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","command_contract_cid":"sha256:cc127c70d073273d011fbb36068fb8b45e77cab31fa5d0737553bccb9978b0f2","command_ref":"command:fixture.upload.v1"},"target_ref":"connector://storage/archive","target_schema":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"path":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:793f546b62fd8f3db0862d0369fc5451de8cee5fce0bd2408d7749efc6c3c336","version":"fixture-1","writable_fields":["content","path"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
        ),
        "sha256:a62efc3aa9a23d4355f511b1e819f1bd549e475734990d4b84a28347bc407067",
      )
    _ => abort("unknown original STORE bridge preimage")
  }
  client_program_check_environment(
    wire, expected, false, false, true, false, false, false, false,
  ).unwrap()
}

///|
fn store_public_bridge_publication(
  environment : @program_check.CheckEnvironment,
) -> String {
  "{\"environmentCid\":\"" +
  client_program_checking_environment_cid(environment) +
  "\",\"aliases\":[],\"storeTargets\":[{\"name\":\"storage.archive\",\"targetRef\":\"connector://storage/archive\",\"installationBindingCid\":\"sha256:" +
  "d".repeat(64) +
  "\",\"installationOwnerCid\":\"sha256:" +
  "e".repeat(64) +
  "\"}]}"
}

///|
test "actual public Source publication bridge admits the original STORE pair and refuses substitution" {
  let environment = store_public_bridge_fixture("collection")
  let publication = store_public_bridge_publication(environment)
  assert_true(client_program_source_publication_valid(environment, publication))
  for
    invalid in [
      publication.replace(old="installationOwnerCid", new="unknownOwnerCid"),
      publication.replace(
        old="\"name\":\"storage.archive\"",
        new="\"name\":null",
      ),
      publication.replace(
        old=client_program_checking_environment_cid(environment),
        new="sha256:" + "a".repeat(64),
      ),
    ] {
    assert_true(!client_program_source_publication_valid(environment, invalid))
  }
  let foreign = store_public_bridge_fixture("collectionForeignCatalog")
  assert_true(
    !client_program_source_publication_valid(
      foreign,
      store_public_bridge_publication(foreign),
    ),
  )
  let empty = "{\"environmentCid\":\"" +
    client_program_checking_environment_cid(foreign) +
    "\",\"aliases\":[],\"storeTargets\":[]}"
  assert_true(client_program_source_publication_valid(foreign, empty))
}
