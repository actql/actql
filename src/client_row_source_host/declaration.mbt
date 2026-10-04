// A provider-neutral static declaration for installed row sources: the
// Connector Catalog, SourceViews and Check Environment evidence members of
// views whose fields have fixed ActQL value types. A connector supplies the
// view specification from its own declaration; the common runtime generates
// (and on load regenerates) the canonical contracts, so the Host never trusts
// a connector-computed CID.

///|
pub(all) struct RowField {
  name : String
  value_type : String
  nullable : Bool
} derive(Eq, Debug)

///|
pub(all) struct RowViewSpec {
  resource : String
  resource_kind : String
  fields : Array[RowField]
} derive(Eq, Debug)

///|
pub struct RowDeclaredView {
  resource : String
  source_ref : String
  view_cid : String
  fields : Array[String]
  carrier_schema_cid : String
  data_policy_cid : String
}

///|
pub struct RowDeclaration {
  connector_id : String
  connector_registration : String
  connector_version : String
  catalog : String
  catalog_cid : String
  contracts : Array[String]
  views : Array[RowDeclaredView]
  view_bodies : Array[String]
  manifest_entry : String
  manifest_entry_cid : String
}

///|
pub(all) enum RowDeclarationIssue {
  InvalidConnectorId
  InvalidRegistration
  InvalidView
  UnsupportedType(String)
  DuplicateName(String)
  OutputLimit
} derive(Eq, Debug)

///|
pub(all) struct RowDeclarationLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_views : Int
  max_fields : Int
} derive(Eq, Debug)

