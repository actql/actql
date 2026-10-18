///|
// Literal public document and independent canonical identities. Provider/policy
// DATA below is an explicit fixture, never an installation or permission.
fn public_signed64_task_document() -> String {
  (
    #|# model-tasks/churn-risk.v1.yaml
    #|task: model-task:churn-risk.v1
    #|model: { provider: openai, name: "<model id>" }   # optional
    #|input:
    #|  notes: string
    #|  active_users: int64
    #|  trend: string
    #|instructions: |
    #|  From the account notes, the number of active users and the usage trend,
    #|  rate the churn risk as low, medium or high and explain why in one line.
    #|  Do not assume facts that are not in the input.
    #|output:
    #|  level: {type: string, enum: [low, medium, high]}
    #|  reason: string
    #|limits:
    #|  max_items: 5000
    #|  max_output_tokens: 200
  )
}

///|
fn public_signed64_task_limits() -> @environment.ModelTaskLimits {
  {
    bodies: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_members: 100,
    },
    contracts: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
    max_work: 10000000,
  }
}

///|
fn public_signed64_task_normalized() -> @environment.NormalizedPublicModelTask raise {
  let limits = public_signed64_task_limits()
  let declaration = @environment.read_public_model_task_document(
    public_signed64_task_document(),
    "yaml",
    limits,
  ).unwrap()
  let profile = @environment.read_model_provider_defaults_configuration(
    @utf8.encode(
      (
        #|{"model_defaults":{"default_model":"<model id>","models":[{"data_handling":{"body":{"accepted_classifications":["public","internal"],"allowed_regions":["explicit-fixture-region"],"retention":"none","training_use":"forbidden"},"cid":"sha256:e04bf6dc7a5a983f7813f491c3c6efa067b25ca21647799c804b456f0e2e461e","id":"signed64-public-task-fixture-policy","kind":"request_data_handling","schema":"actql.contract/0.1","version":"explicit-fixture-revision"},"generation_config":{"max_output_tokens":100,"temperature":0,"top_p":1},"model":"<model id>"}]}}
      ),
    ),
    limits.bodies,
    limits.max_work,
  ).unwrap().0.unwrap()
  let resolved = @environment.resolve_model_provider_defaults(
    profile,
    Some(
      @environment.public_model_task_declaration_model(declaration).unwrap().1,
    ),
    @environment.public_model_task_declaration_limits(declaration).1,
    limits.max_work,
  ).unwrap()
  assert_eq(
    @environment.public_model_task_declaration_identity(declaration),
    ("model-task:churn-risk.v1", "model-task:churn-risk.v1"),
  )
  assert_eq(
    @environment.public_model_task_declaration_limits(declaration),
    (Some(5000L), Some(200L)),
  )
  let (input, output) = @environment.public_model_task_declaration_contracts(
    declaration,
  )
  assert_eq(
    @environment.public_model_task_contract_schema(input),
    (
      "{\"additional_properties\":false,\"fields\":{\"active_users\":{\"nullable\":false,\"type\":\"int64\"},\"notes\":{\"nullable\":false,\"type\":\"string\"},\"trend\":{\"nullable\":false,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"}",
      "sha256:735d8d91c33e902ce54d02b0f48fac4af82c3e3fd7c3fdc076676ce015d1110b",
    ),
  )
  assert_eq(
    @environment.public_model_task_contract_schema(output),
    (
      "{\"additional_properties\":false,\"fields\":{\"level\":{\"enum\":[\"low\",\"medium\",\"high\"],\"nullable\":false,\"type\":\"string\"},\"reason\":{\"nullable\":false,\"type\":\"string\"}},\"nullable\":false,\"type\":\"object\"}",
      "sha256:c7e6dd2e3b269a94de71231ced9f3654ae5cc25e71f2f68ef05abae1f7d53005",
    ),
  )
  let normalized = @environment.normalize_public_model_task(
    declaration, profile, resolved, "openai", limits,
  ).unwrap()
  let materials = @environment.normalized_public_model_task_materials(
    normalized,
  )
  assert_eq(
    materials.0,
    (
      #|{"authored_model_selector":"<model id>","connector_id":"openai","contract_cid":"sha256:f2eee3c10b5c3cf1e42cc145d6f367cb3c731b9cc5358144fa2be365c082e8ee","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["explicit-fixture-region"],"contract_cid":"sha256:e04bf6dc7a5a983f7813f491c3c6efa067b25ca21647799c804b456f0e2e461e","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":200,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"active_users":{"nullable":false,"type":"int64"},"notes":{"nullable":false,"type":"string"},"trend":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:735d8d91c33e902ce54d02b0f48fac4af82c3e3fd7c3fdc076676ce015d1110b","max_items":5000,"output_contract":{"additional_properties":false,"fields":{"level":{"enum":["low","medium","high"],"nullable":false,"type":"string"},"reason":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:c7e6dd2e3b269a94de71231ced9f3654ae5cc25e71f2f68ef05abae1f7d53005","prompt_template_cid":"sha256:a6b2ea310b573f077d8c34651dbdcac233e71f32d10e1dd76036f98f37dadc4c","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:churn-risk.v1","task_kind":"structured_generate","tool_policy":"none","version":"model-task:churn-risk.v1"}
    ),
  )
  assert_eq(
    materials.1,
    "sha256:f2eee3c10b5c3cf1e42cc145d6f367cb3c731b9cc5358144fa2be365c082e8ee",
  )
  assert_eq(
    materials.2,
    (
      #|{"payload":{"format":"actql.openai_chat_prompt/0.1","instructions":"From the account notes, the number of active users and the usage trend,\nrate the churn risk as low, medium or high and explain why in one line.\nDo not assume facts that are not in the input.\n"},"self_cid":"sha256:a6b2ea310b573f077d8c34651dbdcac233e71f32d10e1dd76036f98f37dadc4c","version":"actql-model-prompt/0.1"}
    ),
  )
  assert_eq(
    materials.3,
    "sha256:a6b2ea310b573f077d8c34651dbdcac233e71f32d10e1dd76036f98f37dadc4c",
  )
  normalized
}

