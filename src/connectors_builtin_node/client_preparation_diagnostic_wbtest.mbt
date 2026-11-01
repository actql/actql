///|
// Pure DATA inputs reconstructed from the original GCS source-qualified helpers.
// They do not issue a Site, credential, acquisition ticket or execution grant.
// The independent 3 * 2 * 8192 bound is 49152, even for an empty path list.
fn original_lookup_diagnostic_environment(
  one_short : Bool,
) -> @program_check.CheckEnvironment {
  let wire = if one_short {
    (
      #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:storage.gcs.upload.v1","connector_id":"storage","contract_cid":"sha256:12cf80a8a0de63135f0382629d3b1a7d2d3c2c0186d24d68a238944d16be381a","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]},"input_schema":{"cid":"sha256:83320f0478645615e5948872ab7de62819976ddc05269566689700b66245ffb1","id":"storage.gcs.upload.command_input","version":"gcs/0.1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:a170e24a2ebd424c14974863509a6cc9080bd035ea146f29630c75dbe738c1eb","id":"storage.gcs.upload.command_output","version":"gcs/0.1"},"permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"gcs/0.1"}],"connector_capabilities":[{"capability_contract_cids":["sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b"],"read_mode":"snapshot","source_contract_cid":"sha256:1a2a0f8289b220100afd257ce54bfe2265cacf53b585a3df495cd27ea8f4e729","source_ref":"connector://storage/objects#records","source_view_contract_cid":"sha256:1a2a0f8289b220100afd257ce54bfe2265cacf53b585a3df495cd27ea8f4e729"},{"capability_contract_cids":["sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b"],"read_mode":"snapshot","source_contract_cid":"sha256:e575e81ce66ae4c702f243e795d6c8da0d6ea33d9392b8b3a2c9c0a4bcfeabc6","source_ref":"connector://storage/files#records","source_view_contract_cid":"sha256:e575e81ce66ae4c702f243e795d6c8da0d6ea33d9392b8b3a2c9c0a4bcfeabc6"},{"capability_contract_cids":["sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b"],"read_mode":"snapshot","source_contract_cid":"sha256:2a77f55260157432e03baefd0fa9e6fb067fd23090b211d2863092dba9d0c907","source_ref":"connector://storage/contents#records","source_view_contract_cid":"sha256:2a77f55260157432e03baefd0fa9e6fb067fd23090b211d2863092dba9d0c907"}],"connector_catalogs":[{"catalog_cid":"sha256:df1f5ff8db6189a69a074d40beca4c9288772d5695ea67b7d7726008cbfcb833","commands":[{"atomicity":"single_target","command_id":"command:storage.gcs.upload.v1","connector_id":"storage","contract_cid":"sha256:12cf80a8a0de63135f0382629d3b1a7d2d3c2c0186d24d68a238944d16be381a","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]},"input_schema":{"cid":"sha256:83320f0478645615e5948872ab7de62819976ddc05269566689700b66245ffb1","id":"storage.gcs.upload.command_input","version":"gcs/0.1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:a170e24a2ebd424c14974863509a6cc9080bd035ea146f29630c75dbe738c1eb","id":"storage.gcs.upload.command_output","version":"gcs/0.1"},"permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"gcs/0.1"}],"connector_id":"storage","connector_version":"gcs/0.1","contracts":[{"body":{"classification":"unknown","source_ref":"connector://storage/objects#records","version":"actql-source-data-policy/0.1"},"cid":"sha256:013046a42a3e212133f350370c53aa5b1573bab424a923d620eee19bd0166cfd","id":"storage/objects/records/policy","kind":"data_policy","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"classification":"unknown","source_ref":"connector://storage/files#records","version":"actql-source-data-policy/0.1"},"cid":"sha256:16818319785133cb0b77cbfe272edee2bf67fcd1c75d2ef90047ca995bb7bb8b","id":"storage/files/records/policy","kind":"data_policy","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"fields":{"content":{"media_type":"application/pdf","nullable":false,"type":"content_ref"},"media_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}},"version":"actql-relation-schema/0.1"},"cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","id":"storage/contents/records/row","kind":"carrier_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"carrier":"relation","operations":["projection"],"version":"actql-source-view-pushdown/0.1"},"cid":"sha256:6177a5ef6d98eb891bcd679eb394ffe0013652f93d95bd43544877c2f4981a3d","id":"storage/contents/records/pushdown","kind":"pushdown","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"classification":"unknown","source_ref":"connector://storage/contents#records","version":"actql-source-data-policy/0.1"},"cid":"sha256:63d9404d82bbbcce6ffcfd260256a18e31271e0e48d8699fa57e802250b8a673","id":"storage/contents/records/policy","kind":"data_policy","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"fields":{"media_type":{"nullable":true,"type":"string"},"modified_at":{"nullable":true,"type":"timestamp"},"name":{"nullable":false,"type":"string"},"path":{"nullable":true,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"size_bytes":{"nullable":true,"type":"number"},"version":{"nullable":false,"type":"string"}},"version":"actql-relation-schema/0.1"},"cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","id":"storage/files/records/row","kind":"carrier_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{},"cid":"sha256:757a76824fe568e1dd623edb46abd529124bd9a3b6243f7fdc9e37e2acc4582b","id":"storage/objects/records/facts","kind":"carrier_facts","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"file_listing":{"admitted_scope_contract_cid":"sha256:98a7bde0250e1452871939138a72dff1f55194711e8d82b24ce428941645585b","allow_unfiltered_listing":true,"kind":"file_listing","listing_schema_contract_cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","max_examined_items":9,"max_listing_bytes":32768,"max_listing_duration_ms":10000,"max_listing_items":3,"max_listing_pages":4,"max_request_attempts":4,"maximum_path_length":1024,"selectable":["paths","glob"],"version":"actql-file-list/0.1","version_capability":{"contract_cid":"sha256:8937bda765bd83a97122a5e4d87d7db4f12e03393f639ef7f0a236759ed41cdb","required_nonnull":true}}},"cid":"sha256:82ce787374fbc4c117ce83c8c31cf9d2d9c733671a5b4a2cb71416bfbd778a41","id":"storage/files/records/facts","kind":"carrier_facts","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]},"cid":"sha256:83320f0478645615e5948872ab7de62819976ddc05269566689700b66245ffb1","id":"storage.gcs.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:a170e24a2ebd424c14974863509a6cc9080bd035ea146f29630c75dbe738c1eb","id":"storage.gcs.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"carrier":"relation","operations":["projection"],"version":"actql-source-view-pushdown/0.1"},"cid":"sha256:ad715d264c75fc1d2d465fea3fd5f04cc2f2c37f9148ff91f057c8c2e542e1a2","id":"storage/files/records/pushdown","kind":"pushdown","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"prefix":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:ba2c0036f869b0c2a3979f0f2262fa65f141f1d85b3b1b28b2ba288968419e34","id":"storage/objects/records/request","kind":"request_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:cfb6b24f68244d09399c8c672ee12f141bfe2c36ba239e3f624eae09815f1d3c","id":"storage/contents/records/request","kind":"request_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"file_content":{"admitted_scope_contract_cid":"sha256:98a7bde0250e1452871939138a72dff1f55194711e8d82b24ce428941645585b","content_schema_contract_cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","kind":"file_content","representation":"exact_stored_bytes","version":"actql-file-content/0.1","version_capability":{"contract_cid":"sha256:8937bda765bd83a97122a5e4d87d7db4f12e03393f639ef7f0a236759ed41cdb","required_nonnull":true}},"lookup_capacity":{"completeness":"complete_per_requested_key","max_pages_per_request":2,"max_response_bytes_per_page":8192,"max_rows_per_key":1,"version":"actql-lookup-capacity/0.1"}},"cid":"sha256:d06775b1280931503ff11c1690b4e64e9574b4b5e1758d2a18f80741b9f6e0e8","id":"storage/contents/records/facts","kind":"carrier_facts","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"glob":{"nullable":true,"type":"string"},"paths":{"items":{"nullable":false,"type":"string"},"max_items":3,"nullable":true,"type":"array"}},"nullable":false,"type":"object"},"cid":"sha256:e2f75792e5b5f874b8dae1ae1758b96efe7ff6438015228a5938d04c51c2cde5","id":"storage/files/records/request","kind":"request_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"carrier":"relation","operations":["projection"],"version":"actql-source-view-pushdown/0.1"},"cid":"sha256:eb5bcafaf7eb7ca0f21c07bc9ca73aa714202c02fb8e221de91ed49551141d6c","id":"storage/objects/records/pushdown","kind":"pushdown","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"fields":{"content_type":{"nullable":true,"type":"string"},"crc32c":{"nullable":true,"type":"string"},"generation":{"nullable":false,"precision":19,"scale":0,"type":"decimal"},"md5":{"nullable":true,"type":"string"},"metadata":{"nullable":true,"type":"json"},"metageneration":{"nullable":false,"precision":19,"scale":0,"type":"decimal"},"name":{"nullable":false,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"size":{"nullable":false,"precision":19,"scale":0,"type":"decimal"},"storage_class":{"nullable":true,"type":"string"},"updated":{"nullable":true,"type":"timestamp"},"version":{"nullable":false,"type":"string"}},"version":"actql-relation-schema/0.1"},"cid":"sha256:fa16e17e789f4d7f878477b41af2b7944632c1eeeb3d1ac9918e14f57601ab93","id":"storage/objects/records/row","kind":"carrier_schema","schema":"actql.contract/0.1","version":"gcs/0.1"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:ba2c0036f869b0c2a3979f0f2262fa65f141f1d85b3b1b28b2ba288968419e34","id":"storage/objects/records/request","version":"gcs/0.1"}},"connector_id":"storage","connector_version":"gcs/0.1","contract_cid":"sha256:1a2a0f8289b220100afd257ce54bfe2265cacf53b585a3df495cd27ea8f4e729","output":{"carrier":"relation","data_policy":{"cid":"sha256:013046a42a3e212133f350370c53aa5b1573bab424a923d620eee19bd0166cfd","id":"storage/objects/records/policy","version":"gcs/0.1"},"facts":{"cid":"sha256:757a76824fe568e1dd623edb46abd529124bd9a3b6243f7fdc9e37e2acc4582b","id":"storage/objects/records/facts","version":"gcs/0.1"},"schema":{"cid":"sha256:fa16e17e789f4d7f878477b41af2b7944632c1eeeb3d1ac9918e14f57601ab93","id":"storage/objects/records/row","version":"gcs/0.1"}},"pushdown":{"contract":{"cid":"sha256:eb5bcafaf7eb7ca0f21c07bc9ca73aa714202c02fb8e221de91ed49551141d6c","id":"storage/objects/records/pushdown","version":"gcs/0.1"},"operations":["projection"]},"request_processing":{"mutates_business_state":false},"resource_kind":"file","schema":"actql.source_view/0.1","view_id":"records","view_version":"gcs/0.1"},{"acquisition":{"authority":"read_content","correlation":{"cardinality":"one","identity":["resource","version"],"request_fields":["resource","version"],"response_fields":["resource","version"]},"default_mode":"snapshot","kind":"fetch","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:cfb6b24f68244d09399c8c672ee12f141bfe2c36ba239e3f624eae09815f1d3c","id":"storage/contents/records/request","version":"gcs/0.1"}},"connector_id":"storage","connector_version":"gcs/0.1","contract_cid":"sha256:2a77f55260157432e03baefd0fa9e6fb067fd23090b211d2863092dba9d0c907","output":{"carrier":"relation","data_policy":{"cid":"sha256:63d9404d82bbbcce6ffcfd260256a18e31271e0e48d8699fa57e802250b8a673","id":"storage/contents/records/policy","version":"gcs/0.1"},"facts":{"cid":"sha256:d06775b1280931503ff11c1690b4e64e9574b4b5e1758d2a18f80741b9f6e0e8","id":"storage/contents/records/facts","version":"gcs/0.1"},"schema":{"cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","id":"storage/contents/records/row","version":"gcs/0.1"}},"pushdown":{"contract":{"cid":"sha256:6177a5ef6d98eb891bcd679eb394ffe0013652f93d95bd43544877c2f4981a3d","id":"storage/contents/records/pushdown","version":"gcs/0.1"},"operations":["projection"]},"request_processing":{"mutates_business_state":false},"resource_kind":"file","schema":"actql.source_view/0.1","view_id":"records","view_version":"gcs/0.1"},{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:e2f75792e5b5f874b8dae1ae1758b96efe7ff6438015228a5938d04c51c2cde5","id":"storage/files/records/request","version":"gcs/0.1"}},"connector_id":"storage","connector_version":"gcs/0.1","contract_cid":"sha256:e575e81ce66ae4c702f243e795d6c8da0d6ea33d9392b8b3a2c9c0a4bcfeabc6","output":{"carrier":"relation","data_policy":{"cid":"sha256:16818319785133cb0b77cbfe272edee2bf67fcd1c75d2ef90047ca995bb7bb8b","id":"storage/files/records/policy","version":"gcs/0.1"},"facts":{"cid":"sha256:82ce787374fbc4c117ce83c8c31cf9d2d9c733671a5b4a2cb71416bfbd778a41","id":"storage/files/records/facts","version":"gcs/0.1"},"schema":{"cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","id":"storage/files/records/row","version":"gcs/0.1"}},"pushdown":{"contract":{"cid":"sha256:ad715d264c75fc1d2d465fea3fd5f04cc2f2c37f9148ff91f057c8c2e542e1a2","id":"storage/files/records/pushdown","version":"gcs/0.1"},"operations":["projection"]},"request_processing":{"mutates_business_state":false},"resource_kind":"file","schema":"actql.source_view/0.1","view_id":"records","view_version":"gcs/0.1"}]}],"connector_manifest":{"connectors":[{"connector":"gcs","connector_id":"storage","connector_version":"gcs/0.1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"carrier":"relation","operations":["projection"],"version":"actql-source-view-pushdown/0.1"},"cid":"sha256:6177a5ef6d98eb891bcd679eb394ffe0013652f93d95bd43544877c2f4981a3d","id":"storage/contents/records/pushdown","kind":"pushdown","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"classification":"unknown","source_ref":"connector://storage/files#records","version":"actql-source-data-policy/0.1"},"cid":"sha256:16818319785133cb0b77cbfe272edee2bf67fcd1c75d2ef90047ca995bb7bb8b","id":"storage/files/records/policy","kind":"data_policy","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"fields":{"media_type":{"nullable":true,"type":"string"},"modified_at":{"nullable":true,"type":"timestamp"},"name":{"nullable":false,"type":"string"},"path":{"nullable":true,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"size_bytes":{"nullable":true,"type":"number"},"version":{"nullable":false,"type":"string"}},"version":"actql-relation-schema/0.1"},"cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","id":"storage/files/records/row","kind":"carrier_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]},"cid":"sha256:83320f0478645615e5948872ab7de62819976ddc05269566689700b66245ffb1","id":"storage.gcs.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"prefix":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:ba2c0036f869b0c2a3979f0f2262fa65f141f1d85b3b1b28b2ba288968419e34","id":"storage/objects/records/request","kind":"request_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"file_listing":{"admitted_scope_contract_cid":"sha256:98a7bde0250e1452871939138a72dff1f55194711e8d82b24ce428941645585b","allow_unfiltered_listing":true,"kind":"file_listing","listing_schema_contract_cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","max_examined_items":9,"max_listing_bytes":32768,"max_listing_duration_ms":10000,"max_listing_items":3,"max_listing_pages":4,"max_request_attempts":4,"maximum_path_length":1024,"selectable":["paths","glob"],"version":"actql-file-list/0.1","version_capability":{"contract_cid":"sha256:8937bda765bd83a97122a5e4d87d7db4f12e03393f639ef7f0a236759ed41cdb","required_nonnull":true}}},"cid":"sha256:82ce787374fbc4c117ce83c8c31cf9d2d9c733671a5b4a2cb71416bfbd778a41","id":"storage/files/records/facts","kind":"carrier_facts","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"glob":{"nullable":true,"type":"string"},"paths":{"items":{"nullable":false,"type":"string"},"max_items":3,"nullable":true,"type":"array"}},"nullable":false,"type":"object"},"cid":"sha256:e2f75792e5b5f874b8dae1ae1758b96efe7ff6438015228a5938d04c51c2cde5","id":"storage/files/records/request","kind":"request_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"fields":{"content":{"media_type":"application/pdf","nullable":false,"type":"content_ref"},"media_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}},"version":"actql-relation-schema/0.1"},"cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","id":"storage/contents/records/row","kind":"carrier_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{},"cid":"sha256:757a76824fe568e1dd623edb46abd529124bd9a3b6243f7fdc9e37e2acc4582b","id":"storage/objects/records/facts","kind":"carrier_facts","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"classification":"unknown","source_ref":"connector://storage/objects#records","version":"actql-source-data-policy/0.1"},"cid":"sha256:013046a42a3e212133f350370c53aa5b1573bab424a923d620eee19bd0166cfd","id":"storage/objects/records/policy","kind":"data_policy","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:cfb6b24f68244d09399c8c672ee12f141bfe2c36ba239e3f624eae09815f1d3c","id":"storage/contents/records/request","kind":"request_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"carrier":"relation","operations":["projection"],"version":"actql-source-view-pushdown/0.1"},"cid":"sha256:eb5bcafaf7eb7ca0f21c07bc9ca73aa714202c02fb8e221de91ed49551141d6c","id":"storage/objects/records/pushdown","kind":"pushdown","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"carrier":"relation","operations":["projection"],"version":"actql-source-view-pushdown/0.1"},"cid":"sha256:ad715d264c75fc1d2d465fea3fd5f04cc2f2c37f9148ff91f057c8c2e542e1a2","id":"storage/files/records/pushdown","kind":"pushdown","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"file_content":{"admitted_scope_contract_cid":"sha256:98a7bde0250e1452871939138a72dff1f55194711e8d82b24ce428941645585b","content_schema_contract_cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","kind":"file_content","representation":"exact_stored_bytes","version":"actql-file-content/0.1","version_capability":{"contract_cid":"sha256:8937bda765bd83a97122a5e4d87d7db4f12e03393f639ef7f0a236759ed41cdb","required_nonnull":true}},"lookup_capacity":{"completeness":"complete_per_requested_key","max_pages_per_request":2,"max_response_bytes_per_page":8192,"max_rows_per_key":1,"version":"actql-lookup-capacity/0.1"}},"cid":"sha256:d06775b1280931503ff11c1690b4e64e9574b4b5e1758d2a18f80741b9f6e0e8","id":"storage/contents/records/facts","kind":"carrier_facts","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"classification":"unknown","source_ref":"connector://storage/contents#records","version":"actql-source-data-policy/0.1"},"cid":"sha256:63d9404d82bbbcce6ffcfd260256a18e31271e0e48d8699fa57e802250b8a673","id":"storage/contents/records/policy","kind":"data_policy","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"fields":{"content_type":{"nullable":true,"type":"string"},"crc32c":{"nullable":true,"type":"string"},"generation":{"nullable":false,"precision":19,"scale":0,"type":"decimal"},"md5":{"nullable":true,"type":"string"},"metadata":{"nullable":true,"type":"json"},"metageneration":{"nullable":false,"precision":19,"scale":0,"type":"decimal"},"name":{"nullable":false,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"size":{"nullable":false,"precision":19,"scale":0,"type":"decimal"},"storage_class":{"nullable":true,"type":"string"},"updated":{"nullable":true,"type":"timestamp"},"version":{"nullable":false,"type":"string"}},"version":"actql-relation-schema/0.1"},"cid":"sha256:fa16e17e789f4d7f878477b41af2b7944632c1eeeb3d1ac9918e14f57601ab93","id":"storage/objects/records/row","kind":"carrier_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:a170e24a2ebd424c14974863509a6cc9080bd035ea146f29630c75dbe738c1eb","id":"storage.gcs.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"gcs/0.1"}],"evidence_bundle_cid":"sha256:def545900f2605594df31fb34632128600733595bad9c37df33353930d8e081e","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"lookup_execution":{"max_network_attempts_per_request":3,"max_request_bytes_per_attempt":4096,"max_total_decoded_response_bytes":49151,"max_total_duration_ms":30000,"max_total_request_bytes":73728,"max_total_response_bytes":49152,"version":"actql-lookup-execution-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:9ba0b550db52585a41dffe873c0a8fbc666e7db2745f28ec2f5d8b7669b3fcb1","conversions":[],"mapping_contract_cid":"sha256:dcc14b4cc20e99e657b7bafef7199ab801d7a07cc7e935cf8322878660076b2f","mapping_ref":"mapping:storage.gcs.objects.upload.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"create","permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"selector_class":"none","write_fields":["content","name"]},{"effect_kind":"create","permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"selector_class":"none","write_fields":["content","content_type","name"]},{"effect_kind":"create","permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"selector_class":"none","write_fields":["content","name","overwrite"]},{"effect_kind":"create","permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"selector_class":"none","write_fields":["content","content_type","name","overwrite"]}],"primary_identity":null,"required_fields":["content","name"],"required_permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"resource_identity_cid":"sha256:d456e25d1d2a07499d9db78c5ed926b321dc6150977c6b31cda0b07dbbe3eb7b","row_mapping":{"content":{"field":"content","null_behavior":"reject"},"content_type":{"field":"content_type","null_behavior":"reject"},"name":{"field":"name","null_behavior":"reject"},"overwrite":{"field":"overwrite","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:df1f5ff8db6189a69a074d40beca4c9288772d5695ea67b7d7726008cbfcb833","command_contract_cid":"sha256:12cf80a8a0de63135f0382629d3b1a7d2d3c2c0186d24d68a238944d16be381a","command_ref":"command:storage.gcs.upload.v1"},"target_ref":"connector://storage/objects","target_schema":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:3420afa3b6d4a946a3858dde773d70f9ffd4491f083775b06009637a8d2bcf08","version":"gcs/0.1","writable_fields":["content","content_type","name","overwrite"]}],"model_task_contracts":[],"schema_snapshots":[{"carrier_schema_contract_cid":"sha256:fa16e17e789f4d7f878477b41af2b7944632c1eeeb3d1ac9918e14f57601ab93","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:1a2a0f8289b220100afd257ce54bfe2265cacf53b585a3df495cd27ea8f4e729","source_data_policy_cid":"sha256:013046a42a3e212133f350370c53aa5b1573bab424a923d620eee19bd0166cfd","source_ref":"connector://storage/objects#records","source_view_contract_cid":"sha256:1a2a0f8289b220100afd257ce54bfe2265cacf53b585a3df495cd27ea8f4e729"},{"carrier_schema_contract_cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:2a77f55260157432e03baefd0fa9e6fb067fd23090b211d2863092dba9d0c907","source_data_policy_cid":"sha256:63d9404d82bbbcce6ffcfd260256a18e31271e0e48d8699fa57e802250b8a673","source_ref":"connector://storage/contents#records","source_view_contract_cid":"sha256:2a77f55260157432e03baefd0fa9e6fb067fd23090b211d2863092dba9d0c907"},{"carrier_schema_contract_cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:e575e81ce66ae4c702f243e795d6c8da0d6ea33d9392b8b3a2c9c0a4bcfeabc6","source_data_policy_cid":"sha256:16818319785133cb0b77cbfe272edee2bf67fcd1c75d2ef90047ca995bb7bb8b","source_ref":"connector://storage/files#records","source_view_contract_cid":"sha256:e575e81ce66ae4c702f243e795d6c8da0d6ea33d9392b8b3a2c9c0a4bcfeabc6"}],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:e2f75792e5b5f874b8dae1ae1758b96efe7ff6438015228a5938d04c51c2cde5","id":"storage/files/records/request","version":"gcs/0.1"}},"connector_id":"storage","connector_version":"gcs/0.1","contract_cid":"sha256:e575e81ce66ae4c702f243e795d6c8da0d6ea33d9392b8b3a2c9c0a4bcfeabc6","output":{"carrier":"relation","data_policy":{"cid":"sha256:16818319785133cb0b77cbfe272edee2bf67fcd1c75d2ef90047ca995bb7bb8b","id":"storage/files/records/policy","version":"gcs/0.1"},"facts":{"cid":"sha256:82ce787374fbc4c117ce83c8c31cf9d2d9c733671a5b4a2cb71416bfbd778a41","id":"storage/files/records/facts","version":"gcs/0.1"},"schema":{"cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","id":"storage/files/records/row","version":"gcs/0.1"}},"pushdown":{"contract":{"cid":"sha256:ad715d264c75fc1d2d465fea3fd5f04cc2f2c37f9148ff91f057c8c2e542e1a2","id":"storage/files/records/pushdown","version":"gcs/0.1"},"operations":["projection"]},"request_processing":{"mutates_business_state":false},"resource_kind":"file","schema":"actql.source_view/0.1","view_id":"records","view_version":"gcs/0.1"},{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:ba2c0036f869b0c2a3979f0f2262fa65f141f1d85b3b1b28b2ba288968419e34","id":"storage/objects/records/request","version":"gcs/0.1"}},"connector_id":"storage","connector_version":"gcs/0.1","contract_cid":"sha256:1a2a0f8289b220100afd257ce54bfe2265cacf53b585a3df495cd27ea8f4e729","output":{"carrier":"relation","data_policy":{"cid":"sha256:013046a42a3e212133f350370c53aa5b1573bab424a923d620eee19bd0166cfd","id":"storage/objects/records/policy","version":"gcs/0.1"},"facts":{"cid":"sha256:757a76824fe568e1dd623edb46abd529124bd9a3b6243f7fdc9e37e2acc4582b","id":"storage/objects/records/facts","version":"gcs/0.1"},"schema":{"cid":"sha256:fa16e17e789f4d7f878477b41af2b7944632c1eeeb3d1ac9918e14f57601ab93","id":"storage/objects/records/row","version":"gcs/0.1"}},"pushdown":{"contract":{"cid":"sha256:eb5bcafaf7eb7ca0f21c07bc9ca73aa714202c02fb8e221de91ed49551141d6c","id":"storage/objects/records/pushdown","version":"gcs/0.1"},"operations":["projection"]},"request_processing":{"mutates_business_state":false},"resource_kind":"file","schema":"actql.source_view/0.1","view_id":"records","view_version":"gcs/0.1"},{"acquisition":{"authority":"read_content","correlation":{"cardinality":"one","identity":["resource","version"],"request_fields":["resource","version"],"response_fields":["resource","version"]},"default_mode":"snapshot","kind":"fetch","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:cfb6b24f68244d09399c8c672ee12f141bfe2c36ba239e3f624eae09815f1d3c","id":"storage/contents/records/request","version":"gcs/0.1"}},"connector_id":"storage","connector_version":"gcs/0.1","contract_cid":"sha256:2a77f55260157432e03baefd0fa9e6fb067fd23090b211d2863092dba9d0c907","output":{"carrier":"relation","data_policy":{"cid":"sha256:63d9404d82bbbcce6ffcfd260256a18e31271e0e48d8699fa57e802250b8a673","id":"storage/contents/records/policy","version":"gcs/0.1"},"facts":{"cid":"sha256:d06775b1280931503ff11c1690b4e64e9574b4b5e1758d2a18f80741b9f6e0e8","id":"storage/contents/records/facts","version":"gcs/0.1"},"schema":{"cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","id":"storage/contents/records/row","version":"gcs/0.1"}},"pushdown":{"contract":{"cid":"sha256:6177a5ef6d98eb891bcd679eb394ffe0013652f93d95bd43544877c2f4981a3d","id":"storage/contents/records/pushdown","version":"gcs/0.1"},"operations":["projection"]},"request_processing":{"mutates_business_state":false},"resource_kind":"file","schema":"actql.source_view/0.1","view_id":"records","view_version":"gcs/0.1"}],"version":"actql-check-environment/0.1"}
    )
  } else {
    (
      #|{"command_contracts":[{"atomicity":"single_target","command_id":"command:storage.gcs.upload.v1","connector_id":"storage","contract_cid":"sha256:12cf80a8a0de63135f0382629d3b1a7d2d3c2c0186d24d68a238944d16be381a","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]},"input_schema":{"cid":"sha256:83320f0478645615e5948872ab7de62819976ddc05269566689700b66245ffb1","id":"storage.gcs.upload.command_input","version":"gcs/0.1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:a170e24a2ebd424c14974863509a6cc9080bd035ea146f29630c75dbe738c1eb","id":"storage.gcs.upload.command_output","version":"gcs/0.1"},"permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"gcs/0.1"}],"connector_capabilities":[{"capability_contract_cids":["sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b"],"read_mode":"snapshot","source_contract_cid":"sha256:1a2a0f8289b220100afd257ce54bfe2265cacf53b585a3df495cd27ea8f4e729","source_ref":"connector://storage/objects#records","source_view_contract_cid":"sha256:1a2a0f8289b220100afd257ce54bfe2265cacf53b585a3df495cd27ea8f4e729"},{"capability_contract_cids":["sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b"],"read_mode":"snapshot","source_contract_cid":"sha256:e575e81ce66ae4c702f243e795d6c8da0d6ea33d9392b8b3a2c9c0a4bcfeabc6","source_ref":"connector://storage/files#records","source_view_contract_cid":"sha256:e575e81ce66ae4c702f243e795d6c8da0d6ea33d9392b8b3a2c9c0a4bcfeabc6"},{"capability_contract_cids":["sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b"],"read_mode":"snapshot","source_contract_cid":"sha256:2a77f55260157432e03baefd0fa9e6fb067fd23090b211d2863092dba9d0c907","source_ref":"connector://storage/contents#records","source_view_contract_cid":"sha256:2a77f55260157432e03baefd0fa9e6fb067fd23090b211d2863092dba9d0c907"}],"connector_catalogs":[{"catalog_cid":"sha256:df1f5ff8db6189a69a074d40beca4c9288772d5695ea67b7d7726008cbfcb833","commands":[{"atomicity":"single_target","command_id":"command:storage.gcs.upload.v1","connector_id":"storage","contract_cid":"sha256:12cf80a8a0de63135f0382629d3b1a7d2d3c2c0186d24d68a238944d16be381a","idempotency":{"support":"unsupported"},"input_contract":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]},"input_schema":{"cid":"sha256:83320f0478645615e5948872ab7de62819976ddc05269566689700b66245ffb1","id":"storage.gcs.upload.command_input","version":"gcs/0.1"},"minimum_approval":"required","outcome":"synchronous","output_schema":{"cid":"sha256:a170e24a2ebd424c14974863509a6cc9080bd035ea146f29630c75dbe738c1eb","id":"storage.gcs.upload.command_output","version":"gcs/0.1"},"permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"preview":{"strength":"exact"},"reversibility":"unknown","schema":"actql.command_contract/0.1","target":{"cardinality":"single","resource_kind":"file_collection"},"version":"gcs/0.1"}],"connector_id":"storage","connector_version":"gcs/0.1","contracts":[{"body":{"classification":"unknown","source_ref":"connector://storage/objects#records","version":"actql-source-data-policy/0.1"},"cid":"sha256:013046a42a3e212133f350370c53aa5b1573bab424a923d620eee19bd0166cfd","id":"storage/objects/records/policy","kind":"data_policy","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"classification":"unknown","source_ref":"connector://storage/files#records","version":"actql-source-data-policy/0.1"},"cid":"sha256:16818319785133cb0b77cbfe272edee2bf67fcd1c75d2ef90047ca995bb7bb8b","id":"storage/files/records/policy","kind":"data_policy","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"fields":{"content":{"media_type":"application/pdf","nullable":false,"type":"content_ref"},"media_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}},"version":"actql-relation-schema/0.1"},"cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","id":"storage/contents/records/row","kind":"carrier_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"carrier":"relation","operations":["projection"],"version":"actql-source-view-pushdown/0.1"},"cid":"sha256:6177a5ef6d98eb891bcd679eb394ffe0013652f93d95bd43544877c2f4981a3d","id":"storage/contents/records/pushdown","kind":"pushdown","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"classification":"unknown","source_ref":"connector://storage/contents#records","version":"actql-source-data-policy/0.1"},"cid":"sha256:63d9404d82bbbcce6ffcfd260256a18e31271e0e48d8699fa57e802250b8a673","id":"storage/contents/records/policy","kind":"data_policy","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"fields":{"media_type":{"nullable":true,"type":"string"},"modified_at":{"nullable":true,"type":"timestamp"},"name":{"nullable":false,"type":"string"},"path":{"nullable":true,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"size_bytes":{"nullable":true,"type":"number"},"version":{"nullable":false,"type":"string"}},"version":"actql-relation-schema/0.1"},"cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","id":"storage/files/records/row","kind":"carrier_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{},"cid":"sha256:757a76824fe568e1dd623edb46abd529124bd9a3b6243f7fdc9e37e2acc4582b","id":"storage/objects/records/facts","kind":"carrier_facts","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"file_listing":{"admitted_scope_contract_cid":"sha256:98a7bde0250e1452871939138a72dff1f55194711e8d82b24ce428941645585b","allow_unfiltered_listing":true,"kind":"file_listing","listing_schema_contract_cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","max_examined_items":9,"max_listing_bytes":32768,"max_listing_duration_ms":10000,"max_listing_items":3,"max_listing_pages":4,"max_request_attempts":4,"maximum_path_length":1024,"selectable":["paths","glob"],"version":"actql-file-list/0.1","version_capability":{"contract_cid":"sha256:8937bda765bd83a97122a5e4d87d7db4f12e03393f639ef7f0a236759ed41cdb","required_nonnull":true}}},"cid":"sha256:82ce787374fbc4c117ce83c8c31cf9d2d9c733671a5b4a2cb71416bfbd778a41","id":"storage/files/records/facts","kind":"carrier_facts","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]},"cid":"sha256:83320f0478645615e5948872ab7de62819976ddc05269566689700b66245ffb1","id":"storage.gcs.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:a170e24a2ebd424c14974863509a6cc9080bd035ea146f29630c75dbe738c1eb","id":"storage.gcs.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"carrier":"relation","operations":["projection"],"version":"actql-source-view-pushdown/0.1"},"cid":"sha256:ad715d264c75fc1d2d465fea3fd5f04cc2f2c37f9148ff91f057c8c2e542e1a2","id":"storage/files/records/pushdown","kind":"pushdown","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"prefix":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:ba2c0036f869b0c2a3979f0f2262fa65f141f1d85b3b1b28b2ba288968419e34","id":"storage/objects/records/request","kind":"request_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:cfb6b24f68244d09399c8c672ee12f141bfe2c36ba239e3f624eae09815f1d3c","id":"storage/contents/records/request","kind":"request_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"file_content":{"admitted_scope_contract_cid":"sha256:98a7bde0250e1452871939138a72dff1f55194711e8d82b24ce428941645585b","content_schema_contract_cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","kind":"file_content","representation":"exact_stored_bytes","version":"actql-file-content/0.1","version_capability":{"contract_cid":"sha256:8937bda765bd83a97122a5e4d87d7db4f12e03393f639ef7f0a236759ed41cdb","required_nonnull":true}},"lookup_capacity":{"completeness":"complete_per_requested_key","max_pages_per_request":2,"max_response_bytes_per_page":8192,"max_rows_per_key":1,"version":"actql-lookup-capacity/0.1"}},"cid":"sha256:d06775b1280931503ff11c1690b4e64e9574b4b5e1758d2a18f80741b9f6e0e8","id":"storage/contents/records/facts","kind":"carrier_facts","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"glob":{"nullable":true,"type":"string"},"paths":{"items":{"nullable":false,"type":"string"},"max_items":3,"nullable":true,"type":"array"}},"nullable":false,"type":"object"},"cid":"sha256:e2f75792e5b5f874b8dae1ae1758b96efe7ff6438015228a5938d04c51c2cde5","id":"storage/files/records/request","kind":"request_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"carrier":"relation","operations":["projection"],"version":"actql-source-view-pushdown/0.1"},"cid":"sha256:eb5bcafaf7eb7ca0f21c07bc9ca73aa714202c02fb8e221de91ed49551141d6c","id":"storage/objects/records/pushdown","kind":"pushdown","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"fields":{"content_type":{"nullable":true,"type":"string"},"crc32c":{"nullable":true,"type":"string"},"generation":{"nullable":false,"precision":19,"scale":0,"type":"decimal"},"md5":{"nullable":true,"type":"string"},"metadata":{"nullable":true,"type":"json"},"metageneration":{"nullable":false,"precision":19,"scale":0,"type":"decimal"},"name":{"nullable":false,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"size":{"nullable":false,"precision":19,"scale":0,"type":"decimal"},"storage_class":{"nullable":true,"type":"string"},"updated":{"nullable":true,"type":"timestamp"},"version":{"nullable":false,"type":"string"}},"version":"actql-relation-schema/0.1"},"cid":"sha256:fa16e17e789f4d7f878477b41af2b7944632c1eeeb3d1ac9918e14f57601ab93","id":"storage/objects/records/row","kind":"carrier_schema","schema":"actql.contract/0.1","version":"gcs/0.1"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:ba2c0036f869b0c2a3979f0f2262fa65f141f1d85b3b1b28b2ba288968419e34","id":"storage/objects/records/request","version":"gcs/0.1"}},"connector_id":"storage","connector_version":"gcs/0.1","contract_cid":"sha256:1a2a0f8289b220100afd257ce54bfe2265cacf53b585a3df495cd27ea8f4e729","output":{"carrier":"relation","data_policy":{"cid":"sha256:013046a42a3e212133f350370c53aa5b1573bab424a923d620eee19bd0166cfd","id":"storage/objects/records/policy","version":"gcs/0.1"},"facts":{"cid":"sha256:757a76824fe568e1dd623edb46abd529124bd9a3b6243f7fdc9e37e2acc4582b","id":"storage/objects/records/facts","version":"gcs/0.1"},"schema":{"cid":"sha256:fa16e17e789f4d7f878477b41af2b7944632c1eeeb3d1ac9918e14f57601ab93","id":"storage/objects/records/row","version":"gcs/0.1"}},"pushdown":{"contract":{"cid":"sha256:eb5bcafaf7eb7ca0f21c07bc9ca73aa714202c02fb8e221de91ed49551141d6c","id":"storage/objects/records/pushdown","version":"gcs/0.1"},"operations":["projection"]},"request_processing":{"mutates_business_state":false},"resource_kind":"file","schema":"actql.source_view/0.1","view_id":"records","view_version":"gcs/0.1"},{"acquisition":{"authority":"read_content","correlation":{"cardinality":"one","identity":["resource","version"],"request_fields":["resource","version"],"response_fields":["resource","version"]},"default_mode":"snapshot","kind":"fetch","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:cfb6b24f68244d09399c8c672ee12f141bfe2c36ba239e3f624eae09815f1d3c","id":"storage/contents/records/request","version":"gcs/0.1"}},"connector_id":"storage","connector_version":"gcs/0.1","contract_cid":"sha256:2a77f55260157432e03baefd0fa9e6fb067fd23090b211d2863092dba9d0c907","output":{"carrier":"relation","data_policy":{"cid":"sha256:63d9404d82bbbcce6ffcfd260256a18e31271e0e48d8699fa57e802250b8a673","id":"storage/contents/records/policy","version":"gcs/0.1"},"facts":{"cid":"sha256:d06775b1280931503ff11c1690b4e64e9574b4b5e1758d2a18f80741b9f6e0e8","id":"storage/contents/records/facts","version":"gcs/0.1"},"schema":{"cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","id":"storage/contents/records/row","version":"gcs/0.1"}},"pushdown":{"contract":{"cid":"sha256:6177a5ef6d98eb891bcd679eb394ffe0013652f93d95bd43544877c2f4981a3d","id":"storage/contents/records/pushdown","version":"gcs/0.1"},"operations":["projection"]},"request_processing":{"mutates_business_state":false},"resource_kind":"file","schema":"actql.source_view/0.1","view_id":"records","view_version":"gcs/0.1"},{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:e2f75792e5b5f874b8dae1ae1758b96efe7ff6438015228a5938d04c51c2cde5","id":"storage/files/records/request","version":"gcs/0.1"}},"connector_id":"storage","connector_version":"gcs/0.1","contract_cid":"sha256:e575e81ce66ae4c702f243e795d6c8da0d6ea33d9392b8b3a2c9c0a4bcfeabc6","output":{"carrier":"relation","data_policy":{"cid":"sha256:16818319785133cb0b77cbfe272edee2bf67fcd1c75d2ef90047ca995bb7bb8b","id":"storage/files/records/policy","version":"gcs/0.1"},"facts":{"cid":"sha256:82ce787374fbc4c117ce83c8c31cf9d2d9c733671a5b4a2cb71416bfbd778a41","id":"storage/files/records/facts","version":"gcs/0.1"},"schema":{"cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","id":"storage/files/records/row","version":"gcs/0.1"}},"pushdown":{"contract":{"cid":"sha256:ad715d264c75fc1d2d465fea3fd5f04cc2f2c37f9148ff91f057c8c2e542e1a2","id":"storage/files/records/pushdown","version":"gcs/0.1"},"operations":["projection"]},"request_processing":{"mutates_business_state":false},"resource_kind":"file","schema":"actql.source_view/0.1","view_id":"records","view_version":"gcs/0.1"}]}],"connector_manifest":{"connectors":[{"connector":"gcs","connector_id":"storage","connector_version":"gcs/0.1"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{"carrier":"relation","operations":["projection"],"version":"actql-source-view-pushdown/0.1"},"cid":"sha256:6177a5ef6d98eb891bcd679eb394ffe0013652f93d95bd43544877c2f4981a3d","id":"storage/contents/records/pushdown","kind":"pushdown","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"classification":"unknown","source_ref":"connector://storage/files#records","version":"actql-source-data-policy/0.1"},"cid":"sha256:16818319785133cb0b77cbfe272edee2bf67fcd1c75d2ef90047ca995bb7bb8b","id":"storage/files/records/policy","kind":"data_policy","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"fields":{"media_type":{"nullable":true,"type":"string"},"modified_at":{"nullable":true,"type":"timestamp"},"name":{"nullable":false,"type":"string"},"path":{"nullable":true,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"size_bytes":{"nullable":true,"type":"number"},"version":{"nullable":false,"type":"string"}},"version":"actql-relation-schema/0.1"},"cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","id":"storage/files/records/row","kind":"carrier_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"required_fields":["content","name"]},"cid":"sha256:83320f0478645615e5948872ab7de62819976ddc05269566689700b66245ffb1","id":"storage.gcs.upload.command_input","kind":"command_input","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"prefix":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:ba2c0036f869b0c2a3979f0f2262fa65f141f1d85b3b1b28b2ba288968419e34","id":"storage/objects/records/request","kind":"request_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"file_listing":{"admitted_scope_contract_cid":"sha256:98a7bde0250e1452871939138a72dff1f55194711e8d82b24ce428941645585b","allow_unfiltered_listing":true,"kind":"file_listing","listing_schema_contract_cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","max_examined_items":9,"max_listing_bytes":32768,"max_listing_duration_ms":10000,"max_listing_items":3,"max_listing_pages":4,"max_request_attempts":4,"maximum_path_length":1024,"selectable":["paths","glob"],"version":"actql-file-list/0.1","version_capability":{"contract_cid":"sha256:8937bda765bd83a97122a5e4d87d7db4f12e03393f639ef7f0a236759ed41cdb","required_nonnull":true}}},"cid":"sha256:82ce787374fbc4c117ce83c8c31cf9d2d9c733671a5b4a2cb71416bfbd778a41","id":"storage/files/records/facts","kind":"carrier_facts","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"glob":{"nullable":true,"type":"string"},"paths":{"items":{"nullable":false,"type":"string"},"max_items":3,"nullable":true,"type":"array"}},"nullable":false,"type":"object"},"cid":"sha256:e2f75792e5b5f874b8dae1ae1758b96efe7ff6438015228a5938d04c51c2cde5","id":"storage/files/records/request","kind":"request_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"fields":{"content":{"media_type":"application/pdf","nullable":false,"type":"content_ref"},"media_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}},"version":"actql-relation-schema/0.1"},"cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","id":"storage/contents/records/row","kind":"carrier_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{},"cid":"sha256:757a76824fe568e1dd623edb46abd529124bd9a3b6243f7fdc9e37e2acc4582b","id":"storage/objects/records/facts","kind":"carrier_facts","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"classification":"unknown","source_ref":"connector://storage/objects#records","version":"actql-source-data-policy/0.1"},"cid":"sha256:013046a42a3e212133f350370c53aa5b1573bab424a923d620eee19bd0166cfd","id":"storage/objects/records/policy","kind":"data_policy","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"version":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:cfb6b24f68244d09399c8c672ee12f141bfe2c36ba239e3f624eae09815f1d3c","id":"storage/contents/records/request","kind":"request_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"carrier":"relation","operations":["projection"],"version":"actql-source-view-pushdown/0.1"},"cid":"sha256:eb5bcafaf7eb7ca0f21c07bc9ca73aa714202c02fb8e221de91ed49551141d6c","id":"storage/objects/records/pushdown","kind":"pushdown","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"carrier":"relation","operations":["projection"],"version":"actql-source-view-pushdown/0.1"},"cid":"sha256:ad715d264c75fc1d2d465fea3fd5f04cc2f2c37f9148ff91f057c8c2e542e1a2","id":"storage/files/records/pushdown","kind":"pushdown","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"file_content":{"admitted_scope_contract_cid":"sha256:98a7bde0250e1452871939138a72dff1f55194711e8d82b24ce428941645585b","content_schema_contract_cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","kind":"file_content","representation":"exact_stored_bytes","version":"actql-file-content/0.1","version_capability":{"contract_cid":"sha256:8937bda765bd83a97122a5e4d87d7db4f12e03393f639ef7f0a236759ed41cdb","required_nonnull":true}},"lookup_capacity":{"completeness":"complete_per_requested_key","max_pages_per_request":2,"max_response_bytes_per_page":8192,"max_rows_per_key":1,"version":"actql-lookup-capacity/0.1"}},"cid":"sha256:d06775b1280931503ff11c1690b4e64e9574b4b5e1758d2a18f80741b9f6e0e8","id":"storage/contents/records/facts","kind":"carrier_facts","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"classification":"unknown","source_ref":"connector://storage/contents#records","version":"actql-source-data-policy/0.1"},"cid":"sha256:63d9404d82bbbcce6ffcfd260256a18e31271e0e48d8699fa57e802250b8a673","id":"storage/contents/records/policy","kind":"data_policy","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"fields":{"content_type":{"nullable":true,"type":"string"},"crc32c":{"nullable":true,"type":"string"},"generation":{"nullable":false,"precision":19,"scale":0,"type":"decimal"},"md5":{"nullable":true,"type":"string"},"metadata":{"nullable":true,"type":"json"},"metageneration":{"nullable":false,"precision":19,"scale":0,"type":"decimal"},"name":{"nullable":false,"type":"string"},"resource":{"nullable":false,"resource_kind":"file","type":"resource_ref"},"size":{"nullable":false,"precision":19,"scale":0,"type":"decimal"},"storage_class":{"nullable":true,"type":"string"},"updated":{"nullable":true,"type":"timestamp"},"version":{"nullable":false,"type":"string"}},"version":"actql-relation-schema/0.1"},"cid":"sha256:fa16e17e789f4d7f878477b41af2b7944632c1eeeb3d1ac9918e14f57601ab93","id":"storage/objects/records/row","kind":"carrier_schema","schema":"actql.contract/0.1","version":"gcs/0.1"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:a170e24a2ebd424c14974863509a6cc9080bd035ea146f29630c75dbe738c1eb","id":"storage.gcs.upload.command_output","kind":"command_output","schema":"actql.contract/0.1","version":"gcs/0.1"}],"evidence_bundle_cid":"sha256:8f880e2ab7a307edbad42d091b974bf55f44fdc21afd958961094ab7309e826f","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"lookup_execution":{"max_network_attempts_per_request":3,"max_request_bytes_per_attempt":4096,"max_total_decoded_response_bytes":49152,"max_total_duration_ms":30000,"max_total_request_bytes":73728,"max_total_response_bytes":49152,"version":"actql-lookup-execution-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:9ba0b550db52585a41dffe873c0a8fbc666e7db2745f28ec2f5d8b7669b3fcb1","conversions":[],"mapping_contract_cid":"sha256:dcc14b4cc20e99e657b7bafef7199ab801d7a07cc7e935cf8322878660076b2f","mapping_ref":"mapping:storage.gcs.objects.upload.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"create","permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"selector_class":"none","write_fields":["content","name"]},{"effect_kind":"create","permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"selector_class":"none","write_fields":["content","content_type","name"]},{"effect_kind":"create","permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"selector_class":"none","write_fields":["content","name","overwrite"]},{"effect_kind":"create","permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"selector_class":"none","write_fields":["content","content_type","name","overwrite"]}],"primary_identity":null,"required_fields":["content","name"],"required_permissions":["storage.objects.create","storage.objects.delete","storage.objects.get"],"resource_identity_cid":"sha256:d456e25d1d2a07499d9db78c5ed926b321dc6150977c6b31cda0b07dbbe3eb7b","row_mapping":{"content":{"field":"content","null_behavior":"reject"},"content_type":{"field":"content_type","null_behavior":"reject"},"name":{"field":"name","null_behavior":"reject"},"overwrite":{"field":"overwrite","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","store_command":{"catalog_cid":"sha256:df1f5ff8db6189a69a074d40beca4c9288772d5695ea67b7d7726008cbfcb833","command_contract_cid":"sha256:12cf80a8a0de63135f0382629d3b1a7d2d3c2c0186d24d68a238944d16be381a","command_ref":"command:storage.gcs.upload.v1"},"target_ref":"connector://storage/objects","target_schema":{"additional_properties":false,"fields":{"content":{"nullable":false,"type":"content_ref"},"content_type":{"nullable":false,"type":"string"},"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":false,"type":"boolean"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:3420afa3b6d4a946a3858dde773d70f9ffd4491f083775b06009637a8d2bcf08","version":"gcs/0.1","writable_fields":["content","content_type","name","overwrite"]}],"model_task_contracts":[],"schema_snapshots":[{"carrier_schema_contract_cid":"sha256:fa16e17e789f4d7f878477b41af2b7944632c1eeeb3d1ac9918e14f57601ab93","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:1a2a0f8289b220100afd257ce54bfe2265cacf53b585a3df495cd27ea8f4e729","source_data_policy_cid":"sha256:013046a42a3e212133f350370c53aa5b1573bab424a923d620eee19bd0166cfd","source_ref":"connector://storage/objects#records","source_view_contract_cid":"sha256:1a2a0f8289b220100afd257ce54bfe2265cacf53b585a3df495cd27ea8f4e729"},{"carrier_schema_contract_cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:2a77f55260157432e03baefd0fa9e6fb067fd23090b211d2863092dba9d0c907","source_data_policy_cid":"sha256:63d9404d82bbbcce6ffcfd260256a18e31271e0e48d8699fa57e802250b8a673","source_ref":"connector://storage/contents#records","source_view_contract_cid":"sha256:2a77f55260157432e03baefd0fa9e6fb067fd23090b211d2863092dba9d0c907"},{"carrier_schema_contract_cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:e575e81ce66ae4c702f243e795d6c8da0d6ea33d9392b8b3a2c9c0a4bcfeabc6","source_data_policy_cid":"sha256:16818319785133cb0b77cbfe272edee2bf67fcd1c75d2ef90047ca995bb7bb8b","source_ref":"connector://storage/files#records","source_view_contract_cid":"sha256:e575e81ce66ae4c702f243e795d6c8da0d6ea33d9392b8b3a2c9c0a4bcfeabc6"}],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:e2f75792e5b5f874b8dae1ae1758b96efe7ff6438015228a5938d04c51c2cde5","id":"storage/files/records/request","version":"gcs/0.1"}},"connector_id":"storage","connector_version":"gcs/0.1","contract_cid":"sha256:e575e81ce66ae4c702f243e795d6c8da0d6ea33d9392b8b3a2c9c0a4bcfeabc6","output":{"carrier":"relation","data_policy":{"cid":"sha256:16818319785133cb0b77cbfe272edee2bf67fcd1c75d2ef90047ca995bb7bb8b","id":"storage/files/records/policy","version":"gcs/0.1"},"facts":{"cid":"sha256:82ce787374fbc4c117ce83c8c31cf9d2d9c733671a5b4a2cb71416bfbd778a41","id":"storage/files/records/facts","version":"gcs/0.1"},"schema":{"cid":"sha256:7154fd5cd613cb846e8c626bd66be765735e6c4434aa5b7898df8dffc2412696","id":"storage/files/records/row","version":"gcs/0.1"}},"pushdown":{"contract":{"cid":"sha256:ad715d264c75fc1d2d465fea3fd5f04cc2f2c37f9148ff91f057c8c2e542e1a2","id":"storage/files/records/pushdown","version":"gcs/0.1"},"operations":["projection"]},"request_processing":{"mutates_business_state":false},"resource_kind":"file","schema":"actql.source_view/0.1","view_id":"records","view_version":"gcs/0.1"},{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:ba2c0036f869b0c2a3979f0f2262fa65f141f1d85b3b1b28b2ba288968419e34","id":"storage/objects/records/request","version":"gcs/0.1"}},"connector_id":"storage","connector_version":"gcs/0.1","contract_cid":"sha256:1a2a0f8289b220100afd257ce54bfe2265cacf53b585a3df495cd27ea8f4e729","output":{"carrier":"relation","data_policy":{"cid":"sha256:013046a42a3e212133f350370c53aa5b1573bab424a923d620eee19bd0166cfd","id":"storage/objects/records/policy","version":"gcs/0.1"},"facts":{"cid":"sha256:757a76824fe568e1dd623edb46abd529124bd9a3b6243f7fdc9e37e2acc4582b","id":"storage/objects/records/facts","version":"gcs/0.1"},"schema":{"cid":"sha256:fa16e17e789f4d7f878477b41af2b7944632c1eeeb3d1ac9918e14f57601ab93","id":"storage/objects/records/row","version":"gcs/0.1"}},"pushdown":{"contract":{"cid":"sha256:eb5bcafaf7eb7ca0f21c07bc9ca73aa714202c02fb8e221de91ed49551141d6c","id":"storage/objects/records/pushdown","version":"gcs/0.1"},"operations":["projection"]},"request_processing":{"mutates_business_state":false},"resource_kind":"file","schema":"actql.source_view/0.1","view_id":"records","view_version":"gcs/0.1"},{"acquisition":{"authority":"read_content","correlation":{"cardinality":"one","identity":["resource","version"],"request_fields":["resource","version"],"response_fields":["resource","version"]},"default_mode":"snapshot","kind":"fetch","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:cfb6b24f68244d09399c8c672ee12f141bfe2c36ba239e3f624eae09815f1d3c","id":"storage/contents/records/request","version":"gcs/0.1"}},"connector_id":"storage","connector_version":"gcs/0.1","contract_cid":"sha256:2a77f55260157432e03baefd0fa9e6fb067fd23090b211d2863092dba9d0c907","output":{"carrier":"relation","data_policy":{"cid":"sha256:63d9404d82bbbcce6ffcfd260256a18e31271e0e48d8699fa57e802250b8a673","id":"storage/contents/records/policy","version":"gcs/0.1"},"facts":{"cid":"sha256:d06775b1280931503ff11c1690b4e64e9574b4b5e1758d2a18f80741b9f6e0e8","id":"storage/contents/records/facts","version":"gcs/0.1"},"schema":{"cid":"sha256:4c60a3960c3b1d86bec8006c99da0303e7309663fadf356a1fa08460983cb6e6","id":"storage/contents/records/row","version":"gcs/0.1"}},"pushdown":{"contract":{"cid":"sha256:6177a5ef6d98eb891bcd679eb394ffe0013652f93d95bd43544877c2f4981a3d","id":"storage/contents/records/pushdown","version":"gcs/0.1"},"operations":["projection"]},"request_processing":{"mutates_business_state":false},"resource_kind":"file","schema":"actql.source_view/0.1","view_id":"records","view_version":"gcs/0.1"}],"version":"actql-check-environment/0.1"}
    )
  }
  let cid = if one_short {
    "sha256:def545900f2605594df31fb34632128600733595bad9c37df33353930d8e081e"
  } else {
    "sha256:8f880e2ab7a307edbad42d091b974bf55f44fdc21afd958961094ab7309e826f"
  }
  guard client_program_check_environment(
      wire, cid, false, false, true, false, false, false, false,
    )
    is Some(environment) else {
    abort("The original source-qualified environment must be admitted")
  }
  environment
}

