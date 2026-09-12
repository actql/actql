///|
fn canonical_fixture(value : Json) -> String raise {
  @canonical.stringify_value(
    @canonical.from_json(value, 10000, 100, 100000),
    100000,
    10000,
    100,
  )
}

///|
fn sealed_fixture(value : Json, self_field : String) -> String raise {
  let id = "sha256:" + @sha.hex(@utf8.encode(canonical_fixture(value)))
  guard value is Object(fields) else { abort("object fixture") }
  fields[self_field] = Json::string(id)
  canonical_fixture(value)
}

///|
fn mutate_reference_fixture(
  value : Json,
  path : Array[String],
  index : Int,
  replacement : Json?,
) -> Unit raise {
  let name = path[index]
  if value is Object(fields) {
    if index + 1 == path.length() {
      match replacement {
        Some(v) => fields[name] = v
        None => ignore(fields.remove(name))
      }
    } else {
      mutate_reference_fixture(fields[name], path, index + 1, replacement)
    }
  } else if value is Array(items) {
    assert_eq(name, "0")
    mutate_reference_fixture(items[0], path, index + 1, replacement)
  } else {
    abort("invalid fixture path")
  }
}

///|
fn reference_fixture(
  path? : Array[String] = [],
  replacement? : Json? = None,
  misplaced? : Bool = false,
  modes? : Int = 1,
  policy_body? : Json? = None,
  unused_policy? : Json? = None,
  bodies? : Map[String, Json] = Map([]),
  unused_value? : Json? = None,
  unused_carrier? : Json? = None,
  complete_view? : Bool = false,
  carrier? : String = "relation",
) -> CatalogContents raise {
  let kinds = [
    "request_schema", "carrier_schema", "carrier_facts", "pushdown", "checkpoint",
    "command_input", "command_output", "idempotency_key", "reconciliation", "poll",
    "cancel", "lookup_request_key", "lookup_batch_request", "lookup_response_key",
    "request_data_handling", "data_policy", "provider_execution_capability",
  ]
  let contracts = []
  let identities : Map[String, String] = Map([])
  let refs : Map[String, Json] = Map([])
  for kind in kinds {
    let core = @json.parse(
      "{\"schema\":\"actql.contract/0.1\",\"id\":\"" +
      kind +
      "\",\"kind\":\"" +
      kind +
      "\",\"version\":\"external\",\"body\":{\"literal\":{\"$param\":\"business\"}}}",
    )
    if kind == "data_policy" && policy_body is Some(body) {
      guard core is Object(fields) else { abort("policy fixture") }
      fields["body"] = body
    }
    if bodies.get(kind) is Some(body) {
      guard core is Object(fields) else { abort("value contract fixture") }
      fields["body"] = body
    }
    let wire = sealed_fixture(core, "cid")
    contracts.push(wire)
    guard @json.parse(wire) is Object(fields) else { abort("envelope fixture") }
    guard fields["cid"] is String(identity) else { abort("identity fixture") }
    identities[wire] = identity
    refs[kind] = Json::object(
      Map([
        ("id", Json::string(kind)),
        ("version", Json::string("external")),
        ("cid", fields["cid"]),
      ]),
    )
  }
  if unused_policy is Some(body) {
    let core = @json.parse(
      "{\"schema\":\"actql.contract/0.1\",\"id\":\"unused-policy\",\"kind\":\"data_policy\",\"version\":\"external\"}",
    )
    guard core is Object(fields) else { abort("unused policy fixture") }
    fields["body"] = body
    let wire = sealed_fixture(core, "cid")
    guard fields["cid"] is String(identity) else { abort("identity fixture") }
    contracts.push(wire)
    identities[wire] = identity
  }
  for
    (kind, unused) in [
      ("checkpoint", unused_value),
      ("carrier_schema", unused_carrier),
    ] {
    if unused is Some(body) {
      let unused_id = if kind == "checkpoint" {
        "unused-value"
      } else {
        "unused-carrier"
      }
      let core = @json.parse(
        "{\"schema\":\"actql.contract/0.1\",\"id\":\"" +
        unused_id +
        "\",\"kind\":\"" +
        kind +
        "\",\"version\":\"external\"}",
      )
      guard core is Object(fields) else { abort("unused value fixture") }
      fields["body"] = body
      let wire = sealed_fixture(core, "cid")
      guard fields["cid"] is String(identity) else { abort("identity fixture") }
      contracts.push(wire)
      identities[wire] = identity
    }
  }
  contracts.sort_by((a, b) => identities[a].compare(identities[b]))
  let mode = "{\"mode\":\"snapshot\",\"bounded\":true,\"checkpoint\":{\"value_schema\":\"@checkpoint\",\"expiration_schema\":\"@checkpoint\"},\"delivery\":{\"lease\":{\"expiration_schema\":\"@checkpoint\"}}}"
  let modes_text = Array::make(modes, mode).join(",")
  let mut text = "{\"view\":{\"schema\":\"actql.source_view/0.1\",\"connector_id\":\"example\",\"connector_version\":\"external-7\",\"resource_kind\":\"record\",\"view_id\":\"main\",\"view_version\":\"external\",\"acquisition\":{\"request_schema\":\"@request_schema\",\"batching\":{\"request_key_schema\":\"@lookup_request_key\",\"batch_request_schema\":\"@lookup_batch_request\",\"response_key_schema\":\"@lookup_response_key\"},\"modes\":[" +
    modes_text +
    "]},\"request_processing\":{\"data_handling\":{\"contract\":\"@request_data_handling\"},\"provider_execution_capability\":\"@provider_execution_capability\"},\"output\":{\"schema\":\"@carrier_schema\",\"facts\":\"@carrier_facts\",\"data_policy\":\"@data_policy\"},\"pushdown\":{\"contract\":\"@pushdown\"}},\"command\":{\"schema\":\"actql.command_contract/0.1\",\"command_id\":\"command\",\"connector_id\":\"example\",\"version\":\"external\",\"input_schema\":\"@command_input\",\"output_schema\":\"@command_output\",\"idempotency\":{\"key_schema\":\"@idempotency_key\"},\"reconciliation\":\"@reconciliation\",\"poll\":\"@poll\",\"cancel\":\"@cancel\"}}"
  for kind in kinds {
    let token = "\"@" + kind + "\""
    while text.contains(token) {
      text = text.replace(old=token, new=canonical_fixture(refs[kind]))
    }
  }
  let value = @json.parse(text)
  if complete_view {
    guard value is Object(fields) else { abort("fixture") }
    let mut view_text =
      #|{"schema":"actql.source_view/0.1","connector_id":"example","connector_version":"external-7","resource_kind":"record","view_id":"main","view_version":"external","acquisition":{"kind":"scan","authority":"read_metadata","request_schema":"@request_schema","modes":[{"mode":"snapshot","bounded":true}],"default_mode":"snapshot"},"request_processing":{"mutates_business_state":false},"output":{"carrier":"@carrier","schema":"@carrier_schema","facts":"@carrier_facts","data_policy":"@data_policy"},"pushdown":{"contract":"@pushdown","operations":[]}}
    for kind in kinds {
      view_text = view_text.replace(
        old="\"@" + kind + "\"",
        new=canonical_fixture(refs[kind]),
      )
    }
    view_text = view_text.replace(
      old="\"@carrier\"",
      new=canonical_fixture(Json::string(carrier)),
    )
    fields["view"] = @json.parse(view_text)
  }
  if !path.is_empty() {
    mutate_reference_fixture(value, path, 0, replacement)
  }
  guard value is Object(fields) else { abort("fixture") }
  let view = sealed_fixture(fields["view"], "contract_cid")
  let command = sealed_fixture(fields["command"], "contract_cid")
  let catalogs = if misplaced {
    [
      catalog_fixture("example", [], views=[view], commands=[command]),
      catalog_fixture("other", contracts),
    ]
  } else {
    [catalog_fixture("example", contracts, views=[view], commands=[command])]
  }
  match
    check_catalog_contents(
      catalog_environment(catalogs, contracts, views=[view], commands=[command]),
      caps(),
    ) {
    Ok(v) => v
    Err(e) => {
      debug_inspect(e, content="valid Catalog")
      abort("invalid Catalog fixture")
    }
  }
}

///|
fn reference_caps() -> ReferenceLimits {
  { max_work: 1000000, max_references: 10000, }
}