///|
fn valid_connector_id(value : String) -> Bool {
  if value.length() == 0 || value.length() > 128 || value.contains("//") {
    return false
  }
  for index, character in value {
    let alnum = (character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9')
    if !alnum &&
      (
        index == 0 ||
        !(character == '.' ||
        character == '_' ||
        character == '-' ||
        character == '/')
      ) {
      return false
    }
  }
  !value.has_suffix("/")
}

///|
fn valid_name(value : String, max_units : Int) -> Bool {
  if value.length() == 0 || value.length() > max_units {
    return false
  }
  for index, character in value {
    let alpha = (character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      character == '_'
    let digit = character >= '0' && character <= '9'
    if !(alpha || (index > 0 && digit)) {
      return false
    }
  }
  true
}

///|
/// Canonical key order compares UTF-16 code units, not length.
fn key_before(left : String, right : String) -> Bool {
  let shorter = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index in 0..<shorter {
    let a = left.code_unit_at(index)
    let b = right.code_unit_at(index)
    if a != b {
      return a < b
    }
  }
  left.length() < right.length()
}

///|
fn object(entries : Array[(String, Json)]) -> Json {
  let sorted = entries.copy()
  sorted.sort_by((a, b) => {
    if key_before(a.0, b.0) {
      -1
    } else if key_before(b.0, a.0) {
      1
    } else {
      0
    }
  })
  let map : Map[String, Json] = Map([])
  for entry in sorted {
    map[entry.0] = entry.1
  }
  Json::object(map)
}

///|
fn canonical_text(
  value : Json,
  limits : RowDeclarationLimits,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  @encode.emit_json(value, writer)
  @encode.finish(writer)
}

///|
fn canonical_cid(
  value : Json,
  limits : RowDeclarationLimits,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.hashing_writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  @encode.emit_json(value, writer)
  "sha256:" + @encode.finish_hash(writer)
}

///|
/// A self-addressed entry_: the CID excludes only its own key.
fn seal(
  entries : Array[(String, Json)],
  key : String,
  limits : RowDeclarationLimits,
) -> (Json, String) raise @encode.EncodeFailure {
  let cid = canonical_cid(object(entries), limits)
  (object([..entries, (key, Json::string(cid))]), cid)
}

///|
fn ref_cid(reference : Json) -> String {
  match reference {
    Object(entries) =>
      match entries.get("cid") {
        Some(String(cid)) => cid
        _ => ""
      }
    _ => ""
  }
}

///|
/// The ActQL value types a row field may declare: exact JSON spellings that
/// value admission accepts without provider-specific conversion.
fn supported_type(value_type : String) -> Bool {
  ["string", "number", "boolean", "timestamp", "date"].contains(value_type)
}

///|
priv struct Envelopes {
  prefix : String
  version : String
  limits : RowDeclarationLimits
  texts : Array[String]
  values : Array[Json]
  cids : Array[String]
}

///|
fn Envelopes::add(
  self : Envelopes,
  name : String,
  kind : String,
  body : Json,
) -> Json raise @encode.EncodeFailure {
  let id = self.prefix + "/" + name
  let (envelope, cid) = seal(
    [
      ("schema", "actql.contract/0.1".to_json()),
      ("id", id.to_json()),
      ("version", self.version.to_json()),
      ("kind", kind.to_json()),
      ("body", body),
    ],
    "cid",
    self.limits,
  )
  if !self.cids.contains(cid) {
    self.cids.push(cid)
    self.values.push(envelope)
    self.texts.push(canonical_text(envelope, self.limits))
  }
  object([
    ("id", id.to_json()),
    ("version", self.version.to_json()),
    ("cid", cid.to_json()),
  ])
}

///|
/// Generate the declaration of `views` for one installed connector. The
/// registration and revision are the installed implementation's, verified by
/// the Host against the installation; they are not authority here.
pub fn generate_row_declaration(
  connector_id : String,
  connector_registration : String,
  connector_version : String,
  views : Array[RowViewSpec],
  limits : RowDeclarationLimits,
) -> Result[RowDeclaration, RowDeclarationIssue] {
  if !valid_connector_id(connector_id) {
    return Err(InvalidConnectorId)
  }
  if !valid_name(connector_registration, 64) ||
    !connector_version.has_prefix(connector_registration + "/") {
    return Err(InvalidRegistration)
  }
  if views.is_empty() || views.length() > limits.max_views {
    return Err(InvalidView)
  }
  let resources = []
  for view in views {
    if !valid_name(view.resource, 255) ||
      !valid_name(view.resource_kind, 64) ||
      view.fields.is_empty() ||
      view.fields.length() > limits.max_fields {
      return Err(InvalidView)
    }
    if resources.contains(view.resource) {
      return Err(DuplicateName(view.resource))
    }
    resources.push(view.resource)
    let names = []
    for field in view.fields {
      if !valid_name(field.name, 255) {
        return Err(InvalidView)
      }
      if names.contains(field.name) {
        return Err(DuplicateName(field.name))
      }
      if !supported_type(field.value_type) {
        return Err(UnsupportedType(field.value_type))
      }
      names.push(field.name)
    }
  }
  try {
    let envelopes : Envelopes = {
      prefix: connector_id,
      version: connector_version,
      limits,
      texts: [],
      values: [],
      cids: [],
    }
    let declared = []
    let members = []
    for view in views {
      let source_ref = "connector://" +
        connector_id +
        "/" +
        view.resource +
        "#records"
      let name = view.resource + "/records"
      let request = envelopes.add(
        name + "/request",
        "request_schema",
        object([
          ("type", "object".to_json()),
          ("nullable", false.to_json()),
          ("additional_properties", false.to_json()),
          ("fields", object([])),
        ]),
      )
      let row = envelopes.add(
        name + "/row",
        "carrier_schema",
        object([
          ("type", "object".to_json()),
          ("nullable", false.to_json()),
          ("additional_properties", false.to_json()),
          (
            "fields",
            object(
              view.fields.map(field => {
                (
                  field.name,
                  object([
                    ("nullable", Json::boolean(field.nullable)),
                    ("type", field.value_type.to_json()),
                  ]),
                )
              }),
            ),
          ),
        ]),
      )
      let facts = envelopes.add(name + "/facts", "carrier_facts", object([]))
      let policy = envelopes.add(
        name + "/policy",
        "data_policy",
        object([
          ("version", "actql-source-data-policy/0.1".to_json()),
          ("source_ref", source_ref.to_json()),
          ("classification", "unknown".to_json()),
        ]),
      )
      // Only projection is pushed: the common admission keeps the fields the
      // checked input names. Filters, limits and order stay residual.
      let pushdown = envelopes.add(
        name + "/pushdown",
        "pushdown",
        object([
          ("version", "actql-source-view-pushdown/0.1".to_json()),
          ("carrier", "relation".to_json()),
          ("operations", Json::array(["projection".to_json()])),
        ]),
      )
      let (body, view_cid) = seal(
        [
          ("schema", "actql.source_view/0.1".to_json()),
          ("connector_id", connector_id.to_json()),
          ("connector_version", connector_version.to_json()),
          ("resource_kind", view.resource_kind.to_json()),
          ("view_id", "records".to_json()),
          ("view_version", connector_version.to_json()),
          (
            "acquisition",
            object([
              ("kind", "scan".to_json()),
              ("authority", "read_content".to_json()),
              ("request_schema", request),
              (
                "modes",
                Json::array([
                  object([
                    ("mode", "snapshot".to_json()),
                    ("bounded", true.to_json()),
                  ]),
                ]),
              ),
              ("default_mode", "snapshot".to_json()),
            ]),
          ),
          (
            "request_processing",
            object([("mutates_business_state", false.to_json())]),
          ),
          (
            "output",
            object([
              ("carrier", "relation".to_json()),
              ("schema", row),
              ("facts", facts),
              ("data_policy", policy),
            ]),
          ),
          (
            "pushdown",
            object([
              ("contract", pushdown),
              ("operations", Json::array(["projection".to_json()])),
            ]),
          ),
        ],
        "contract_cid",
        limits,
      )
      members.push((view_cid, body))
      declared.push({
        resource: view.resource,
        source_ref,
        view_cid,
        fields: view.fields.map(field => field.name),
        carrier_schema_cid: ref_cid(row),
        data_policy_cid: ref_cid(policy),
      })
    }
    members.sort_by((a, b) => {
      if key_before(a.0, b.0) {
        -1
      } else if key_before(b.0, a.0) {
        1
      } else {
        0
      }
    })
    let indexed = []
    for index, cid in envelopes.cids {
      indexed.push((cid, index))
    }
    indexed.sort_by((a, b) => {
      if key_before(a.0, b.0) {
        -1
      } else if key_before(b.0, a.0) {
        1
      } else {
        0
      }
    })
    let (catalog, catalog_cid) = seal(
      [
        ("schema", "actql.connector_catalog/0.1".to_json()),
        ("connector_id", connector_id.to_json()),
        ("connector_version", connector_version.to_json()),
        ("source_views", Json::array(members.map(entry => entry.1))),
        ("commands", Json::array([])),
        (
          "contracts",
          Json::array(indexed.map(entry => envelopes.values[entry.1])),
        ),
      ],
      "catalog_cid",
      limits,
    )
    let entry = object([
      ("connector", connector_registration.to_json()),
      ("connector_id", connector_id.to_json()),
      ("connector_version", connector_version.to_json()),
    ])
    let ordered = members.map(entry_ => {
      let mut found = declared[0]
      for view in declared {
        if view.view_cid == entry_.0 {
          found = view
        }
      }
      found
    })
    Ok({
      connector_id,
      connector_registration,
      connector_version,
      catalog: canonical_text(catalog, limits),
      catalog_cid,
      contracts: indexed.map(entry => envelopes.texts[entry.1]),
      views: ordered,
      view_bodies: members.map(entry_ => canonical_text(entry_.1, limits)),
      manifest_entry: canonical_text(entry, limits),
      manifest_entry_cid: canonical_cid(entry, limits),
    })
  } catch {
    _ => Err(OutputLimit)
  }
}

///|
pub fn row_declaration_view(
  declaration : RowDeclaration,
  source_ref : String,
) -> RowDeclaredView? {
  for view in declaration.views {
    if view.source_ref == source_ref {
      return Some(view)
    }
  }
  None
}

///|
/// The Check Environment source evidence members of every declared view:
/// its schema snapshot and this implementation's capability (the common
/// broad-receipt process-evidence contract).
pub fn row_declaration_evidence_members(
  declaration : RowDeclaration,
) -> (Array[String], Array[String]) raise @encode.EncodeFailure {
  let schemas = []
  let capabilities = []
  for view in declaration.views {
    let schema = @encode.writer(4096, 64, 8)
    @encode.begin_object(schema)
    for
      (key, value) in [
        ("carrier_schema_contract_cid", view.carrier_schema_cid),
        ("data_classification", "unknown"),
        ("output_carrier", "relation"),
        ("read_mode", "snapshot"),
        ("source_contract_cid", view.view_cid),
        ("source_data_policy_cid", view.data_policy_cid),
        ("source_ref", view.source_ref),
        ("source_view_contract_cid", view.view_cid),
      ] {
      @encode.key(schema, key)
      @encode.string_value(schema, value)
    }
    @encode.end_object(schema)
    schemas.push(@encode.finish(schema))
    let capability = @encode.writer(4096, 64, 8)
    @encode.begin_object(capability)
    @encode.key(capability, "capability_contract_cids")
    @encode.begin_array(capability)
    @encode.string_value(
      capability,
      @planning.query_evidence_contract_identity(),
    )
    @encode.end_array(capability)
    for
      (key, value) in [
        ("read_mode", "snapshot"),
        ("source_contract_cid", view.view_cid),
        ("source_ref", view.source_ref),
        ("source_view_contract_cid", view.view_cid),
      ] {
      @encode.key(capability, key)
      @encode.string_value(capability, value)
    }
    @encode.end_object(capability)
    capabilities.push(@encode.finish(capability))
  }
  (schemas, capabilities)
}
