// The existing installed GCS ReferenceIssuer supplies authority. The checked
// Common pair and the original collection supply exact selection, not a grant.

///|
pub(all) struct CollectionReferenceLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_work : Int
}

///|
pub(all) enum CollectionReferenceIssue {
  InvalidLimits
  ForeignSelection
  CapacityExceeded
  ReferenceRejected(@admitted.ReferenceIssue)
} derive(Eq, Debug)

///|
priv struct ComparisonBudget {
  mut remaining : Int
}

///|
fn cursor_wire(
  cursor : @decode.Cursor,
  limits : CollectionReferenceLimits,
  budget : ComparisonBudget,
) -> Result[String, CollectionReferenceIssue] {
  guard @canonical.start_cursor_admission(
      cursor,
      limits.max_nodes,
      limits.max_depth,
      limits.max_bytes,
      limits.max_bytes,
      data_keys=true,
    )
    is Some(pending) else {
    return Err(CapacityExceeded)
  }
  while budget.remaining > 0 {
    budget.remaining -= 1
    match @canonical.advance_cursor_admission(pending) {
      CursorAdmissionContinue => ()
      CursorAdmissionComplete(value, _, _) => {
        return try {
          Ok(
            @canonical.stringify_value(
              value,
              limits.max_bytes,
              limits.max_nodes,
              limits.max_depth,
            ),
          )
        } catch {
          _ => Err(CapacityExceeded)
        }
      }
      CursorAdmissionFailed(_) | CursorAdmissionTerminal =>
        return Err(CapacityExceeded)
    }
  }
  @canonical.cancel_cursor_admission(pending)
  Err(CapacityExceeded)
}

///|
fn contract(limits : CollectionReferenceLimits) -> @contract.Contract? {
  // Read the fixed non-null ResourceRef contract in its existing owner. This
  // is not a private constructor, a String substitute or a new wire role.
  let bytes = @utf8.encode(
    "{\"nullable\":false,\"resource_kind\":\"file_collection\",\"type\":\"resource_ref\"}",
  )
  guard @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    })
    is Ok(tree) &&
    @decode.admit(tree, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Ok(cursor) else {
    return None
  }
  match
    @contract.read_checked(cursor, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_bytes,
    }) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
pub fn issue_collection_reference(
  original : @gcs.ObjectCollectionBinding,
  selected : @environment.StoreCommandBinding,
  declared_wire : String,
  connector_id : String,
  issuer : @admitted.ReferenceIssuer,
  limits : CollectionReferenceLimits,
) -> Result[@admitted.CheckedValue, CollectionReferenceIssue] {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_work < 1 {
    return Err(InvalidLimits)
  }
  let data_limits : @gcs.ObjectUploadDeclarationLimits = {
    max_bytes: limits.max_bytes,
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
  }
  // Reuse the vendor's complete declaration/mapping projection. Comparing the
  // complete original bodies is deliberate; equal identifiers alone do not
  // transfer another environment's nominal pair or installation custody.
  let expected_mapping = match
    @gcs.object_upload_mapping_json(
      original, declared_wire, connector_id, data_limits,
    ) {
    Ok(value) => value
    Err(CapacityExceeded) => return Err(CapacityExceeded)
    Err(_) => return Err(ForeignSelection)
  }
  let complete = match
    @gcs.object_upload_catalog_json(declared_wire, connector_id, data_limits) {
    Ok(value) => value
    Err(CapacityExceeded) => return Err(CapacityExceeded)
    Err(_) => return Err(ForeignSelection)
  }
  let complete = @json.parse(complete) catch {
    _ => return Err(ForeignSelection)
  }
  guard complete is Object(declared) &&
    declared.get("catalog") is Some(String(expected_catalog)) else {
    return Err(ForeignSelection)
  }
  let mapping = @environment.mapping_shape_member(
    @environment.store_command_mapping(selected),
  )
  let command = @environment.store_command_target(selected)
  let catalog = @environment.catalog_member(
    @environment.command_target_catalog(command),
  )
  if !physical_equal(
    @environment.member_environment(mapping),
    @environment.member_environment(@environment.command_target_member(command)),
  ) ||
    !physical_equal(
      @environment.member_environment(mapping),
      @environment.member_environment(catalog),
    ) ||
    @environment.command_target_resource_kind(command) != "file_collection" ||
    @environment.command_target_id(command) !=
      "command:" + connector_id + ".gcs.upload.v1" {
    return Err(ForeignSelection)
  }
  let budget = { remaining: limits.max_work, }
  let actual_mapping = match cursor_wire(
    @environment.member_body(mapping), limits, budget,
  ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if actual_mapping != expected_mapping {
    return Err(ForeignSelection)
  }
  let actual_catalog = match cursor_wire(
    @environment.member_body(catalog), limits, budget,
  ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if actual_catalog != expected_catalog {
    return Err(ForeignSelection)
  }
  guard contract(limits) is Some(contract) else {
    return Err(CapacityExceeded)
  }
  match
    @admitted.issue_reference(
      issuer,
      contract,
      @gcs.object_collection_resource_json(original),
      {
        max_bytes: limits.max_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_text_units: limits.max_bytes,
      },
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(ReferenceRejected(issue))
  }
}
