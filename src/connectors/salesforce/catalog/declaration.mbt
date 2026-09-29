///|
/// What this Connector revision implements. Only `salesforce_implementation`
/// constructs it, from the revision the Site was installed with; a caller
/// cannot assemble capability flags of its own.
pub struct SalesforceImplementation {
  connector_revision : String
  scan_read : Bool
  exact_int_prefilter : Bool
  create : Bool
  update_by_id : Bool
  upsert_by_external_id : Bool
}

///|
pub fn salesforce_implementation(
  connector_revision : String,
) -> SalesforceImplementation? {
  match connector_revision {
    "salesforce/0.1" =>
      Some({
        connector_revision,
        scan_read: true,
        exact_int_prefilter: true,
        create: true,
        update_by_id: true,
        upsert_by_external_id: true,
      })
    _ => None
  }
}

///|
pub(all) enum DeclarationExclusionReason {
  /// The describe does not confirm nullability, so no exact carrier type.
  UnconfirmedNullability
  /// No existing ActQL value contract carries this provider type exactly.
  UnsupportedType(String)
  /// A Number (`double`) whose described precision and scale are missing,
  /// invalid, or above precision 15, so its values are not all recovered
  /// exactly from the reply.
  UnsupportedPrecision(Int?, Int?)
  /// The Resource is not queryable; no SourceView is declared.
  NotQueryable
  /// A required create field cannot be written, or its requirement is
  /// unknown, so no create rule is declared.
  CreateRequirementUnknown(String)
  /// The Resource has no described, non-null `Id` of type `id`.
  NoRecordIdentity
} derive(Eq, Debug)

///|
pub struct DeclarationExclusion {
  resource : String
  field : String
  reason : DeclarationExclusionReason
} derive(Eq, Debug)