///|
fn original_lookup_diagnostic_programs() -> Array[String] {
  [
    (
      #|{"version":"actql/0.1","id":"gcs-version-fixed-read","stages":[{"id":"s","inputs":{"files":{"connector":"storage","resource":"files","view":"records","request":{"paths":["test/é/fixture.pdf"],"glob":null}},"contents":{"connector":"storage","resource":"contents","view":"records"}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"listed"},{"from":"listed","select":["resource","version","name","path","media_type","size_bytes","modified_at"],"as":"listing_capture"},{"join":{"left":"listing_capture","with":"contents","kind":"inner","on":[{"left":"resource","right":"resource"},{"left":"version","right":"version"}],"select":{"name":"left.name","content":"right.content"}},"as":"captured"},{"from":"captured","assert_rows":{"unique_by":["name"]},"as":"unique_names"},{"from":"unique_names","sort":[{"name":"asc"}],"as":"ordered"}],"results":{"files":{"from":"ordered","fields":["name","content"]}}}],"results":{"files":{"from":{"stage":"s","result":"files"}}}}
    ),
    (
      #|{"version":"actql/0.1","id":"gcs-version-fixed-read","stages":[{"id":"s","inputs":{"files":{"connector":"storage","resource":"files","view":"records","request":{"paths":[],"glob":null}},"contents":{"connector":"storage","resource":"contents","view":"records"}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"listed"},{"from":"listed","select":["resource","version","name","path","media_type","size_bytes","modified_at"],"as":"listing_capture"},{"join":{"left":"listing_capture","with":"contents","kind":"inner","on":[{"left":"resource","right":"resource"},{"left":"version","right":"version"}],"select":{"name":"left.name","content":"right.content"}},"as":"captured"},{"from":"captured","assert_rows":{"unique_by":["name"]},"as":"unique_names"},{"from":"unique_names","sort":[{"name":"asc"}],"as":"ordered"}],"results":{"files":{"from":"ordered","fields":["name","content"]}}}],"results":{"files":{"from":{"stage":"s","result":"files"}}}}
    ),
  ]
}

