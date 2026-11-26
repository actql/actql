///|
fn tuple_plan_fixture_json(text : String) -> @json.CanonicalValue raise {
  let parsed = @source.parse_json(text, {
    max_input_bytes: 16000,
    max_nodes: 1000,
    max_depth: 32,
  }).unwrap()
  @json.from_source(parsed, 1000, 32, 16000)
}

///|
fn tuple_plan_fixture_seal(
  text : String,
  field : String,
) -> (String, String) raise {
  let value = tuple_plan_fixture_json(text)
  let cid = @json.cid_value(value, 16000, 1000, 32)
  let admitted = @json.object_with_string_field(value, field, cid).unwrap()
  (@json.stringify_value(admitted, 16000, 1000, 32), cid)
}

///|
fn tuple_plan_fixture_mappings(
  second_type : String,
) -> @environment.MappingContractShapes raise {
  let schema =
    #|{"additional_properties":false,"fields":{"a":{"nullable":false,"type":"int64"},"b":{"nullable":false,"type":"@second"}},"nullable":false,"type":"object"}
  let schema = schema.replace(old="@second", new=second_type)
  let contracts : Array[(String, String)] = []
  let refs : Map[String, String] = Map([])
  for
    (kind, body) in [
      ("carrier_schema", schema),
      (
        "carrier_facts", "{\"relation_keys\":{\"candidate_keys\":[[\"a\",\"b\"]]}}",
      ),
      ("request_schema", "{\"type\":\"number\",\"nullable\":false}"),
      ("pushdown", "{}"),
      (
        "data_policy", "{\"version\":\"actql-source-data-policy/0.1\",\"classification\":\"internal\",\"source_ref\":\"connector://example/record#records\"}",
      ),
    ] {
    let (wire, cid) = tuple_plan_fixture_seal(
      "{\"schema\":\"actql.contract/0.1\",\"id\":\"" +
      kind +
      "\",\"kind\":\"" +
      kind +
      "\",\"version\":\"v1\",\"body\":" +
      body +
      "}",
      "cid",
    )
    contracts.push((cid, wire))
    refs[kind] = "{\"cid\":\"" +
      cid +
      "\",\"id\":\"" +
      kind +
      "\",\"version\":\"v1\"}"
  }
  contracts.sort_by((a, b) => a.0.compare(b.0))
  let contract_list = "[" + contracts.map(pair => pair.1).join(",") + "]"
  let mut view =
    #|{"schema":"actql.source_view/0.1","connector_id":"example","connector_version":"v1","resource_kind":"record","view_id":"records","view_version":"v1","acquisition":{"kind":"scan","authority":"read_metadata","request_schema":"@request_schema","modes":[{"mode":"snapshot","bounded":true}],"default_mode":"snapshot"},"request_processing":{"mutates_business_state":false},"output":{"carrier":"relation","schema":"@carrier_schema","facts":"@carrier_facts","data_policy":"@data_policy"},"pushdown":{"contract":"@pushdown","operations":[]}}
  for kind, reference in refs {
    view = view.replace(old="\"@" + kind + "\"", new=reference)
  }
  let (view, _) = tuple_plan_fixture_seal(view, "contract_cid")
  let (catalog, _) = tuple_plan_fixture_seal(
    "{\"commands\":[],\"connector_id\":\"example\",\"connector_version\":\"v1\",\"contracts\":" +
    contract_list +
    ",\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[" +
    view +
    "]}",
    "catalog_cid",
  )
  let connector = "{\"connector\":\"example\",\"connector_id\":\"example\",\"connector_version\":\"v1\"}"
  let mapping =
    #|{"connector_manifest_cid":"@connector","conversions":[],"mapping_ref":"mapping:example.record.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"delete","selector_class":"match_tuple","write_fields":[],"permissions":["scope:delete"]}],"primary_identity":{"kind":"tuple","fields":["a","b"]},"required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{},"schema":"actql.mapping_contract/0.2","target_ref":"connector://example/record","target_schema":@schema,"target_schema_identity":"@identity","version":"v1","writable_fields":[]}
  let (mapping, _) = tuple_plan_fixture_seal(
    mapping
    .replace(
      old="@connector",
      new="sha256:" + @sha.hex(@utf8.encode(connector)),
    )
    .replace(old="@schema", new=schema)
    .replace(old="@identity", new="sha256:" + @sha.hex(@utf8.encode(schema))),
    "mapping_contract_cid",
  )
  let registry_wires = contracts.map(pair => {
    (@sha.hex(@utf8.encode(pair.1)), pair.1)
  })
  registry_wires.sort_by((a, b) => a.0.compare(b.0))
  let (wire, cid) = tuple_plan_fixture_seal(
    "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[" +
    catalog +
    "],\"connector_manifest\":{\"connectors\":[" +
    connector +
    "],\"version\":\"actql-connectors/0.1\"},\"contract_registry\":" +
    "[" +
    registry_wires.map(pair => pair.1).join(",") +
    "]" +
    ",\"host_policy_profile\":{},\"mapping_contracts\":[" +
    mapping +
    "],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[" +
    view +
    "],\"version\":\"actql-check-environment/0.1\"}",
    "evidence_bundle_cid",
  )
  let limits : @environment.Limits = {
    max_bytes: 16000,
    max_nodes: 1000,
    max_depth: 32,
    max_members: 40,
  }
  let original = @environment.read(@utf8.encode(wire), cid, limits).unwrap()
  let registry = @environment.check_contract_registry(original, limits).unwrap()
  let catalog = @environment.check_catalog_contents(registry, limits).unwrap()
  let references = @environment.check_catalog_references(catalog, {
    max_work: 10000,
    max_references: 100,
  }).unwrap()
  let policies = @environment.check_source_data_policies(references, {
    max_work: 10000,
    max_policies: 4,
  }).unwrap()
  let values = @environment.check_protocol_value_contracts(policies, {
    max_envelopes: 10,
    contracts: { max_nodes: 1000, max_depth: 32, max_text_bytes: 16000, },
  }).unwrap()
  let shapes = @environment.check_source_view_shapes(values, {
    max_views: 4,
    max_work: 10000,
  }).unwrap()
  let modes = @environment.check_source_read_modes(shapes, 10000).unwrap()
  let carriers = @environment.check_carrier_schemas(modes, {
    max_schemas: 4,
    max_work: 10000,
    bodies: { max_nodes: 1000, max_bytes: 16000, max_depth: 32, },
  }).unwrap()
  @environment.check_mapping_contract_shapes(
    original,
    limits,
    10000,
    carriers=Some(carriers),
  ).unwrap()
}

