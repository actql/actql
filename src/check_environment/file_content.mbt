///|
/// Checked Catalog declaration only. Runtime capture still proves exact keys,
/// complete responses, bytes, policy and custody before the issuer emits a Ref.
struct FileContentProfile {
  body : @decode.Cursor
  facts_cid : String
  scope_cid : String
  version_capability_cid : String
}

///|
pub fn source_request_file_content(
  view : SourceViewRequestContract,
) -> FileContentProfile? {
  view.file_content
}

///|
pub fn file_content_source(profile : FileContentProfile) -> @decode.Cursor {
  profile.body
}

///|
pub fn file_content_facts_cid(profile : FileContentProfile) -> String {
  profile.facts_cid
}

///|
pub fn file_content_scope_cid(profile : FileContentProfile) -> String {
  profile.scope_cid
}

///|
pub fn file_content_version_capability_cid(
  profile : FileContentProfile,
) -> String {
  profile.version_capability_cid
}

///|
fn content_object(
  source : @decode.Cursor,
  b : SourceRequestBudget,
) -> @decode.ObjectView raise SourceRequestStop {
  if @decode.object_length(source) is None {
    request_fail(InvalidFileContentProfile, source)
  }
  request_object(source, b)
}

///|
fn content_required(
  object : @decode.ObjectView,
  name : String,
  source : @decode.Cursor,
) -> @decode.Cursor raise SourceRequestStop {
  match @decode.lookup(object, name) {
    Some(value) => value
    None => request_fail(InvalidFileContentProfile, source)
  }
}

///|
fn content_text(
  object : @decode.ObjectView,
  name : String,
  source : @decode.Cursor,
  b : SourceRequestBudget,
) -> String raise SourceRequestStop {
  let value = content_required(object, name, source)
  let text = match @decode.text(value) {
    Ok(text) => text
    Err(_) => request_fail(InvalidFileContentProfile, value)
  }
  request_charge(b, text.length() + 1, value)
  text
}

///|
fn content_role_contract(
  name : String,
  contract : @value_contract.Contract,
  resource_kind : String,
) -> Bool {
  !contract.nullable &&
  (match (name, contract.shape) {
    ("resource", @value_contract.ResourceRef(resource_kind=kind)) =>
      kind == resource_kind
    ("version", @value_contract.Text(_)) => true
    ("content", @value_contract.ContentRef(_)) => true
    _ => false
  })
}

///|
fn file_content_profile_fields() -> Int {
  6
}