///|
test "original lookup rejection projection preserves stage and join step without compiler tags" {
  let one_short = original_lookup_diagnostic_environment(true)
  for program in original_lookup_diagnostic_programs() {
    let rejected = client_program_prepare_effect_free_with_parameters(
      program,
      "json",
      one_short,
      None,
    )
    assert_true(client_program_preparation_ready(rejected) is None)
    assert_eq(
      client_program_preparation_decoded_response_limit_json(rejected),
      Some("{\"stageIndex\":0,\"stepIndex\":2}"),
    )
  }
}

///|
test "original lookup rejection projection refuses unrelated causes and a genuinely ready preparation" {
  let sufficient = original_lookup_diagnostic_environment(false)
  for program in original_lookup_diagnostic_programs() {
    let ready = client_program_prepare_effect_free_with_parameters(
      program,
      "json",
      sufficient,
      None,
    )
    assert_true(client_program_preparation_ready(ready) is Some(_))
    assert_true(
      client_program_preparation_decoded_response_limit_json(ready) is None,
    )
  }
  for (document, format) in [("{}", "unsupported"), ("{", "json")] {
    let rejected = client_program_prepare_effect_free_with_parameters(
      document,
      format,
      sufficient,
      None,
    )
    assert_true(client_program_preparation_ready(rejected) is None)
    assert_true(
      client_program_preparation_decoded_response_limit_json(rejected) is None,
    )
  }
}

