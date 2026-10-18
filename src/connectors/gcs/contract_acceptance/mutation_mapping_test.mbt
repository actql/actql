///|
fn mutation_original_declaration() -> @row.RowDeclaration raise {
  // Same objects field types as the ordinary GCS declaration, issued here by
  // its actual Common declaration Owner. No provider/credential I/O is used.
  let text : Json = { "type": "string", "nullable": true }
  let integer : Json = {
    "type": "decimal",
    "precision": 19,
    "scale": 0,
    "nullable": false,
  }
  let schema : Json = {
    "resource": {
      "type": "resource_ref",
      "resource_kind": "file",
      "nullable": false,
    },
    "version": { "type": "string", "nullable": false },
    "name": { "type": "string", "nullable": false },
    "size": integer,
    "content_type": text,
    "generation": integer,
    "metageneration": integer,
    "storage_class": text,
    "updated": { "type": "timestamp", "nullable": true },
    "md5": text,
    "crc32c": text,
    "metadata": { "type": "json", "nullable": true },
  }
  @row.generate_relation_row_declaration(
    "exports",
    "gcs",
    "gcs/0.1",
    [
      {
        resource: "objects",
        resource_kind: "file",
        schema_wire: canonical(schema),
        schema_cid: cid(schema),
        request_schema_wire: Some(
          canonical({
            "type": "object",
            "nullable": false,
            "additional_properties": false,
            "fields": { "prefix": text },
          }),
        ),
        facts_wire: Some("{}"),
        acquisition_wire: Some(
          "{\"authority\":\"read_metadata\",\"kind\":\"scan\"}",
        ),
      },
    ],
    {
      max_bytes: 100000,
      max_nodes: 20000,
      max_depth: 64,
      max_views: 4,
      max_fields: 32,
    },
  ).unwrap()
}

///|
fn mutation_common_environment(
  kind : @gcs.ObjectMutationKind,
) -> @environment.WireEnvironment raise {
  let declaration = mutation_original_declaration()
  let wire = canonical({
    "connector_id": "exports",
    "connector_registration": "gcs",
    "connector_version": "gcs/0.1",
    "catalog": declaration.catalog.to_json(),
    "catalog_cid": declaration.catalog_cid.to_json(),
    "contracts": declaration.contracts.to_json(),
    "views": Json::array(
      declaration.views.map(view => {
        "source_ref": view.source_ref.to_json(),
        "view_cid": view.view_cid.to_json(),
      }),
    ),
    "manifest_entry": declaration.manifest_entry.to_json(),
    "manifest_entry_cid": declaration.manifest_entry_cid.to_json(),
  })
  let binding = @gcs.prepare_object_mutation_binding(
    kind,
    "bucket",
    "in/",
    declaration.catalog_cid,
    "sha256:" + "2".repeat(64),
    "sha256:" + "3".repeat(64),
    ["storage.objects.get", "storage.objects.update", "storage.objects.delete"],
    {
      metadata: {
        max_bytes: 8192,
        max_nodes: 1000,
        max_depth: 16,
        max_metadata_entries: 10,
      },
      max_path_bytes: 4096,
      max_body_bytes: 8192,
      max_identity_bytes: 16384,
    },
  ).unwrap()
  let mapping = @gcs.object_mutation_mapping_json(binding, wire, "exports", {
    max_bytes: 100000,
    max_nodes: 20000,
    max_depth: 64,
  }).unwrap()
  let (schemas, capabilities) = @row.row_declaration_evidence_members(
    declaration,
  )
  let body : Json = {
    "version": "actql-check-environment/0.1",
    "schema_snapshots": Json::array(schemas.map(wire => @json.parse(wire))),
    "connector_capabilities": Json::array(
      capabilities.map(wire => @json.parse(wire)),
    ),
    "mapping_contracts": [@json.parse(mapping)],
    "source_views": Json::array(
      declaration.view_bodies.map(wire => @json.parse(wire)),
    ),
    "command_contracts": [],
    "model_task_contracts": [],
    "contract_registry": body_sorted(
      declaration.contracts.map(wire => @json.parse(wire)),
    ),
    "connector_catalogs": [@json.parse(declaration.catalog)],
    "host_policy_profile": {},
    "connector_manifest": {
      "version": "actql-connectors/0.1",
      "connectors": [@json.parse(declaration.manifest_entry)],
    },
  }
  let expected = cid(body)
  guard body is Object(fields) else { abort("environment") }
  fields["evidence_bundle_cid"] = expected.to_json()
  @environment.read(@utf8.encode(canonical(body)), expected, caps()).unwrap()
}

///|
test "GCS mutation Mapping reaches actual Common Catalog roles and Mapping admission" {
  for kind in [@gcs.PatchMetadata, @gcs.DeleteObject] {
    let original = mutation_common_environment(kind)
    let refs = references(catalogs(original))
    @environment.check_source_data_policies(refs, {
      max_work: 100000,
      max_policies: 100,
    }).unwrap()
    |> ignore
    let mappings = @environment.check_mapping_contract_shapes(
      original,
      caps(),
      100000,
    ).unwrap()
    @environment.mapping_shape_at(mappings, 0).unwrap() |> ignore
  }
}