///|
pub struct DeclaredView {
  resource : String
  source_ref : String
  view_cid : String
  fields : Array[String]
  // The view's carrier schema and data policy contracts, for its Check
  // Environment schema evidence member.
  carrier_schema_cid : String
  data_policy_cid : String
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
/// What one Resource can write under this declaration: the candidate fields
/// per operation, never an executable Mapping. An executable Mapping is
/// prepared per Effect from these (`prepare_execution_mapping`).
pub struct DeclaredWritable {
  resource : String
  target_ref : String
  create_fields : Array[String]?
  update_fields : Array[String]?
  upsert_fields : Array[String]?
  upsert_keys : Array[String]
  required_fields : Array[String]
  // Writable `datetime` fields: this revision sends whole seconds only and
  // refuses a nonzero millisecond part before sending.
  timestamp_whole_seconds : Array[String]
}

///|
/// Canonical Connector Catalog and Mapping contracts generated from one
/// authorized, selected describe observation. The observation binding stays
/// with the Site; it is not part of the Catalog. Generation is neither
/// current authority nor a grant.
pub struct StaticDeclaration {
  connector_id : String
  connector_version : String
  binding : CatalogObservationBinding
  observation_cid : String
  catalog : String
  catalog_cid : String
  contracts : Array[String]
  views : Array[DeclaredView]
  view_bodies : Array[String]
  writables : Array[DeclaredWritable]
  exclusions : Array[DeclarationExclusion]
  // The described Resources as declared; a later projection must still mean
  // the same for every field it uses.
  resources : Array[ResourceMetadata]
  // This connection's entry of the `actql-connectors/0.1` manifest and its
  // CID, which each execution Mapping names as `connector_manifest_cid`.
  manifest_entry : String
  manifest_entry_cid : String
}

///|
pub(all) enum DeclarationIssue {
  InvalidConnectorId
  InvalidSelection
  ForeignImplementation
  Observation(CatalogObservationIssue)
  OutputLimit
} derive(Eq, Debug)

///|
pub(all) struct DeclarationLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

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
fn sorted_keys(entries : Array[(String, Json)]) -> Array[(String, Json)] {
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
  sorted
}

///|
fn object(entries : Array[(String, Json)]) -> Json {
  let map : Map[String, Json] = Map([])
  for entry in sorted_keys(entries) {
    map[entry.0] = entry.1
  }
  Json::object(map)
}

///|
fn strings(values : Array[String]) -> Json {
  Json::array(values.map(value => Json::string(value)))
}

///|
fn sorted_strings(values : Array[String]) -> Array[String] {
  let sorted = values.copy()
  sorted.sort_by((a, b) => {
    if key_before(a, b) {
      -1
    } else if key_before(b, a) {
      1
    } else {
      0
    }
  })
  sorted
}

///|
fn canonical_text(
  value : Json,
  limits : DeclarationLimits,
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
  limits : DeclarationLimits,
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
/// A self-addressed member: the CID excludes only its own key.
fn seal(
  entries : Array[(String, Json)],
  key : String,
  limits : DeclarationLimits,
) -> (Json, String) raise @encode.EncodeFailure {
  let cid = canonical_cid(object(entries), limits)
  (object([..entries, (key, Json::string(cid))]), cid)
}

///|
/// The ActQL value type that carries a read of this provider type exactly,
/// if any. Salesforce `int` is a 32-bit integer and exact in binary64.
/// `date` is `yyyy-MM-dd`, the ActQL date spelling. `datetime` is read in
/// UTC as `...SSS+0000` and admitted as the same instant ending in `Z`.
/// A Number (`double`) is `decimal(P,S)` from its described precision and
/// scale, up to precision 15 (`double_decimal`), converted from the reply's
/// number text alone. `percent`, `currency` and `time` are not declared:
/// the scale of a percent and the currency of an amount are not fixed by
/// the value, and `time` is a time of day in the saving user's time zone,
/// which ActQL has no type for.
fn read_value_type(native_type : String) -> String? {
  match native_type {
    "id"
    | "reference"
    | "string"
    | "textarea"
    | "email"
    | "phone"
    | "url"
    | "picklist"
    | "combobox" => Some("string")
    "boolean" => Some("boolean")
    "int" => Some("number")
    "date" => Some("date")
    "datetime" => Some("timestamp")
    "double" => Some("decimal")
    _ => None
  }
}

///|
/// The ActQL value type a write of this provider type accepts exactly, if
/// any. It is decided apart from reads: a type is writable only when its
/// written value means what was approved. A `date` is sent as it is, within
/// Salesforce's range. A `timestamp` is sent as it is in UTC, and only in
/// whole seconds (see `timestamp_whole_seconds`).
fn write_value_type(native_type : String) -> String? {
  match native_type {
    "date" => Some("date")
    "datetime" => Some("timestamp")
    _ => read_value_type(native_type)
  }
}

///|
fn typed_contract(field : FieldMetadata, kind : String?) -> Json? {
  guard field.nullability_confirmed && kind is Some(kind) else { return None }
  if kind == "decimal" {
    guard double_decimal(field) is Some((precision, scale)) else { return None }
    return Some(
      object([
        ("nullable", Json::boolean(field.nullable)),
        ("precision", precision.to_json()),
        ("scale", scale.to_json()),
        ("type", kind.to_json()),
      ]),
    )
  }
  Some(
    object([
      ("nullable", Json::boolean(field.nullable)),
      ("type", kind.to_json()),
    ]),
  )
}

///|
fn read_field_contract_json(field : FieldMetadata) -> Json? {
  typed_contract(field, read_value_type(field.native_type))
}

///|
fn write_field_contract_json(field : FieldMetadata) -> Json? {
  typed_contract(field, write_value_type(field.native_type))
}

///|
fn exclusion_reason(field : FieldMetadata) -> DeclarationExclusionReason {
  if read_value_type(field.native_type) is None {
    UnsupportedType(field.native_type)
  } else if field.native_type == "double" && double_decimal(field) is None {
    UnsupportedPrecision(field.precision, field.scale)
  } else {
    UnconfirmedNullability
  }
}

///|
fn record_identity(resource : ResourceMetadata) -> Bool {
  resource.fields
  .iter()
  .any(field => {
    field.name == "Id" &&
    field.native_type == "id" &&
    field.nullability_confirmed &&
    !field.nullable
  })
}

///|
priv struct Envelopes {
  prefix : String
  version : String
  limits : DeclarationLimits
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
fn resource_identity() -> Json {
  object([
    ("version", "actql.resource_identity/0.1".to_json()),
    ("provider_namespace", "salesforce".to_json()),
    ("resource_kind", "sobject".to_json()),
    ("provider_id_field", "Id".to_json()),
    ("output_field", "Id".to_json()),
    ("boundary_topology", "connector_connection".to_json()),
  ])
}

///|
/// Generate the static declaration for the selected Resources of one
/// complete-for-them observation. A Resource that was not selected, not
/// described, or not visible is never declared absent; it is simply outside
/// this declaration.
pub fn generate_static_declaration(
  observation : CatalogObservation,
  current : CatalogObservationBinding,
  implementation : SalesforceImplementation,
  connector_id : String,
  resource_names : Array[String],
  limits : DeclarationLimits,
) -> Result[StaticDeclaration, DeclarationIssue] {
  if !valid_connector_id(connector_id) {
    return Err(InvalidConnectorId)
  }
  if resource_names.is_empty() {
    return Err(InvalidSelection)
  }
  let names = sorted_strings(resource_names)
  for index in 1..<names.length() {
    if names[index] == names[index - 1] {
      return Err(InvalidSelection)
    }
  }
  if implementation.connector_revision != current.connector_revision {
    return Err(ForeignImplementation)
  }
  let resources = []
  for name in names {
    match catalog_observation_resource(observation, current, name) {
      Ok(resource) => resources.push(resource)
      Err(issue) => return Err(Observation(issue))
    }
  }
  let connector_version = current.connector_revision
  try {
    let envelopes : Envelopes = {
      prefix: connector_id,
      version: connector_version,
      limits,
      texts: [],
      values: [],
      cids: [],
    }
    let views = []
    let view_members = []
    let view_bodies = []
    let exclusions = []
    let writables : Array[DeclaredWritable] = []
    for resource in resources {
      let base = "connector://" + connector_id + "/" + resource.name
      // Read side: one SourceView of the exactly typed fields.
      let fields : Array[(String, Json)] = []
      let field_names = []
      for field in resource.fields {
        match read_field_contract_json(field) {
          Some(contract) => {
            fields.push((field.name, contract))
            field_names.push(field.name)
          }
          None =>
            exclusions.push({
              resource: resource.name,
              field: field.name,
              reason: exclusion_reason(field),
            })
        }
      }
      if !resource.queryable || !implementation.scan_read {
        exclusions.push({
          resource: resource.name,
          field: "",
          reason: NotQueryable,
        })
      } else if !fields.is_empty() {
        let source_ref = base + "#records"
        let name = resource.name + "/records"
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
            ("fields", object(fields)),
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
        // Projection is always pushed; only an exact `int` comparison is
        // pushed as a prefilter and the checked filter stays residual. No
        // limit or order is pushed.
        let operations = if implementation.exact_int_prefilter {
          ["filter", "projection"]
        } else {
          ["projection"]
        }
        let pushdown = envelopes.add(
          name + "/pushdown",
          "pushdown",
          object([
            ("version", "actql-source-view-pushdown/0.1".to_json()),
            ("carrier", "relation".to_json()),
            ("operations", strings(operations)),
          ]),
        )
        let entries = [
          ("schema", "actql.source_view/0.1".to_json()),
          ("connector_id", connector_id.to_json()),
          ("connector_version", connector_version.to_json()),
          ("resource_kind", "sobject".to_json()),
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
            object([("contract", pushdown), ("operations", strings(operations))]),
          ),
        ]
        let with_identity = if field_names.contains("Id") &&
          record_identity(resource) {
          [..entries, ("resource_identity", resource_identity())]
        } else {
          entries
        }
        let (view_value, view_cid) = seal(with_identity, "contract_cid", limits)
        view_members.push((view_cid, view_value))
        views.push({
          resource: resource.name,
          source_ref,
          view_cid,
          fields: field_names,
          carrier_schema_cid: ref_cid(row),
          data_policy_cid: ref_cid(policy),
        })
      }
      // Write side: one Mapping whose rules cover what this revision writes.
      if !record_identity(resource) {
        if resource.createable || resource.updateable {
          exclusions.push({
            resource: resource.name,
            field: "Id",
            reason: NoRecordIdentity,
          })
        }
        continue
      }
      let createable = []
      let updateable = []
      let whole_seconds = []
      let mut create_blocked : String? = None
      let required = []
      for field in resource.fields {
        let writable = field.createable || field.updateable
        let contract = write_field_contract_json(field)
        if field.createable &&
          !(field.nullability_confirmed && field.default_on_create_confirmed) {
          create_blocked = Some(field.name)
        } else if field.createable &&
          !field.nullable &&
          !field.defaulted_on_create {
          if contract is None {
            create_blocked = Some(field.name)
          } else {
            required.push(field.name)
          }
        }
        guard writable && contract is Some(_) else { continue }
        if field.native_type == "datetime" {
          whole_seconds.push(field.name)
        }
        if field.createable {
          createable.push(field.name)
        }
        if field.updateable {
          updateable.push(field.name)
        }
      }
      let keys = resource.fields
        .filter(field => {
          field.external_id &&
          field.unique &&
          field.createable &&
          field.updateable &&
          field.nullability_confirmed &&
          (
            field.native_type == "string" ||
            field.native_type == "email" ||
            field.native_type == "int"
          )
        })
        .map(field => field.name)
      let create_fields = if resource.createable &&
        implementation.create &&
        create_blocked is None {
        Some(sorted_strings(createable))
      } else {
        if resource.createable && implementation.create {
          exclusions.push({
            resource: resource.name,
            field: create_blocked.unwrap_or(""),
            reason: CreateRequirementUnknown(create_blocked.unwrap_or("")),
          })
        }
        None
      }
      let update_fields = if resource.updateable &&
        implementation.update_by_id &&
        !updateable.is_empty() {
        Some(sorted_strings(updateable))
      } else {
        None
      }
      let upsert_fields = if create_fields is Some(created) &&
        update_fields is Some(updated) &&
        implementation.upsert_by_external_id &&
        !keys.is_empty() {
        Some(created.filter(name => updated.contains(name)))
      } else {
        None
      }
      if create_fields is None && update_fields is None && upsert_fields is None {
        continue
      }
      writables.push({
        resource: resource.name,
        target_ref: base,
        create_fields,
        update_fields,
        upsert_fields,
        upsert_keys: sorted_strings(keys),
        required_fields: sorted_strings(required),
        timestamp_whole_seconds: sorted_strings(whole_seconds),
      })
    }
    view_members.sort_by((a, b) => {
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
    let contract_values = indexed.map(entry => envelopes.values[entry.1])
    let (catalog, catalog_cid) = seal(
      [
        ("schema", "actql.connector_catalog/0.1".to_json()),
        ("connector_id", connector_id.to_json()),
        ("connector_version", connector_version.to_json()),
        ("source_views", Json::array(view_members.map(entry => entry.1))),
        ("commands", Json::array([])),
        ("contracts", Json::array(contract_values)),
      ],
      "catalog_cid",
      limits,
    )
    for entry in view_members {
      view_bodies.push(canonical_text(entry.1, limits))
    }
    let entry = object([
      ("connector", current.connector_registration.to_json()),
      ("connector_id", connector_id.to_json()),
      ("connector_version", connector_version.to_json()),
    ])
    let manifest_entry = canonical_text(entry, limits)
    let manifest_entry_cid = canonical_cid(entry, limits)
    Ok({
      manifest_entry,
      manifest_entry_cid,
      connector_id,
      connector_version,
      binding: current,
      observation_cid: observation.cid,
      catalog: canonical_text(catalog, limits),
      catalog_cid,
      contracts: indexed.map(entry => envelopes.texts[entry.1]),
      views: view_members.map(entry => {
        let mut found = views[0]
        for view in views {
          if view.view_cid == entry.0 {
            found = view
          }
        }
        found
      }),
      view_bodies,
      writables,
      exclusions,
      resources,
    })
  } catch {
    _ => Err(OutputLimit)
  }
}

///|
pub(all) enum DeclarationUseIssue {
  /// The declaration was generated for another namespace_id, principal,
  /// environment, org, connection, Site, generation, origin or revision.
  ForeignDeclaration
  /// No declared SourceView or Mapping rule covers this Resource and use.
  Undeclared
  UndeclaredField(String)
  UndeclaredKey(String)
  /// The field no longer means what was declared; declare again first.
  SchemaChanged(String)
  /// A row omits a field its Mapping does not omit.
  OmittedField(String)
} derive(Eq, Debug)

///|
/// Every described member a declaration or its use depends on.
fn same_field_meaning(
  declared : FieldMetadata,
  current : FieldMetadata,
) -> Bool {
  declared.name == current.name &&
  declared.native_type == current.native_type &&
  declared.nullable == current.nullable &&
  declared.nullability_confirmed == current.nullability_confirmed &&
  declared.defaulted_on_create == current.defaulted_on_create &&
  declared.default_on_create_confirmed == current.default_on_create_confirmed &&
  declared.createable == current.createable &&
  declared.updateable == current.updateable &&
  declared.filterable == current.filterable &&
  declared.sortable == current.sortable &&
  declared.external_id == current.external_id &&
  declared.unique == current.unique &&
  declared.case_sensitive == current.case_sensitive &&
  declared.reference_to == current.reference_to &&
  declared.precision == current.precision &&
  declared.scale == current.scale
}

///|
fn check_declared_fields(
  declaration : StaticDeclaration,
  resource : String,
  fields : Array[FieldMetadata],
) -> Result[Unit, DeclarationUseIssue] {
  guard declaration.resources.search_by(value => value.name == resource)
    is Some(index) else {
    return Err(Undeclared)
  }
  let declared = declaration.resources[index].fields
  for field in fields {
    guard declared.search_by(value => value.name == field.name)
      is Some(position) else {
      return Err(UndeclaredField(field.name))
    }
    if !same_field_meaning(declared[position], field) {
      return Err(SchemaChanged(field.name))
    }
  }
  Ok(())
}

///|
/// The installed Site identity a declaration is valid for. Dispatch and sync
/// occurrence differ between the generating sync and any later use.
fn declaration_site_matches(
  declared : CatalogObservationBinding,
  current : CatalogObservationBinding,
) -> Bool {
  declared.namespace_id == current.namespace_id &&
  declared.principal == current.principal &&
  declared.environment == current.environment &&
  declared.connection_revision == current.connection_revision &&
  declared.org_id == current.org_id &&
  declared.site_key == current.site_key &&
  declared.site_generation == current.site_generation &&
  declared.connector_registration == current.connector_registration &&
  declared.connector_revision == current.connector_revision &&
  declared.resource_origin == current.resource_origin
}

///|
/// Before any provider I/O: a read plan must use the admitted SourceView of
/// this Site's declaration for its Resource, and only declared fields.
pub fn check_declared_read(
  declaration : StaticDeclaration,
  plan : ReadProjection,
  source_view_cid : String,
) -> Result[Unit, DeclarationUseIssue] {
  if !declaration_site_matches(declaration.binding, plan.binding) {
    return Err(ForeignDeclaration)
  }
  for view in declaration.views {
    if view.resource == plan.resource && view.view_cid == source_view_cid {
      // Each field must be declared and still exactly typed now; the
      // checked input contract is compared with the plan separately.
      for field in plan.fields {
        if !view.fields.contains(field.name) ||
          read_field_contract_json(field) is None {
          return Err(UndeclaredField(field.name))
        }
      }
      return check_declared_fields(declaration, plan.resource, plan.fields)
    }
  }
  Err(Undeclared)
}

///|
pub fn static_declaration_catalog(declaration : StaticDeclaration) -> String {
  declaration.catalog
}

///|
pub fn static_declaration_catalog_cid(
  declaration : StaticDeclaration,
) -> String {
  declaration.catalog_cid
}

///|
fn exclusion_reason_json(reason : DeclarationExclusionReason) -> Json {
  match reason {
    UnconfirmedNullability =>
      object([("kind", "unconfirmed_nullability".to_json())])
    UnsupportedType(native) =>
      object([
        ("kind", "unsupported_type".to_json()),
        ("native_type", native.to_json()),
      ])
    UnsupportedPrecision(precision, scale) =>
      object([
        ("kind", "unsupported_precision".to_json()),
        ("native_type", "double".to_json()),
        (
          "precision",
          precision.map(value => value.to_json()).unwrap_or(Json::null()),
        ),
        ("scale", scale.map(value => value.to_json()).unwrap_or(Json::null())),
      ])
    NotQueryable => object([("kind", "not_queryable".to_json())])
    CreateRequirementUnknown(field) =>
      object([
        ("kind", "create_requirement_unknown".to_json()),
        ("field", field.to_json()),
      ])
    NoRecordIdentity => object([("kind", "no_record_identity".to_json())])
  }
}

///|
fn optional_strings(value : Array[String]?) -> Json {
  match value {
    Some(names) => strings(names)
    None => Json::null()
  }
}

///|
/// The declaration as canonical JSON for the Host: the Catalog and Mapping
/// texts to admit, and what was declared or left out. The Site binding is
/// not included; it stays with the Site-held declaration.
pub fn static_declaration_json(
  declaration : StaticDeclaration,
  limits : DeclarationLimits,
) -> String? {
  let value = object([
    ("connector_id", declaration.connector_id.to_json()),
    ("connector_version", declaration.connector_version.to_json()),
    ("catalog", declaration.catalog.to_json()),
    ("manifest_entry", declaration.manifest_entry.to_json()),
    ("manifest_entry_cid", declaration.manifest_entry_cid.to_json()),
    ("catalog_cid", declaration.catalog_cid.to_json()),
    ("contracts", strings(declaration.contracts)),
    ("source_views", strings(declaration.view_bodies)),
    (
      "views",
      Json::array(
        declaration.views.map(view => {
          object([
            ("resource", view.resource.to_json()),
            ("source_ref", view.source_ref.to_json()),
            ("view_cid", view.view_cid.to_json()),
            ("fields", strings(view.fields)),
          ])
        }),
      ),
    ),
    (
      "writables",
      Json::array(
        declaration.writables.map(writable => {
          object([
            ("resource", writable.resource.to_json()),
            ("target_ref", writable.target_ref.to_json()),
            ("create_fields", optional_strings(writable.create_fields)),
            ("update_fields", optional_strings(writable.update_fields)),
            ("upsert_fields", optional_strings(writable.upsert_fields)),
            ("upsert_keys", strings(writable.upsert_keys)),
            ("required_fields", strings(writable.required_fields)),
            (
              "timestamp_whole_seconds",
              strings(writable.timestamp_whole_seconds),
            ),
          ])
        }),
      ),
    ),
    (
      "exclusions",
      Json::array(
        declaration.exclusions.map(exclusion => {
          object([
            ("resource", exclusion.resource.to_json()),
            ("field", exclusion.field.to_json()),
            ("reason", exclusion_reason_json(exclusion.reason)),
          ])
        }),
      ),
    ),
  ])
  try canonical_text(value, limits) catch {
    _ => None
  } noraise {
    text => Some(text)
  }
}

///|
/// The Result field feeding one target field of a Result-backed create.
pub(all) struct RowSource {
  target : String
  source : String
  null_behavior : String
} derive(Eq, Debug)

///|
/// One Effect's write, as the Program will state it.
pub(all) enum ExecutionWrite {
  /// `create` with an inline `payload` naming these fields.
  CreatePayload(Array[String])
  /// `create` from a Named Result through these field sources.
  CreateFromResult(Array[RowSource])
  /// `update` by record Id of exactly these fields.
  UpdateById(Array[String])
  /// `upsert` on this external ID of exactly these body fields.
  UpsertByExternalId(String, Array[String])
} derive(Eq, Debug)

///|
pub(all) enum ExecutionMappingIssue {
  NotWritable(String)
  OperationNotDeclared
  EmptyWrite
  DuplicateField(String)
  FieldNotWritable(String)
  KeyNotDeclared(String)
  KeyInBody(String)
  MissingRequiredField(String)
  InvalidNullBehavior(String)
  OutputLimit
} derive(Eq, Debug)

///|
/// The executable Mapping for one declared write. Its single permission rule
/// is exactly this write, so the common Effect Check's exact rule match and
/// the provider's request coincide.
pub struct ExecutionMapping {
  declaration : StaticDeclaration
  resource : String
  operation : WriteOperation
  fields : Array[String]
  // Fields this Mapping omits when a Result row's source value is null.
  omittable : Array[String]
  mapping_ref : String
  mapping_cid : String
  body : String
}

///|
fn field_in(resource : ResourceMetadata, name : String) -> FieldMetadata? {
  match resource.fields.search_by(field => field.name == name) {
    Some(index) => Some(resource.fields[index])
    None => None
  }
}

///|
fn unique_names(names : Array[String]) -> Result[Unit, ExecutionMappingIssue] {
  let seen : Map[String, Bool] = Map([])
  for name in names {
    if seen.contains(name) {
      return Err(DuplicateField(name))
    }
    seen[name] = true
  }
  Ok(())
}

///|
/// Prepare the Mapping one Effect uses. It names this connection's manifest
/// entry (`connector_manifest_cid`), which the Host publishes in the Check
/// Environment beside the declaration's Catalog.
pub fn prepare_execution_mapping(
  declaration : StaticDeclaration,
  resource_name : String,
  write : ExecutionWrite,
  limits : DeclarationLimits,
) -> Result[ExecutionMapping, ExecutionMappingIssue] {
  let connector_manifest_cid = declaration.manifest_entry_cid
  guard declaration.writables.search_by(value => value.resource == resource_name)
    is Some(writable_index) else {
    return Err(NotWritable(resource_name))
  }
  let writable = declaration.writables[writable_index]
  guard declaration.resources.search_by(value => value.name == resource_name)
    is Some(resource_index) else {
    return Err(NotWritable(resource_name))
  }
  let resource = declaration.resources[resource_index]
  let (kind, selector, operation, fields, allowed, key) = match write {
    CreatePayload(fields) =>
      ("create", "none", WriteCreate, fields, writable.create_fields, None)
    CreateFromResult(sources) =>
      (
        "create",
        "none",
        WriteCreate,
        sources.map(source => source.target),
        writable.create_fields,
        None,
      )
    UpdateById(fields) =>
      ("update", "id", WriteUpdateById, fields, writable.update_fields, None)
    UpsertByExternalId(key, fields) =>
      (
        "upsert",
        "key",
        WriteUpsertByExternalId(key),
        fields,
        writable.upsert_fields,
        Some(key),
      )
  }
  guard allowed is Some(candidates) else { return Err(OperationNotDeclared) }
  if fields.is_empty() && !(write is CreateFromResult(_)) {
    return Err(EmptyWrite)
  }
  match unique_names(fields) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if key is Some(name) {
    if !writable.upsert_keys.contains(name) {
      return Err(KeyNotDeclared(name))
    }
    // Salesforce selects the record by the key; it is not also a body field.
    if fields.contains(name) {
      return Err(KeyInBody(name))
    }
  }
  for name in fields {
    if !candidates.contains(name) {
      return Err(FieldNotWritable(name))
    }
  }
  if kind == "create" {
    for name in writable.required_fields {
      if !fields.contains(name) {
        return Err(MissingRequiredField(name))
      }
    }
  }
  let row_mapping : Array[(String, Json)] = []
  if write is CreateFromResult(sources) {
    for source in sources {
      let field = field_in(resource, source.target).unwrap()
      let valid = match source.null_behavior {
        "reject" => true
        "write_null" => field.nullable
        "omit" => !writable.required_fields.contains(source.target)
        _ => false
      }
      if !valid || source.source.length() == 0 {
        return Err(InvalidNullBehavior(source.target))
      }
      row_mapping.push(
        (
          source.target,
          object([
            ("field", source.source.to_json()),
            ("null_behavior", source.null_behavior.to_json()),
          ]),
        ),
      )
    }
  }
  let schema_fields : Array[(String, Json)] = [
    (
      "Id",
      object([("nullable", false.to_json()), ("type", "string".to_json())]),
    ),
  ]
  // The upsert key is part of the target schema, so the Mapping identity
  // names the external ID it selects by.
  let described = match key {
    Some(name) => [..fields, name]
    None => fields
  }
  for name in described {
    guard field_in(resource, name) is Some(field) &&
      write_field_contract_json(field) is Some(contract) else {
      return Err(FieldNotWritable(name))
    }
    if name != "Id" {
      schema_fields.push((name, contract))
    }
  }
  let written = sorted_strings(fields)
  let required = if kind == "create" {
    sorted_strings(writable.required_fields)
  } else {
    []
  }
  let target_schema = object([
    ("type", "object".to_json()),
    ("nullable", false.to_json()),
    ("additional_properties", false.to_json()),
    ("fields", object(schema_fields)),
  ])
  try {
    let request_identity = canonical_cid(
      object([
        ("resource", resource_name.to_json()),
        ("kind", kind.to_json()),
        ("key", key.map(value => value.to_json()).unwrap_or(Json::null())),
        ("target_schema", target_schema),
        ("write_fields", strings(written)),
        ("row_mapping", object(row_mapping)),
      ]),
      limits,
    )
    // A distinct reference per distinct write, so several can share one
    // Check Environment.
    let mapping_ref = "mapping:" +
      declaration.connector_id +
      "/" +
      resource_name +
      "/" +
      kind +
      "-" +
      request_identity[7:23].to_owned() +
      ".v1"
    let (mapping, mapping_cid) = seal(
      [
        ("schema", "actql.mapping_contract/0.1".to_json()),
        ("mapping_ref", mapping_ref.to_json()),
        ("version", declaration.connector_version.to_json()),
        ("target_ref", writable.target_ref.to_json()),
        ("connector_manifest_cid", connector_manifest_cid.to_json()),
        (
          "resource_identity_cid",
          canonical_cid(resource_identity(), limits).to_json(),
        ),
        ("target_schema", target_schema),
        (
          "target_schema_identity",
          canonical_cid(target_schema, limits).to_json(),
        ),
        ("primary_identity", "Id".to_json()),
        ("writable_fields", strings(written)),
        ("required_fields", strings(required)),
        ("conversions", Json::array([])),
        (
          "permission_rules",
          Json::array([
            object([
              ("effect_kind", kind.to_json()),
              ("selector_class", selector.to_json()),
              ("write_fields", strings(written)),
              ("permissions", strings(["salesforce:record:" + kind])),
            ]),
          ]),
        ),
        ("required_permissions", Json::array([])),
        ("minimum_approval", "none".to_json()),
        ("row_mapping", object(row_mapping)),
      ],
      "mapping_contract_cid",
      limits,
    )
    let omittable = match write {
      CreateFromResult(sources) =>
        sorted_strings(
          sources
          .filter(source => source.null_behavior == "omit")
          .map(source => source.target),
        )
      _ => []
    }
    Ok({
      declaration,
      resource: resource_name,
      operation,
      fields: written,
      omittable,
      mapping_ref,
      mapping_cid,
      body: canonical_text(mapping, limits),
    })
  } catch {
    _ => Err(OutputLimit)
  }
}

///|
/// The top-level member names of one admitted request body. Request bodies
/// were produced within their own budgets, so their size bounds these limits.
fn body_field_names(body : String) -> Array[String]? {
  let bytes = @utf8.encode(body)
  let nodes = bytes.length() + 1
  guard @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: bytes.length(),
      max_nodes: nodes,
      max_depth: 64,
    })
    is Ok(parsed) &&
    @decode.admit(parsed, {
      max_nodes: nodes,
      max_depth: 64,
      max_string_bytes: bytes.length(),
      max_total_string_bytes: bytes.length(),
    })
    is Ok(root) &&
    @decode.object_field_names(root) is Ok(names) else {
    return None
  }
  Some(names)
}

///|
/// Before any provider I/O: the write request must be exactly this
/// execution Mapping's write, for the declaring Site, and every field it uses
/// (the upsert key included) must still mean what was declared.
pub fn check_execution_write(
  mapping : ExecutionMapping,
  projection : WriteProjection,
  bodies? : Array[String] = [],
) -> Result[Unit, DeclarationUseIssue] {
  let declaration = mapping.declaration
  if !declaration_site_matches(declaration.binding, projection.binding) {
    return Err(ForeignDeclaration)
  }
  if projection.resource != mapping.resource ||
    projection.operation != mapping.operation {
    return Err(Undeclared)
  }
  let requested = sorted_strings(projection.field_names)
  if requested != mapping.fields {
    for name in requested {
      if !mapping.fields.contains(name) {
        return Err(UndeclaredField(name))
      }
    }
    return Err(Undeclared)
  }
  // Each row body carries every Mapping field except those this Mapping
  // omits on a null source.
  for body in bodies {
    guard body_field_names(body) is Some(present) else {
      return Err(Undeclared)
    }
    for name in mapping.fields {
      if !present.contains(name) && !mapping.omittable.contains(name) {
        return Err(OmittedField(name))
      }
    }
  }
  let used = match projection.external_target {
    Some(target) => [..projection.fields, target]
    None => projection.fields
  }
  check_declared_fields(declaration, projection.resource, used)
}

///|
pub fn check_execution_single_write(
  mapping : ExecutionMapping,
  request : SingleWriteRequest,
) -> Result[Unit, DeclarationUseIssue] {
  check_execution_write(mapping, request.projection, bodies=[request.body])
}

///|
pub fn check_execution_collection_write(
  mapping : ExecutionMapping,
  request : WriteCollectionRequest,
) -> Result[Unit, DeclarationUseIssue] {
  check_execution_write(mapping, request.projection, bodies=request.row_bodies)
}

///|
/// A row body for this execution Mapping: a field it omits on a null source
/// may be absent; any other absent field is `MissingField`.
pub fn prepare_execution_write_body(
  mapping : ExecutionMapping,
  projection : WriteProjection,
  bytes : Bytes,
  limits : WriteBodyLimits,
) -> Result[WriteBody, WriteBodyIssue] {
  prepare_write_body_omitting(projection, bytes, limits, mapping.omittable)
}
