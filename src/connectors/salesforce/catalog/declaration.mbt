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
}

///|
pub struct DeclaredMapping {
  resource : String
  mapping_ref : String
  target_ref : String
  mapping_cid : String
  create_fields : Array[String]?
  update_fields : Array[String]?
  upsert_fields : Array[String]?
  upsert_keys : Array[String]
  body : String
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
  mappings : Array[DeclaredMapping]
  exclusions : Array[DeclarationExclusion]
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
/// The ActQL value type that carries this provider type exactly, if any.
/// Salesforce `int` is a 32-bit integer and exact in binary64. `double`
/// describes decimal Number, Currency and Percent fields: binary64 `number`
/// does not carry their decimal values exactly, and no existing conversion
/// law admits them as `decimal`, so they are not declared.
fn declared_value_type(native_type : String) -> String? {
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
    _ => None
  }
}

///|
fn field_contract(field : FieldMetadata) -> Json? {
  guard field.nullability_confirmed &&
    declared_value_type(field.native_type) is Some(kind) else {
    return None
  }
  Some(
    object([
      ("nullable", Json::boolean(field.nullable)),
      ("type", kind.to_json()),
    ]),
  )
}

///|
fn exclusion_reason(field : FieldMetadata) -> DeclarationExclusionReason {
  if declared_value_type(field.native_type) is None {
    UnsupportedType(field.native_type)
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
priv struct PendingMapping {
  resource : ResourceMetadata
  base : String
  rules : Array[Json]
  writable : Array[String]
  required : Array[String]
  target_schema : Json
  create_fields : Array[String]?
  update_fields : Array[String]?
  upsert_fields : Array[String]?
  keys : Array[String]
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
    let mappings = []
    let exclusions = []
    let mapping_members : Array[PendingMapping] = []
    for resource in resources {
      let base = "connector://" + connector_id + "/" + resource.name
      // Read side: one SourceView of the exactly typed fields.
      let fields : Array[(String, Json)] = []
      let field_names = []
      for field in resource.fields {
        match field_contract(field) {
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
      let target_fields : Array[(String, Json)] = []
      let mut create_blocked : String? = None
      let required = []
      for field in resource.fields {
        let writable = field.createable || field.updateable
        let contract = field_contract(field)
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
        guard writable && contract is Some(value) else { continue }
        target_fields.push((field.name, value))
        if field.createable {
          createable.push(field.name)
        }
        if field.updateable {
          updateable.push(field.name)
        }
      }
      let id_contract = object([
        ("nullable", false.to_json()),
        ("type", "string".to_json()),
      ])
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
      let rules = []
      let rule = (kind : String, selector : String, fields : Array[String]) => {
        object([
          ("effect_kind", kind.to_json()),
          ("selector_class", selector.to_json()),
          ("write_fields", strings(fields)),
          ("permissions", strings(["salesforce:record:" + kind])),
        ])
      }
      if create_fields is Some(value) {
        rules.push(rule("create", "none", value))
      }
      if update_fields is Some(value) {
        rules.push(rule("update", "id", value))
      }
      if upsert_fields is Some(value) {
        rules.push(rule("upsert", "key", value))
      }
      if rules.is_empty() {
        continue
      }
      let writable = sorted_strings(
        createable.filter(name => !updateable.contains(name)) + updateable,
      )
      let target_schema = object([
        ("type", "object".to_json()),
        ("nullable", false.to_json()),
        ("additional_properties", false.to_json()),
        ("fields", object([("Id", id_contract), ..target_fields])),
      ])
      mapping_members.push({
        resource,
        base,
        rules,
        writable,
        required,
        target_schema,
        create_fields,
        update_fields,
        upsert_fields,
        keys,
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
    for pending in mapping_members {
      let resource = pending.resource
      let base = pending.base
      let target_schema = pending.target_schema
      let target_identity = canonical_cid(target_schema, limits)
      let mapping_ref = "mapping:" + connector_id + "/" + resource.name + ".v1"
      let (mapping, mapping_cid) = seal(
        [
          ("schema", "actql.mapping_contract/0.1".to_json()),
          ("mapping_ref", mapping_ref.to_json()),
          ("version", connector_version.to_json()),
          ("target_ref", base.to_json()),
          // No Connector manifest contract is admitted today; the Catalog
          // is the only published identity this Mapping belongs to.
          ("connector_manifest_cid", catalog_cid.to_json()),
          (
            "resource_identity_cid",
            canonical_cid(resource_identity(), limits).to_json(),
          ),
          ("target_schema", target_schema),
          ("target_schema_identity", target_identity.to_json()),
          ("primary_identity", "Id".to_json()),
          ("writable_fields", strings(pending.writable)),
          ("required_fields", strings(sorted_strings(pending.required))),
          ("conversions", Json::array([])),
          ("permission_rules", Json::array(pending.rules)),
          ("required_permissions", Json::array([])),
          ("minimum_approval", "none".to_json()),
          // Program write selection names every written field.
          ("row_mapping", object([])),
        ],
        "mapping_contract_cid",
        limits,
      )
      mappings.push({
        resource: resource.name,
        mapping_ref,
        target_ref: base,
        mapping_cid,
        create_fields: pending.create_fields,
        update_fields: pending.update_fields,
        upsert_fields: pending.upsert_fields,
        upsert_keys: sorted_strings(pending.keys),
        body: canonical_text(mapping, limits),
      })
    }
    Ok({
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
      mappings,
      exclusions,
    })
  } catch {
    _ => Err(OutputLimit)
  }
}

///|
pub(all) enum DeclarationUseIssue {
  /// The declaration was generated for another tenant, principal,
  /// environment, org, connection, Site, generation, origin or revision.
  ForeignDeclaration
  /// No declared SourceView or Mapping rule covers this Resource and use.
  Undeclared
  UndeclaredField(String)
  UndeclaredKey(String)
} derive(Eq, Debug)

///|
/// The installed Site identity a declaration is valid for. Dispatch and sync
/// occurrence differ between the generating sync and any later use.
fn declaration_site_matches(
  declared : CatalogObservationBinding,
  current : CatalogObservationBinding,
) -> Bool {
  declared.tenant == current.tenant &&
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
        if !view.fields.contains(field.name) || field_contract(field) is None {
          return Err(UndeclaredField(field.name))
        }
      }
      return Ok(())
    }
  }
  Err(Undeclared)
}

///|
/// Before any provider I/O: a write projection must fall under a declared
/// Mapping rule of this Site's declaration for its Resource and operation.
pub fn check_declared_write(
  declaration : StaticDeclaration,
  projection : WriteProjection,
) -> Result[Unit, DeclarationUseIssue] {
  if !declaration_site_matches(declaration.binding, projection.binding) {
    return Err(ForeignDeclaration)
  }
  for mapping in declaration.mappings {
    if mapping.resource != projection.resource {
      continue
    }
    let allowed = match projection.operation {
      WriteCreate => mapping.create_fields
      WriteUpdateById => mapping.update_fields
      WriteUpsertByExternalId(key) => {
        if !mapping.upsert_keys.contains(key) {
          return Err(UndeclaredKey(key))
        }
        mapping.upsert_fields
      }
    }
    guard allowed is Some(fields) else { return Err(Undeclared) }
    for name in projection.field_names {
      if !fields.contains(name) {
        return Err(UndeclaredField(name))
      }
    }
    return Ok(())
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
      "mappings",
      Json::array(
        declaration.mappings.map(mapping => {
          object([
            ("resource", mapping.resource.to_json()),
            ("mapping_ref", mapping.mapping_ref.to_json()),
            ("target_ref", mapping.target_ref.to_json()),
            ("mapping_cid", mapping.mapping_cid.to_json()),
            ("create_fields", optional_strings(mapping.create_fields)),
            ("update_fields", optional_strings(mapping.update_fields)),
            ("upsert_fields", optional_strings(mapping.upsert_fields)),
            ("upsert_keys", strings(mapping.upsert_keys)),
            ("body", mapping.body.to_json()),
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
pub fn check_declared_single_write(
  declaration : StaticDeclaration,
  request : SingleWriteRequest,
) -> Result[Unit, DeclarationUseIssue] {
  check_declared_write(declaration, request.projection)
}

///|
pub fn check_declared_collection_write(
  declaration : StaticDeclaration,
  request : WriteCollectionRequest,
) -> Result[Unit, DeclarationUseIssue] {
  check_declared_write(declaration, request.projection)
}