///|
fn tuple_plan_fixture_rules(
  second_type : String,
  first_target? : String = "a",
  second_target? : String = "b",
) -> Result[EffectMappingRules, EffectMappingRuleIssue] raise {
  let effect =
    #|{"member":{"delete":{"target":"connector://example/record","mapping":"mapping:example.record.v1","from":{"result":"r"},"match_tuple":[{"target_field":"@first","result_field":"amount"},{"target_field":"@second","result_field":"amount"}]}}}
  let (checked, headers) = effect_binding_inputs(
    effect
    .replace(old="@first", new=first_target)
    .replace(old="@second", new=second_target),
    amount_type=Some(@contract.primitive(Signed64Type, nullable=false)),
    header_work=64,
  )
  let bindings = bind_effect_results(headers, checked, 64).unwrap()
  let shapes = bind_effect_mapping_shapes(
    bindings,
    tuple_plan_fixture_mappings(second_type),
    10,
  ).unwrap()
  bind_effect_mapping_rules(shapes, 100)
}

///|
test "checked tuple Plan and row retain the same repeated Result field in target order" {
  let rule = effect_mapping_rule_at(
    tuple_plan_fixture_rules("int64").unwrap(),
    0,
  ).unwrap()
  assert_eq(prepare_effect_plan_terminal(rule, 1).unwrap_err(), FieldLimit)
  let terminal = prepare_effect_plan_terminal(rule, 2).unwrap().unwrap()
  let out = @encode.writer(1024, 50, 12)
  emit_effect_plan_pipeline(terminal, out)
  let expected =
    #|{"output":"intent","sources":{"r":{"sort":"relation"}},"steps":[{"id":"intent","in":["r"],"op":"EFFECT.plan","params":{"entity":"connector://example/record","op":"delete","selector":"byTuple","selector_tuple":[{"result_field":"amount","target_field":"a","value_type":"int64"},{"result_field":"amount","target_field":"b","value_type":"int64"}]}}],"version":"aoa-pipeline/0.1"}
  assert_eq(@encode.finish(out), expected)
  let row = effect_plan_test_row("{\"amount\":\"9007199254740993\"}")
  let work = 108
  let projection = project_effect_plan_row(terminal, row, 0, 2, work).unwrap()
  let out = @encode.writer(64, 3, 2)
  emit_effect_plan_row_selector(projection, out)
  assert_eq(@encode.finish(out), "[\"9007199254740993\",\"9007199254740993\"]")
  assert_eq(
    project_effect_plan_row(terminal, row, 0, 2, work - 1).unwrap_err(),
    WorkLimit,
  )
  for
    wire in [
      "{\"amount\":null}", "{\"amount\":1}", "{\"amount\":\"01\"}", "{\"amount\":\"9223372036854775808\"}",
    ] {
    assert_eq(
      project_effect_plan_row(terminal, effect_plan_test_row(wire), 0, 2, 256).unwrap_err(),
      InvalidTupleComponent("a"),
    )
  }
}

///|
test "reused Result field must independently match each checked target type and order" {
  let mismatch = tuple_plan_fixture_rules("string").unwrap_err()
  assert_eq(
    effect_mapping_rule_issue_kind(mismatch),
    IncompatibleSourceType("b"),
  )
  let reversed = tuple_plan_fixture_rules(
    "int64",
    first_target="b",
    second_target="a",
  ).unwrap_err()
  assert_eq(effect_mapping_rule_issue_kind(reversed), InvalidBody)
}