///|
fn public_signed64_task_environment() -> @check.CheckEnvironment raise {
  let limits = public_signed64_task_limits()
  let base = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:189e570b7553c768f55852ec2f1a36e1386c4c4118ca62efc8578d028e40c648","commands":[],"connector_id":"salesforce","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]},{"catalog_cid":"sha256:a64dba676c044a2a74a4eec6594a8213a8402212df96dd58c31755d0ff82863f","commands":[],"connector_id":"snowflake","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"salesforce","connector_id":"salesforce","connector_version":"fixture"},{"connector":"snowflake","connector_id":"snowflake","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:af39fba1d1e1db2421bd5e3fedd065e0e98455fe865a3f54ef3d252bc175d192","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:9a6a8e56c272ccc2e238e67707085a0ba0eedadee6cbe701670c830ab704459a","conversions":[],"mapping_contract_cid":"sha256:f244d72c15ceb372a039ae524526709902dd9eb64b2ca965f82aade4d82e1a38","mapping_ref":"mapping:salesforce.churn.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Churn_Risk__c","Risk_Reason__c"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Churn_Risk__c":{"field":"Churn_Risk__c","null_behavior":"reject"},"Risk_Reason__c":{"field":"Risk_Reason__c","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://salesforce/Account","target_schema":{"additional_properties":false,"fields":{"Churn_Risk__c":{"nullable":false,"type":"string"},"Id":{"nullable":false,"type":"string"},"Risk_Reason__c":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:62b1bb5af1125a1bd7c8ef823b817937173ea48b09378e78a55d0beb340e7fe8","version":"fixture","writable_fields":["Churn_Risk__c","Risk_Reason__c"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:af39fba1d1e1db2421bd5e3fedd065e0e98455fe865a3f54ef3d252bc175d192",
    limits.bodies,
  ).unwrap()
  let (wire, cid, _) = @environment.project_public_model_task_environment(
    base,
    [public_signed64_task_normalized()],
    limits,
  ).unwrap()
  let original = @environment.read(@utf8.encode(wire), cid, limits.bodies).unwrap()
  let tasks = @environment.check_model_tasks(original, limits).unwrap()
  let selected = @environment.resolve_model_task(
    tasks, "model-task:churn-risk.v1",
  ).unwrap()
  assert_eq(
    @environment.model_task_schema_cids(selected),
    (
      "sha256:735d8d91c33e902ce54d02b0f48fac4af82c3e3fd7c3fdc076676ce015d1110b",
      "sha256:c7e6dd2e3b269a94de71231ced9f3654ae5cc25e71f2f68ef05abae1f7d53005",
    ),
  )
  assert_eq(
    @environment.model_task_identity(selected).2,
    "sha256:f2eee3c10b5c3cf1e42cc145d6f367cb3c731b9cc5358144fa2be365c082e8ee",
  )
  @check.checking_environment(
    original,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    model_tasks=Some(tasks),
  )
}

///|
fn public_signed64_hero_context(
  environment : @check.CheckEnvironment,
  kind? : String = "int64",
) -> Context {
  let scalar = if kind == "decimal" {
    "{\"nullable\":false,\"precision\":19,\"scale\":0,\"type\":\"decimal\"}"
  } else {
    "{\"nullable\":false,\"type\":\"" + kind + "\"}"
  }
  let entries = [
    (
      "salesforce.accounts", "{\"carrier\":\"relation\",\"primary_key\":[\"id\"],\"schema\":{\"description\":{\"nullable\":false,\"type\":\"string\"},\"id\":{\"nullable\":false,\"type\":\"string\"}}}",
    ),
    (
      "snowflake.usage_30d",
      "{\"carrier\":\"relation\",\"primary_key\":[\"account_id\"],\"schema\":{\"account_id\":{\"nullable\":false,\"type\":\"string\"},\"active_users\":" +
      scalar +
      ",\"trend\":{\"nullable\":false,\"type\":\"string\"}}}",
    ),
  ]
  {
    ..readme_hero_context(environment),
    inputs: entries.map(entry => {
      relation: @query.parse_relation_path(entry.0, syntax_limits().lexical).unwrap(),
      name: entry.0.replace(old=".", new="_"),
      source: Captured(
        @wire.admit(
          @source.parse_json(entry.1, construction_limits().source.source).unwrap(),
          construction_limits().source.tree,
        ).unwrap(),
      ),
      visible_fields: if entry.0 == "salesforce.accounts" {
        ["description", "id"]
      } else {
        ["account_id", "active_users", "trend"]
      },
      graph_bindings: [],
    }),
  }
}

///|
test "public guide Signed64 Task and enum retain original full canonical materials" {
  let normalized = public_signed64_task_normalized()
  assert_true(@environment.normalized_public_model_task_usage(normalized) > 0)
  let environment = public_signed64_task_environment()
  let task = @environment.resolve_model_task(
    @check.checking_environment_model_tasks(environment).unwrap(),
    "model-task:churn-risk.v1",
  ).unwrap()
  assert_eq(@environment.model_task_max_items(task), Some(5000L))
  assert_eq(
    @environment.model_task_generation_config(task).unwrap().max_output_tokens,
    200L,
  )
}

///|
test "README SQL Effects preserves Signed64 and enum through actual public Task normalization" {
  let environment = public_signed64_task_environment()
  let context = public_signed64_hero_context(environment)
  let publication = readme_hero_publication(environment)
  let source = readme_hero_text()
  let explicit = source.replace(
    old="INPUT (notes, active_users, trend)",
    new="ITEM KEY (id) INPUT (notes = notes, active_users = active_users, trend = trend) KEEP (id, notes, active_users, trend)",
  )
  let actual = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    context,
    construction_limits(),
    update_targets=Some(publication),
  ).unwrap()
  let expanded = compile(
    @query.parse_query(explicit, syntax_limits()).unwrap(),
    context,
    construction_limits(),
    update_targets=Some(publication),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expanded))
  let a = readme_hero_checked_effect(actual, environment)
  let b = readme_hero_checked_effect(expanded, environment)
  assert_shorthand_checked_identity(
    @check.effect_program_static_checked_computation(a),
    @check.effect_program_static_checked_computation(b),
  )
  assert_eq(
    @check.effect_program_static_definition_cid(a),
    @check.effect_program_static_definition_cid(b),
  )
  assert_eq(@program.exports(actual).map(value => value.0), ["updates"])
}

