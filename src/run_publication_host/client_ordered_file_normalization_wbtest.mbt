///|
fn ordered_file_normalization_environment(
  operation : String,
) -> (@checked.CheckEnvironment, String) raise {
  let schema =
    #|{"account":{"nullable":false,"type":"string"},"sequence":{"nullable":false,"type":"int64"},"value":{"nullable":false,"type":"string"}}
  let limits : @row_host.RowDeclarationLimits = {
    max_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
    max_views: 4,
    max_fields: 16,
  }
  let declaration = @row_host.generate_relation_row_declaration(
    "ordered",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        schema_wire: schema,
        schema_cid: "sha256:" + @sha.hex(@utf8.encode(schema)),
        request_schema_wire: None,
        facts_wire: Some(
          "{\"relation_keys\":{\"candidate_keys\":[[\"account\",\"sequence\"]]}}",
        ),
        acquisition_wire: None,
      },
    ],
    limits,
  ).unwrap()
  let facts = if operation == "delete" {
    "{\"permission\":\"fixture:delete\",\"approval\":\"required\"}"
  } else {
    "{\"fields\":[\"value\"],\"permission\":\"fixture:write\",\"approval\":\"required\"}"
  }
  let writes = "{\"writes\":[{\"resource\":\"records\",\"primary_identity\":{\"kind\":\"tuple\",\"fields\":[\"account\",\"sequence\"]},\"" +
    operation +
    "\":" +
    facts +
    "}]}"
  let fields : Array[@row_host.RowMappingSource] = [
    { target: "value", field: "value", null_behavior: "reject", },
  ]
  let mapping = (match operation {
    "update" =>
      @row_host.prepare_row_update_mapping(
        declaration, writes, "records", fields,
      )
    "upsert" =>
      @row_host.prepare_row_file_upsert_mapping(
        declaration, writes, "records", fields,
      )
    _ =>
      @row_host.prepare_row_delete_mapping_from_writes(
        declaration, writes, "records",
      )
  }).unwrap()
  let (schemas, capabilities) = @row_host.row_declaration_evidence_members(
    declaration,
  )
  guard @json.parse(run_materials_environment_wire) is Object(body) else {
    abort("environment fixture")
  }
  body.remove("evidence_bundle_cid")
  body["schema_snapshots"] = source_extent_members(schemas).to_json()
  body["connector_capabilities"] = source_extent_members(capabilities).to_json()
  body["source_views"] = source_extent_members(declaration.view_bodies).to_json()
  body["contract_registry"] = source_extent_members(declaration.contracts).to_json()
  body["connector_catalogs"] = [@json.parse(declaration.catalog)].to_json()
  body["connector_manifest"] = {
    "version": "actql-connectors/0.1",
    "connectors": [@json.parse(declaration.manifest_entry)],
  }
  body["mapping_contracts"] = [@json.parse(mapping.body)].to_json()
  let (_, cid) = source_extent_json(Json::object(body))
  body["evidence_bundle_cid"] = cid.to_json()
  let (wire, _) = source_extent_json(Json::object(body))
  let environment = admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  (environment, mapping.mapping_ref)
}

