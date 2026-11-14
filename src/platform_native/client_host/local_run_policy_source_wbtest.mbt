///|
// Original checked row Source inputs. Declaration generation only supplies
// fixture evidence; no Source I/O, execution permission or capacity is issued.
fn source_policy_environment() -> @checked.CheckEnvironment raise {
  let declaration = @rows.generate_row_declaration(
    "policy-source",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "record",
        fields: [{ name: "id", value_type: "number", nullable: false, }],
      },
    ],
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_views: 1,
      max_fields: 1,
    },
  ).unwrap()
  let original =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let parsed = @json.parse(original)
  guard parsed is Object(base) else { fail("fixture Environment") }
  base.remove("evidence_bundle_cid")
  let (schemas, capabilities) = @rows.row_declaration_evidence_members(
    declaration,
  )
  base["connector_catalogs"] = source_policy_members([declaration.catalog])
  base["contract_registry"] = source_policy_members(declaration.contracts)
  base["source_views"] = source_policy_members(declaration.view_bodies)
  base["schema_snapshots"] = source_policy_members(schemas)
  base["connector_capabilities"] = source_policy_members(capabilities)
  let manifest : Json = {
    "version": Json::string("actql-connectors/0.1"),
    "connectors": source_policy_members([declaration.manifest_entry]),
  }
  base["connector_manifest"] = manifest
  let body = @canonical.stringify_value(
    @canonical.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  let evidence = "sha256:" + @sha.hex(@utf8.encode(body))
  base["evidence_bundle_cid"] = Json::string(evidence)
  let wire = @canonical.stringify_value(
    @canonical.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  @host.admit_client_check_environment(
    wire,
    evidence,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn source_policy_members(bodies : Array[String]) -> Json raise {
  let ordered = bodies.map(body => {
    let wire = @canonical.stringify_value(
      @canonical.from_json(@json.parse(body), 100000, 100, 1000000),
      1000000,
      100000,
      100,
    )
    (@sha.hex(@utf8.encode(wire)), wire)
  })
  ordered.sort_by((left, right) => left.0.compare(right.0))
  @json.parse("[" + ordered.map(value => value.1).join(",") + "]")
}

///|
fn source_policy_preparation() -> (
  @host.ClientSubmittedIntent,
  NativeClientSubmittedPreparation,
  @host.PreparedClientProgram,
) raise {
  let document =
    #|{"version":"actql/0.1","id":"policy-source","stages":[{"id":"read","inputs":{"remote":{"connector":"policy-source","resource":"records"}},"steps":[{"select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"out":{"from":{"stage":"read","result":"out"}}}}
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" + document + ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = prepare_native_client_submitted_program(
    intent,
    source_policy_environment(),
    None,
    [],
    @host.client_standard_effect_computation_limits(),
  ).unwrap()
  guard preparation.preparation is Computation(prepared) else {
    fail("checked Pure Source required")
  }
  assert_eq(@host.prepared_client_acquisition_count(prepared), 1)
  (intent, preparation, prepared)
}

///|
// Execute the exact pure projection used by pending Policy preparation. This
// case never selects the legacy-library Host fixture or its physical supplier.
test "pending Policy identity retains the checked Pure Source original" {
  let (_, preparation, prepared) = source_policy_preparation()
  let actual = native_local_run_policy_preparation_identity(preparation)
  guard actual is Ok(identity) else {
    let kind = match actual {
      Err(issue) => selected_policy_journal_issue(issue)
      Ok(_) => "Unavailable"
    }
    fail("pending Source identity: " + kind)
  }
  assert_eq(identity, @host.prepared_client_identity(prepared))
}

///|
// A valid Source compilation is still insufficient for the legacy entrance.
// Only the actual captured-Read caller can pass its retained managed original.
test "Source Policy acceptance refuses an absent managed Plan despite original compilation" {
  let (_, _, prepared) = source_policy_preparation()
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let tasks = @host.issue_prepared_client_task_compilation(
    prepared,
    manifests,
    @host.prepared_client_values_sequence_limits(prepared),
    1000,
    1000,
    65536,
    8192,
    64,
  ).unwrap()
  let compiled = @host.issue_client_task_compiled_run(
    prepared,
    tasks,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "source-policy-no-managed-plan",
  ).unwrap()
  assert_true(@host.client_compiled_run_matches(compiled, prepared))
  assert_true(
    !native_local_run_policy_compilation_original(
      prepared,
      request,
      compiled,
      None,
    ),
  )
}