///|
#external
priv type RequestDiagnosticTestLoader

///|
#module("node:module")
extern "js" fn request_diagnostic_test_loader(
  url : String,
) -> RequestDiagnosticTestLoader = "createRequire"

///|
extern "js" fn request_diagnostic_test_url() -> String =
  #|() => import.meta.url

///|
extern "js" fn request_diagnostic_test_receipt() -> ClientLocalPreparationInputOriginal =
  #|() => Object.freeze({})

///|
extern "js" fn request_diagnostic_test_json(
  document : String,
) -> NativeJsonValue =
  #|(document) => JSON.parse(document)

///|
// Original policy Array ABI, matching the ordinary supplier's existing entry.
#warnings("-deprecated")
extern "js" fn request_diagnostic_test_original(
  loader : RequestDiagnosticTestLoader,
  receipt : ClientLocalPreparationInputOriginal,
  quote : Array[Int64],
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,receipt,quote) => loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(receipt,{planningWork:Number(quote[0]),attempts:Number(quote[1]),holdings:Number(quote[2]),transferBytes:quote[3],retainedBytes:quote[4],executionBytes:quote[5]},()=>{},()=>false,'local-preparation')

///|
fn request_diagnostic_test_parent() -> (
  @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  ClientLocalPreparationInputOriginal,
) {
  let receipt = request_diagnostic_test_receipt()
  let policy = client_local_resource_policy_original()
  let original = request_diagnostic_test_original(
    request_diagnostic_test_loader(request_diagnostic_test_url()),
    receipt,
    client_local_preparation_resource_limits(policy),
  )
  let initial = client_program_prepare_local_preparation_admission(
    original, receipt,
  ).unwrap()
  let parent = client_program_begin_request_preparation(
    initial, receipt, policy,
  ).unwrap()
  client_program_reserve_request_snapshot(parent, receipt, 10000L, 10000L).unwrap()
  (parent, receipt)
}

