///|
let run_materials_environment_wire : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
let run_materials_environment_cid : String = "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904"

///|
let run_materials_document : String =
  #|{"version":"actql/0.1","id":"client-values","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"rows"}}}}

///|
fn run_materials_limits() -> ClientValuesRunMaterialsLimits {
  {
    preparation: client_standard_program_preparation_limits(),
    sequence: {
      max_steps: 10,
      max_rows: 10,
      max_cells: 10,
      max_bindings: 10,
      max_name_bytes: 1000,
      expressions: {
        max_nodes: 100,
        max_work: 1000,
        max_depth: 10,
        max_literal_nodes: 100,
        max_literal_text_bytes: 1000,
      },
    },
    max_sequence_steps: 32,
    max_sequence_work: 64,
    max_evidence_bytes: 100000,
    max_evidence_nodes: 10000,
    max_evidence_depth: 100,
  }
}

///|
fn run_materials_manifests() -> ClientCompilationManifests {
  admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
}

///|
fn run_materials_json(fields : Array[(String, String?)]) -> String raise {
  let writer = @encode.writer(1000000, 64, 4)
  @encode.begin_object(writer)
  for field in fields {
    @encode.key(writer, field.0)
    match field.1 {
      Some(value) => @encode.string_value(writer, value)
      None => @encode.null_value(writer)
    }
  }
  @encode.end_object(writer)
  @encode.finish(writer)
}