///|
test "SQL and AQL Signed64 public INFER use the same checked computation" {
  let environment = public_signed64_task_environment()
  let context = public_signed64_hero_context(environment)
  let sql = "SELECT a.id AS id, a.description AS notes, u.active_users, u.trend FROM salesforce.accounts AS a JOIN snowflake.usage_30d AS u ON a.id=u.account_id |> INFER `model-task:churn-risk.v1` INPUT (notes, active_users, trend) AS risk |> SELECT id, risk.value.level AS level"
  let aql = "FROM salesforce.accounts AS a |> JOIN snowflake.usage_30d AS u ON a.id=u.account_id |> SELECT a.id AS id, a.description AS notes, u.active_users, u.trend |> INFER `model-task:churn-risk.v1` INPUT (notes, active_users, trend) AS risk |> SELECT id, risk.value.level AS level"
  let prepare = fn(source) {
    compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
  }
  let a = prepare(sql)
  let b = prepare(aql)
  assert_eq(semantic(a), semantic(b))
  assert_shorthand_checked_identity(
    check_shorthand_identity_program(a, environment),
    check_shorthand_identity_program(b, environment),
  )
}

///|
test "public Signed64 INFER refuses Number Decimal and Text inputs without promotion" {
  let environment = public_signed64_task_environment()
  let source = "SELECT a.id AS id, a.description AS notes, u.active_users, u.trend FROM salesforce.accounts AS a JOIN snowflake.usage_30d AS u ON a.id=u.account_id |> INFER `model-task:churn-risk.v1` INPUT (notes, active_users, trend) AS risk"
  for kind in ["number", "decimal", "string"] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      public_signed64_hero_context(environment, kind~),
      construction_limits(),
    ).unwrap()
    guard @check.check_parsed(program, environment, None, check_limits())
      is Rejected(error) else {
      fail("non-Signed64 public input admitted: " + kind)
    }
    match @check.diagnostic_cause(error) {
      Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
        assert_eq(
          issue.kind,
          @pipeline.Infer(@evidence.Expression(@typing.TypeMismatch("int64"))),
        )
      other => raise other
    }
  }
}