///|
fn request_diagnostic_checked_issue_code(
  result : Result[Unit, @client_local_host.ClientRequestTerminalIssue],
) -> String? {
  match result {
    Err(issue) => client_program_request_preparation_issue_code(Err(issue))
    Ok(_) => None
  }
}

///|
// Exercise the actual existing JS Result reader across this concrete bridge
// callback. No new Option/tuple decoding or result shape is manufactured.
extern "js" fn request_observation_test_read_js(
  loader : RequestDiagnosticTestLoader,
  project : () -> Result[
    String?,
    @client_local_host.ClientRequestPreparationIssue,
  ],
  present : Bool,
) -> Bool =
  #|(loader,project,present) => { const value=loader('../../../../../adapters/host-common/runtime-result.mjs').checked(project()); return present ? typeof value==='string' && value.includes('"verdict":"invalid"') : value===undefined; }

///|
test "Request original observation bridge returns optional String through the actual JS Result reader without rechecking" {
  let environment = original_lookup_diagnostic_environment(false)
  let wire = "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let publication = @source_publication.prepare_published_query_environment(
    environment, wire,
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"original-observation","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[]},"as":"v"},{"take":-1,"as":"bad"}],"results":{"rows":{"from":"bad","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"s","result":"rows"}}}}
  let (parent, input) = request_diagnostic_test_parent()
  let terminal = match
    client_program_prepare_request_native_computation(
      parent,
      input,
      request_diagnostic_test_json(document),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    ) {
    Err(issue) => issue
    Ok(_) => fail("the original negative Take must reject")
  }
  let project = () => {
    client_program_project_request_check_outcome(
      parent,
      input,
      terminal,
      wire,
      "ctx:" + "a".repeat(64),
      "program",
      "rev:" + "b".repeat(64),
      document.length(),
      None,
      0,
      None,
      0,
      "corr:" + "c".repeat(32),
      None,
    )
  }
  let loader = request_diagnostic_test_loader(request_diagnostic_test_url())
  assert_true(request_observation_test_read_js(loader, project, true))
  client_program_abort_request_preparation(parent).unwrap()
  assert_true(request_observation_test_read_js(loader, project, false))
}

