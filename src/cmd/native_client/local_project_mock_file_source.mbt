///|
// Logical Source custody only. The original managed Read still owns physical
// transport, Account checks, response charging and child-first retirement.
// Issuer callbacks retain this state, never the Project/issuer/provider itself.
priv struct LocalProjectMockFileReferences {
  mut known : Array[LocalProjectMockFileReference]?
  scope : String
  authority : String
  provider : String
  max_items : Int
}

///|
priv struct LocalProjectMockFileReference {
  binding : LocalProjectMockFileBinding
  identity : String
  wire : String
  mut value : @admitted.CheckedValue?
}

///|
priv struct LocalProjectMockFileSource {
  _retained_original : LocalProjectMockSourceDeclaration
  _retained_listings : Array[
    (@row_file.NativeRelationFileListingProvider, LocalProjectMockFileBinding),
  ]
  _retained_resolve_identity : (
    LocalProjectMockFileBinding,
    @admitted.ReferenceValue,
  ) -> String?
  references : LocalProjectMockFileReferences
  _retained_issuer : @admitted.ReferenceIssuer
  _retained_contract : @contract.Contract
}

///|
// Called only with the same adopted Journal's original authority-scope result.
// This installs no Allow, opens no payload and grants no physical Read. The
// Source's checked construction allowance must cover issuance before listing.
fn local_project_mock_file_source(
  original : LocalProjectMockSourceDeclaration,
  authority : String,
) -> Result[LocalProjectMockFileSource, @row_host.RowHostIssue] {
  let syntax = match
    @source.parse_json(
      "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"file\"}",
      { max_input_bytes: 1024, max_nodes: 32, max_depth: 4, },
    ) {
    Ok(value) => value
    Err(_) => return Err(@row_host.RowHostIssue::InvalidSpecification)
  }
  let cursor = match
    @decode.admit(syntax, {
      max_nodes: 32,
      max_depth: 4,
      max_string_bytes: 1024,
      max_total_string_bytes: 1024,
    }) {
    Ok(value) => value
    Err(_) => return Err(@row_host.RowHostIssue::InvalidSpecification)
  }
  let contract = match
    @contract.read_checked(cursor, {
      max_nodes: 32,
      max_depth: 4,
      max_text_bytes: 1024,
    }) {
    Ok(value) => value
    Err(_) => return Err(@row_host.RowHostIssue::InvalidSpecification)
  }
  let references = {
    known: Some([]),
    scope: original._retained_scope_cid,
    authority,
    provider: original._retained_provider_namespace,
    max_items: local_project_mock_file_limits().page.max_rows,
  }
  let issuer = @admitted.bind_reference_issuer(
    (selected, wire) => {
      selected.shape is @contract.ResourceRef(resource_kind="file") &&
      references.known is Some(known) &&
      known.any(original => original.wire == wire)
    },
    _ => references.known is Some(_),
  )
  let listings = []
  for binding in original._retained_files {
    let provider = match
      @row_file.prepare_native_relation_file_listing_provider(
        original._retained_declaration,
        binding.listing.resource,
        binding._retained_provider,
        {
          name: binding._retained_name,
          version: binding._retained_version,
          media_type: binding._retained_media_type,
          path: binding._retained_path,
        },
        issuer,
        identity => {
          references.observe_identity(issuer, contract, binding, identity)
        },
      ) {
      Ok(value) => value
      Err(_) => return Err(@row_host.RowHostIssue::InvalidSpecification)
    }
    listings.push((provider, binding))
  }
  Ok({
    _retained_original: original,
    references,
    _retained_listings: listings,
    _retained_resolve_identity: (binding, value) => {
      references.resolve_identity(binding, value)
    },
    _retained_issuer: issuer,
    _retained_contract: contract,
  })
}

///|
fn LocalProjectMockFileSource::retire(self : Self) -> Unit {
  // Cut the actual backing, not just its logical length. Escaped nominal
  // values keep a closed state and cannot retain the original row inventory.
  self.references.known = None
}

///|
// Private callback of the physical listing projection: its identity comes
// from an original checked row, never from authored reference-shaped JSON.
fn LocalProjectMockFileReferences::observe_identity(
  self : Self,
  issuer : @admitted.ReferenceIssuer,
  contract : @contract.Contract,
  binding : LocalProjectMockFileBinding,
  identity : String,
) -> Result[@admitted.CheckedValue, @row_file.NativeRelationFileIssue] {
  guard self.known is Some(known) else { return Err(ForeignOriginal) }
  if known
    .iter()
    .find_first(original => {
      physical_equal(original.binding, binding) && original.identity == identity
    })
    is Some(original) {
    return original.value
      .map(value => Ok(value))
      .unwrap_or(Err(ForeignOriginal))
  }
  if known.length() >= self.max_items {
    return Err(FileLimit)
  }
  let cid = match
    local_project_mock_file_cid({
      "scope": Json::string(self.scope),
      "collection": Json::string(binding._retained_selection.resource),
      "identity": Json::string(identity),
    }) {
    Ok(value) => value
    Err(_) => return Err(@row_file.NativeRelationFileIssue::InvalidInput)
  }
  let wire = match
    local_project_mock_relation_wire({
      "$actql_ref": "resource",
      "version": "actql-resource-ref/0.1",
      "provider_namespace": Json::string(self.provider),
      "resource_kind": "file",
      "provider_identity_cid": Json::string(self.scope),
      "authority_scope_cid": Json::string(self.authority),
      "boundary_cid": Json::string(self.scope),
      "identity_cid": Json::string(cid),
    }) {
    Ok(value) => value
    Err(_) => return Err(@row_file.NativeRelationFileIssue::InvalidInput)
  }
  let original = { binding, identity, wire, value: None, }
  // Retain the occurrence before the original value owner calls the issuer.
  known.push(original)
  let value = match
    @admitted.issue_reference(issuer, contract, wire, {
      max_bytes: @utf8.encode(wire).length(),
      max_nodes: 9,
      max_depth: 1,
      max_text_units: wire.length(),
    }) {
    Ok(value) => value
    Err(_) => return Err(@row_file.NativeRelationFileIssue::InvalidInput)
  }
  original.value = Some(value)
  Ok(value)
}

///|
// Keyed Content must resolve the original issued occurrence. Equal JSON,
// another Source's issuer or another binding cannot manufacture a lookup key.
fn LocalProjectMockFileReferences::resolve_identity(
  self : Self,
  binding : LocalProjectMockFileBinding,
  reference : @admitted.ReferenceValue,
) -> String? {
  guard self.known is Some(known) && @admitted.reference_available(reference) else {
    return None
  }
  for original in known {
    if physical_equal(original.binding, binding) &&
      original.value is Some(value) &&
      value.value is @admitted.Reference(issued) &&
      @admitted.reference_same_issuer(issued, reference) &&
      @admitted.reference_wire(reference) == original.wire {
      return Some(original.identity)
    }
  }
  None
}