///|
fn read_file_content_profile(
  view : Member,
  catalog : Catalog,
  carriers : CarrierSchemas,
  request_schema : @row.Schema,
  correlation : SourceCorrelation?,
  b : SourceRequestBudget,
) -> FileContentProfile? raise SourceRequestStop {
  let root = request_object(member_body(view), b)
  let output = request_object(@decode.required(root, "output").unwrap(), b)
  let reference = request_object(@decode.required(output, "facts").unwrap(), b)
  let envelope = match
    resolve_catalog_contract(
      catalog,
      content_text(reference, "id", member_body(view), b),
      content_text(reference, "version", member_body(view), b),
      content_text(reference, "cid", member_body(view), b),
      "carrier_facts",
    ) {
    Ok(value) => value
    Err(_) => request_fail(InvalidFileContentProfile, member_body(view))
  }
  if @decode.object_length(envelope.body) is None {
    return None
  }
  let facts = request_object(envelope.body, b)
  let source = match @decode.lookup(facts, "file_content") {
    None => return None
    Some(value) => value
  }
  // Listing and capture are distinct admitted SourceViews, not one ambiguous
  // profile selected by a runtime flag or an authored field name.
  if @decode.lookup(facts, "file_listing") is Some(_) ||
    @decode.object_length(source) != Some(file_content_profile_fields()) {
    request_fail(InvalidFileContentProfile, source)
  }
  let profile = content_object(source, b)
  let scope = content_text(profile, "admitted_scope_contract_cid", source, b)
  if content_text(profile, "version", source, b) != "actql-file-content/0.1" ||
    content_text(profile, "kind", source, b) != "file_content" ||
    content_text(profile, "representation", source, b) != "exact_stored_bytes" ||
    !file_list_cid(scope) {
    request_fail(InvalidFileContentProfile, source)
  }
  let schema_ref = request_object(
    @decode.required(output, "schema").unwrap(),
    b,
  )
  if content_text(profile, "content_schema_contract_cid", source, b) !=
    content_text(schema_ref, "cid", source, b) {
    request_fail(InvalidFileContentProfile, source)
  }
  let capability_source = content_required(
    profile, "version_capability", source,
  )
  if @decode.object_length(capability_source) !=
    Some(file_version_capability_fields()) {
    request_fail(InvalidFileContentProfile, capability_source)
  }
  let capability = content_object(capability_source, b)
  let capability_cid = content_text(
    capability, "contract_cid", capability_source, b,
  )
  if !file_list_cid(capability_cid) ||
    @decode.boolean(
      content_required(capability, "required_nonnull", capability_source),
    ) !=
    Ok(true) {
    request_fail(InvalidFileContentProfile, capability_source)
  }
  let acquisition = request_object(
    @decode.required(root, "acquisition").unwrap(),
    b,
  )
  if content_text(acquisition, "kind", source, b) != "fetch" {
    request_fail(InvalidFileContentProfile, source)
  }
  let authority = content_text(acquisition, "authority", source, b)
  if authority != "read_content" && authority != "read_binary" {
    request_fail(InvalidFileContentProfile, source)
  }
  guard correlation is Some(correlation) &&
    correlation.cardinality == One &&
    correlation.pairs.length() == 2 &&
    correlation.identity.length() == 2 else {
    request_fail(InvalidFileContentProfile, source)
  }
  let resource_kind = content_text(root, "resource_kind", source, b)
  let records = match carriers.views[member_index(view)].schema.carrier {
    @carrier.Relation(records) => records
    _ => request_fail(InvalidFileContentProfile, source)
  }
  let schema = match @carrier.complete_schema(records) {
    Some(schema) => schema
    None => request_fail(InvalidFileContentProfile, source)
  }
  // The role columns must exist on every response, independently of nullable.
  for name in ["resource", "version", "content"] {
    request_charge(b, 1, source)
    guard @row.lookup_reference(schema, name) is Some(field) &&
      @row.field_presence(field) == @row.Required &&
      content_role_contract(name, @row.field_contract(field), resource_kind) else {
      request_fail(InvalidFileContentProfile, source)
    }
  }
  for name in ["resource", "version"] {
    request_charge(b, 1, source)
    guard @row.lookup(request_schema, @row.Unqualified(name)) is Some(contract) &&
      content_role_contract(name, contract, resource_kind) else {
      request_fail(InvalidFileContentProfile, source)
    }
    if !correlation.pairs.any(pair => {
        pair.request.name == name && pair.response.name == name
      }) ||
      !correlation.identity.any(role => role.name == name) {
      request_fail(InvalidFileContentProfile, correlation.source)
    }
  }
  // Reuse the lookup component interpreter and its work accounting. A hard
  // limit or a two-row declaration is not strict, exactly-one content capture.
  let capacity_source = content_required(
    facts,
    "lookup_capacity",
    envelope.body,
  )
  let lookup_budget = { limit: b.work, used: 0, }
  let capacity = lookup_capacity_body(capacity_source, lookup_budget) catch {
    LookupCapacityStop(issue) => {
      // Keep the original nested work already consumed before this refusal.
      // The same request budget owns it; no retry/refund or new allowance.
      b.work -= lookup_budget.used
      request_fail(
        if issue.kind == WorkLimit {
          WorkLimit
        } else {
          InvalidFileContentProfile
        },
        capacity_source,
      )
    }
  }
  b.work -= lookup_budget.used
  if capacity.completeness != CompletePerRequestedKey || capacity.rows != 1L {
    request_fail(InvalidFileContentProfile, capacity_source)
  }
  Some({
    body: source,
    facts_cid: envelope.cid,
    scope_cid: scope,
    version_capability_cid: capability_cid,
  })
}