///|
test "Request original observation bridge never upgrades undisclosable NeedsInputs to verified" {
  let environment = original_lookup_diagnostic_environment(false)
  let wire = "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let publication = @source_publication.prepare_published_query_environment(
    environment, wire,
  ).unwrap()
  // Existing report labels are deliberately limited to256. The semantic
  // parameter name is valid, but its unresolved obligation must not disappear
  // merely because that particular public requirement cannot be enumerated.
  let name = "p".repeat(257)
  let document = "{\"version\":\"actql/0.1\",\"id\":\"original-needs-input\",\"params\":{\"" +
    name +
    "\":{\"type\":\"number\"}},\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"v\"},{\"derive\":{\"value\":\"id + $" +
    name +
    "\"},\"as\":\"d\"}],\"results\":{\"rows\":{\"from\":\"d\",\"fields\":[\"value\"]}}}],\"results\":{\"rows\":{\"from\":{\"stage\":\"s\",\"result\":\"rows\"}}}}"
  let (parent, input) = request_diagnostic_test_parent()
  let terminal = match
    client_program_prepare_request_native_computation(
      parent,
      input,
      request_diagnostic_test_json(document),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    ) {
    Err(issue) => issue
    Ok(_) => fail("the original missing parameter must remain incomplete")
  }
  guard terminal is CheckOutcome(@program_check.NeedsInputs(_)) else {
    fail("must retain the actual nominal NeedsInputs frontier")
  }
  let report = client_program_project_request_check_outcome(
      parent,
      input,
      terminal,
      wire,
      "ctx:" + "a".repeat(64),
      "program",
      "rev:" + "b".repeat(64),
      document.length(),
      None,
      0,
      None,
      0,
      "corr:" + "c".repeat(32),
      None,
    )
    .unwrap()
    .unwrap()
  assert_true(report.contains("\"verdict\":\"undetermined\""), msg=report)
  assert_false(report.contains(name))
  client_program_abort_request_preparation(parent).unwrap()
}