///|
test "run materials rebuild exactly the dispatched source-free Values Run" {
  // The issuing side (for example a Cloud) prepares, compiles and authorizes
  // the Run through the ordinary owners.
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let limits = run_materials_limits()
  let issuer_prepared = prepare_effect_free_client_program(
    run_materials_document,
    Json,
    environment,
    None,
    limits.preparation,
  ).unwrap()
  let issuer_compilation = issue_prepared_client_values_compilation(
    issuer_prepared,
    run_materials_manifests(),
    limits.sequence,
    32,
    64,
    100000,
    10000,
    100,
  ).unwrap()
  let execution_context = "sha256:" + "a".repeat(64)
  let host_policy = "sha256:" + "b".repeat(64)
  let allowed = issue_client_values_compiled_run(
    issuer_prepared, issuer_compilation, execution_context, host_policy, "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let issued = issue_client_compiled_run_definition(
    allowed, "cloud-scope", "cloud-run-1", "2026-09-30T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let issued_cid = @publication.publication_contract_identity(issued)
  let fields : Array[(String, String?)] = [
    ("check_environment", Some(run_materials_environment_wire)),
    ("check_environment_cid", Some(run_materials_environment_cid)),
    ("created_at", Some("2026-09-30T00:00:00.000Z")),
    ("parameters", None),
    (
      "prepared_invocation",
      Some(
        @publication.run_evidence_value_json(
          client_compiled_run_prepared(allowed),
        ),
      ),
    ),
    ("program", Some(run_materials_document)),
    ("program_format", Some("json")),
    (
      "run_authorization",
      Some(
        @publication.run_evidence_value_json(
          client_compiled_run_authorization(allowed),
        ),
      ),
    ),
    ("run_id", Some("cloud-run-1")),
    ("scope_id", Some("cloud-scope")),
    ("valid_until", Some("2099-01-01T00:00:00.000Z")),
    ("version", Some("actql-remote-run-materials/0.1")),
  ]
  let admit = fn(body : String, expected : String) {
    admit_client_values_run_materials(
      body,
      expected,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_manifests(),
      limits,
    )
  }
  let projected = issue_client_values_run_materials(
    issuer_prepared,
    issuer_compilation,
    client_compiled_run_admission(allowed),
    issued,
    environment,
    run_materials_environment_wire,
    run_materials_document,
    None,
  ).unwrap()
  // Independently assembled fields, not a snapshot copied from the issuer.
  assert_eq(projected, run_materials_json(fields))
  assert_eq(
    @publication.publication_contract_identity(
      admit(projected, issued_cid).unwrap().run_definition,
    ),
    issued_cid,
  )
  assert_true(
    issue_client_values_run_materials(
      issuer_prepared,
      issuer_compilation,
      client_compiled_run_admission(allowed),
      issued,
      environment,
      run_materials_environment_wire,
      run_materials_document.replace(old="{\"id\":2}", new="{\"id\":3}"),
      None,
    )
    is Err(MaterialsRunMismatch),
  )
  assert_true(
    issue_client_values_run_materials(
      issuer_prepared,
      issuer_compilation,
      client_compiled_run_admission(allowed),
      issued,
      environment,
      "{}",
      run_materials_document,
      None,
    )
    is Err(MaterialsEnvironment),
  )
  assert_true(
    issue_client_values_run_materials(
      issuer_prepared,
      issuer_compilation,
      client_compiled_run_admission(allowed),
      issued,
      environment,
      run_materials_environment_wire,
      run_materials_document,
      Some(" ".repeat(65537)),
    )
    is Err(MaterialsParameters),
  )
  // The Run definition CID of this fixed fixture, pinned independently of
  // the issuer: a change in what the CID covers, or in how the Site
  // rebuilds the Run, moves it. The Program definition CID has the same
  // shape and is not it.
  assert_eq(
    issued_cid, "sha256:6a5c24d7320c4edfcd61609c5490463b38df1f0c73b398f01b196f1feff35c80",
  )
  assert_eq(
    prepared_client_identity(issuer_prepared).program_definition_cid,
    "sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c",
  )
  // The Site rebuilds the same Run; the materials never supply the Plan.
  let rebuilt = admit(run_materials_json(fields), issued_cid).unwrap()
  assert_eq(
    @publication.publication_contract_identity(rebuilt.run_definition),
    issued_cid,
  )
  // The CID of another Run, including the Program definition CID, is refused.
  let program_cid = prepared_client_identity(issuer_prepared).program_definition_cid
  assert_true(
    admit(run_materials_json(fields), program_cid) is Err(MaterialsRunMismatch),
  )
  // A different Program, Run identity or lifetime rebuilds a different Run.
  let replace = fn(name : String, value : String?) raise {
    run_materials_json(
      fields.map(field => if field.0 == name { (name, value) } else { field }),
    )
  }
  assert_true(
    admit(
      replace(
        "program",
        Some(run_materials_document.replace(old="{\"id\":2}", new="{\"id\":3}")),
      ),
      issued_cid,
    )
    is Err(_),
  )
  assert_true(
    admit(replace("run_id", Some("cloud-run-2")), issued_cid)
    is Err(MaterialsRunMismatch),
  )
  assert_true(
    admit(replace("valid_until", Some("2098-01-01T00:00:00.000Z")), issued_cid)
    is Err(MaterialsRunMismatch),
  )
  // Each inner body is bounded by its own owner's limit; a body past it is
  // refused before anything is rebuilt.
  assert_true(
    admit(
      replace("parameters", Some("\"" + "p".repeat(65536) + "\"")),
      issued_cid,
    )
    is Err(_),
  )
  assert_true(
    admit(
      replace("program", Some(run_materials_document + " ".repeat(65537))),
      issued_cid,
    )
    is Err(_),
  )
  // Received evidence must be the named evidence of this Plan.
  assert_true(
    admit(
      replace(
        "prepared_invocation",
        Some(
          @publication.run_evidence_value_json(
            client_compiled_run_authorization(allowed),
          ),
        ),
      ),
      issued_cid,
    )
    is Err(MaterialsEvidence("prepared_invocation")),
  )
  // The body is an exact, flat, bounded object.
  assert_true(
    admit(replace("version", Some("actql-remote-run-materials")), issued_cid)
    is Err(MaterialsMalformed),
  )
  assert_true(
    admit(run_materials_json([..fields, ("extra", Some("field"))]), issued_cid)
    is Err(MaterialsMalformed),
  )
  assert_true(
    admit("[".repeat(100000) + "]".repeat(100000), issued_cid)
    is Err(MaterialsMalformed),
  )
  assert_true(
    admit(
      replace("check_environment_cid", Some("sha256:" + "0".repeat(64))),
      issued_cid,
    )
    is Err(MaterialsEnvironment),
  )
}