///|
test "ordered File mutations use their original tuple journal and require File profile selection" {
  for operation in ["update", "delete", "upsert"] {
    let original =
      #|{"version":"actql/0.1","id":"ordered-mutation","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"account":{"type":"string","nullable":false},"sequence":{"type":"int64","nullable":false},"value":{"type":"string","nullable":false}},"rows":[{"account":"a","sequence":"9007199254740993","value":"updated"}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["account","sequence","value"]}},"effects":{"apply":{"@kind":{"target":"connector://ordered/records","mapping":"@mapping","from":{"result":"out"},"@tuple":[{"target_field":"account","result_field":"account"},{"target_field":"sequence","result_field":"sequence"}]@set}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
    let tuple = if operation == "upsert" { "key_tuple" } else { "match_tuple" }
    let fields = if operation == "delete" {
      ""
    } else {
      ",\"set\":{\"value\":{\"field\":\"value\"}}"
    }
    let (environment, mapping_ref) = ordered_file_normalization_environment(
      operation,
    )
    let program = original
      .replace(old="@mapping", new=mapping_ref)
      .replace(old="@kind", new=operation)
      .replace(old="@tuple", new=tuple)
      .replace(old="@set", new=fields)
    let target = "connector://ordered/records"
    let binding = "sha256:" + "b".repeat(64)
    let installation = "sha256:" + "a".repeat(64)
    let publication_wire = source_extent_json({
        "environmentCid": @checked.checking_environment_cid(environment).to_json(),
        "updateTargets": [
          {
            "name": "ordered.records",
            "targetRef": target.to_json(),
            "installationBindingCid": binding.to_json(),
            "installationOwnerCid": installation.to_json(),
          },
        ],
      }).0
    let publication = @source_publication.published_update_targets(
        environment, publication_wire,
      )
      .unwrap()
      .unwrap()
    if operation != "upsert" {
      let selected = @update_targets.resolve_concrete_update_target_binding(
        publication,
        target,
        mapping_ref,
        1000,
        effect_kind=operation,
        match_tuple=true,
      ).unwrap()
      assert_eq(
        @update_targets.resolved_update_target_owner_cid(selected),
        installation,
      )
      assert_true(
        @update_targets.resolve_concrete_update_target_binding(
          publication,
          target,
          mapping_ref,
          1000,
          effect_kind=operation,
        )
        is Err(@update_targets.UnresolvedMapping),
      )
      let other_operation = if operation == "delete" {
        "update"
      } else {
        "delete"
      }
      assert_true(
        @update_targets.resolve_concrete_update_target_binding(
          publication,
          target,
          mapping_ref,
          1000,
          effect_kind=other_operation,
          match_tuple=true,
        )
        is Err(@update_targets.UnresolvedMapping),
      )
    }
    let owner = match
      prepare_client_effect_computation(
        program,
        Json,
        environment,
        None,
        [],
        client_standard_effect_computation_limits(),
        update_targets=Some(publication),
      ) {
      Ok(value) => value
      Err(Syntax(issue)) =>
        fail(operation + " syntax: " + @debug.to_string(issue))
      Err(Mapping(issue)) =>
        fail(operation + " mapping: " + @debug.to_string(issue))
      Err(Static(_)) => fail(operation + " static binding failed")
      Err(Graph(issue)) =>
        fail(operation + " graph: " + @debug.to_string(issue))
      Err(TargetSelection(_)) => fail(operation + " target selection failed")
      Err(_) => fail(operation + " fixture preparation failed")
    }
    if operation != "upsert" {
      let selection = prepared_client_effect_target_selections(owner).unwrap()
      guard @json.parse(selection) is Array([Object(row)]) else {
        fail("expected one installed target original")
      }
      assert_eq(row.get("installation_owner_cid"), Some(installation.to_json()))
      assert_eq(row.get("mapping_ref"), Some(mapping_ref.to_json()))
      assert_eq(row.get("target_ref"), Some(target.to_json()))
    }
    assert_true(
      issue_prepared_client_effect_selected_normalization(owner)
      is Err(Inventory(ProfileNotInstalled)),
    )
    let proof = issue_prepared_client_effect_selected_normalization(
      owner,
      allow_file_mutation=true,
    ).unwrap()
    guard proof.inventory is FileMutation(inventory) else {
      fail("missing checked File inventory")
    }
    assert_true(
      @checked.local_common_file_mutation_normalization_ordered(inventory),
    )
    assert_eq(
      client_effect_normalization_catalog_cid(proof),
      "sha256:c223b3b669fb28ecb9d3e4f38d88642c93293d37623f775cc41aac79f4ba194b",
    )
    assert_true(
      issue_prepared_client_effect_selected_normalization(owner)
      is Err(Inventory(ProfileNotInstalled)),
    )
    let bounds = run_materials_limits()
    let manifests = run_materials_manifests()
    let compiled = issue_prepared_client_effect_compilation(
      owner,
      manifests,
      bounds.sequence,
      bounds.max_sequence_steps,
      bounds.max_sequence_work,
      bounds.max_evidence_bytes,
      bounds.max_evidence_nodes,
      bounds.max_evidence_depth,
      normalization=Some(proof),
    ).unwrap()
    let scope = "sha256:" + "a".repeat(64)
    let allowed = issue_client_effect_allowed_run(
      compiled,
      scope,
      "sha256:" + "b".repeat(64),
      "2026-10-10T00:00:00.000Z",
    ).unwrap()
    let definition = issue_client_effect_run_definition(
      allowed, "ordered-file-scope", "ordered-file-run", "2026-10-09T00:00:00.000Z",
      "2026-10-10T00:00:00.000Z",
    ).unwrap()
    let request = prepare_client_effect_request_identity(
      owner,
      scope,
      "ordered-file-caller",
      source_free_caller_input_intent_cid(),
    ).unwrap()
    let issued = issue_prepared_client_effect_normalization_materials(
      allowed,
      definition,
      proof,
      request=Some(request),
    ).unwrap()
    let wire = client_effect_issued_normalization_materials_wire(issued)
    let restored = admit_client_effect_run_materials(
      wire,
      @publication.publication_contract_identity(definition),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      manifests,
      bounds,
      client_standard_effect_computation_limits(),
      expected_request=Some(request),
    ).unwrap()
    assert_eq(restored.request, Some(request))
    let journal = restore_client_effect_run_normalization(restored).unwrap()
    assert_eq(
      @publication.run_evidence_value_json(journal),
      @publication.run_evidence_value_json(proof.journal),
    )
    guard restored.compilation.normalization_profile
      is Some(FileMutation(recovered)) else {
      fail("missing restored File inventory")
    }
    assert_true(
      @checked.local_common_file_mutation_normalization_ordered(recovered),
    )
  }
}