///|
test "Request failure projection uses the original semantic issue without another check" {
  let environment = original_lookup_diagnostic_environment(false)
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let program =
    #|{"version":"actql/0.1","id":"request-refusal","params":{"n":{"type":"number"}},"stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"v"},{"derive":{"value":"id + $n"},"as":"d"}],"results":{"rows":{"from":"d","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"s","result":"rows"}}}}
  let missing =
    #|{"version":"actql/0.1","id":"missing-source","stages":[{"id":"s","inputs":{"remote":{"connector":"missing","resource":"rows","view":"records"}},"steps":[{"from":"remote","take":1,"as":"v"}],"results":{"rows":{"from":"v","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"s","result":"rows"}}}}
  for
    (document, parameters, expected) in [
      ("{}", None, "check_invalid_input"),
      (program, Some("{\"n\":\"wrong type\"}"), "check_invalid_input"),
      (program, None, "needs_inputs"),
      (missing, None, "source_unresolved"),
    ] {
    let (parent, receipt) = request_diagnostic_test_parent()
    let result = client_program_prepare_request_native_computation(
      parent,
      receipt,
      request_diagnostic_test_json(document),
      request_diagnostic_test_json(parameters.unwrap_or("null")),
      environment,
      publication,
      None,
    )
    assert_true(result is Err(_))
    assert_eq(request_diagnostic_checked_issue_code(result), Some(expected))
    @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "Request failure projection keeps input admission and nonsemantic uncertainty separate" {
  let environment = original_lookup_diagnostic_environment(false)
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  // Foreign identity and retired same-original calls produce real nominal
  // errors. No test issuer or widened read-only constructor is introduced.
  let foreign = client_program_prepare_request_native_computation(
    parent,
    request_diagnostic_test_receipt(),
    request_diagnostic_test_json("{}"),
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  )
  assert_true(foreign is Err(_))
  assert_eq(request_diagnostic_checked_issue_code(foreign), None)
  @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
  let retired = client_program_prepare_request_native_computation(
    parent,
    receipt,
    request_diagnostic_test_json("{}"),
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  )
  assert_true(retired is Err(_))
  assert_eq(request_diagnostic_checked_issue_code(retired), None)
  assert_eq(
    client_program_request_preparation_issue_code(Ok("effect_free")),
    None,
  )
}

///|
test "original compilation sum preserves actual Values Task issuers and foreign owner refusal" {
  let environment = original_lookup_diagnostic_environment(false)
  let text =
    #|{"version":"actql/0.1","id":"original-typed-compilation","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"v"}],"results":{"rows":{"from":"v","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"s","result":"rows"}}}}
  let prepare = () => {
    client_program_preparation_ready(
      client_program_prepare_effect_free_with_parameters(
        text,
        "json",
        environment,
        None,
      ),
    ).unwrap()
  }
  let prepared = prepare()
  let foreign = prepare()
  let values = client_program_compile_local_values(prepared).unwrap()
  let tasks = client_program_compile_local_tasks(prepared).unwrap()
  let context = "sha256:" + "a".repeat(64)
  let policy = "sha256:" + "b".repeat(64)
  let expires = "2030-01-01T00:00:00.000Z"
  let original_values : @publication_host.ClientRunCompilation = @publication_host.Values(
    values,
  )
  let original_tasks : @publication_host.ClientRunCompilation = @publication_host.Tasks(
    tasks,
  )
  for
    (original, is_values) in [(original_values, true), (original_tasks, false)] {
    let result = if is_values {
      client_program_issue_original_values_compiled_run(
        prepared, original, context, policy, expires,
      )
    } else {
      client_program_issue_original_task_compiled_run(
        prepared, original, context, policy, expires,
      )
    }
    assert_true(
      @publication_host.client_compiled_run_matches(result.unwrap(), prepared),
    )
    let foreign_result = if is_values {
      client_program_issue_original_values_compiled_run(
        foreign, original, context, policy, expires,
      )
    } else {
      client_program_issue_original_task_compiled_run(
        foreign, original, context, policy, expires,
      )
    }
    assert_true(foreign_result is Err(ForeignOwner))
  }
  assert_true(
    client_program_issue_original_values_compiled_run(
      prepared, original_tasks, context, policy, expires,
    )
    is Err(ForeignOwner),
  )
  assert_true(
    client_program_issue_original_task_compiled_run(
      prepared, original_values, context, policy, expires,
    )
    is Err(ForeignOwner),
  )
}

///|
test "native Query terminal projects original syntax declaration and missing-input refusals" {
  let environment = original_lookup_diagnostic_environment(false)
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  for
    (source, expected) in [
      ("{\"format\":\"sql\",\"text\":\"SELECT (\"}", "source_invalid_input"),
      (
        "{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\",\"parameterDeclarations\":null}",
        "source_declarations",
      ),
      (
        "{\"format\":\"sql\",\"text\":\"SELECT id FROM missing\"}", "source_unresolved",
      ),
      (
        "{\"format\":\"sql\",\"text\":\"SELECT @n AS n\",\"parameterDeclarations\":{\"n\":{\"type\":\"number\"}}}",
        "needs_inputs",
      ),
    ] {
    let (parent, receipt) = request_diagnostic_test_parent()
    let result = client_program_prepare_request_source_computation(
      parent,
      receipt,
      request_diagnostic_test_json(source),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    )
    assert_true(result is Err(_))
    assert_eq(request_diagnostic_checked_issue_code(result), Some(expected))
    @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "native Query terminal keeps foreign and retired originals outside semantic refusal" {
  let environment = original_lookup_diagnostic_environment(false)
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  let source = request_diagnostic_test_json(
    "{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"}",
  )
  let supplied = request_diagnostic_test_json("null")
  let foreign = client_program_prepare_request_source_computation(
    parent,
    request_diagnostic_test_receipt(),
    source,
    supplied,
    environment,
    publication,
    None,
  )
  assert_true(foreign is Err(_))
  assert_eq(request_diagnostic_checked_issue_code(foreign), None)
  @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
  let retired = client_program_prepare_request_source_computation(
    parent,
    receipt,
    source,
    supplied,
    environment,
    publication,
    None,
  )
  assert_true(retired is Err(_))
  assert_eq(request_diagnostic_checked_issue_code(retired), None)
}

///|
test "native Source document terminal projects original invalid Program instead of unconnected phase" {
  let environment = original_lookup_diagnostic_environment(false)
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  for format in ["json", "yaml"] {
    let (parent, receipt) = request_diagnostic_test_parent()
    let source = request_diagnostic_test_json(
      "{\"format\":\"" + format + "\",\"text\":\"{}\"}",
    )
    let result = client_program_prepare_request_source_computation(
      parent,
      receipt,
      source,
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    )
    assert_true(
      result
      is Err(
        @client_local_host.ClientRequestTerminalIssue::Preparation(
          ProgramJson(Syntax(_))
        )
      ),
    )
    assert_eq(
      request_diagnostic_checked_issue_code(result),
      Some("check_invalid_input"),
    )
    @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
  }
}
