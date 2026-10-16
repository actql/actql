// GCS collection DATA for the existing Mapping and ResourceReference owners.
// These bytes cannot issue a reference, authenticate an installation or grant I/O.

///|
pub(all) struct ObjectCollectionLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum ObjectCollectionIssue {
  InvalidBinding
  CapacityExceeded
  ForeignBinding
} derive(Eq, Debug)

///|
pub struct ObjectCollectionBinding {
  installation_cid : String
  target_ref : String
  identity_wire : String
  identity_cid : String
  resource_wire : String
}

///|
fn collection_json(
  body : Json,
  limits : ObjectCollectionLimits,
) -> Result[String, ObjectCollectionIssue] {
  try {
    let value = @canonical.from_json(
      body,
      limits.max_nodes,
      limits.max_depth,
      limits.max_bytes,
      data_keys=true,
    )
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

///|
fn collection_cid(wire : String) -> String {
  "sha256:" + @sha.hex(@utf8.encode(wire))
}

///|
// target_ref is an explicitly selected Catalog/Mapping target, never a Source
// alias. The installed Common owner must separately prove the original pair,
// target and installation and supply currentness when issuing the reference.
pub fn prepare_object_collection_binding(
  project : String,
  bucket : String,
  prefix : String,
  target_ref : String,
  resource_kind : String,
  catalog_cid : String,
  installation_cid : String,
  limits : ObjectCollectionLimits,
) -> Result[ObjectCollectionBinding, ObjectCollectionIssue] {
  if limits.max_bytes < 1 || limits.max_nodes < 1 || limits.max_depth < 1 {
    return Err(InvalidBinding)
  }
  if project.is_empty() ||
    bucket.is_empty() ||
    resource_kind.is_empty() ||
    !target_ref.has_prefix("connector://") ||
    target_ref.length() <= 12 ||
    !mutation_cid(catalog_cid) ||
    !mutation_cid(installation_cid) {
    return Err(InvalidBinding)
  }
  for value in [project, bucket, prefix, target_ref, resource_kind] {
    if @scalar.admit_utf8_length(value, limits.max_bytes) is Err(_) {
      return Err(CapacityExceeded)
    }
  }
  // Provider/scope domains match the existing installed GCS Source. Exact
  // opaque prefix text is not normalized, decoded or resolved as a URL path.
  let provider = match
    collection_json(
      {
        "version": "actql-gcs-provider/0.1",
        "project": project.to_json(),
        "bucket": bucket.to_json(),
      },
      limits,
    ) {
    Ok(value) => collection_cid(value)
    Err(issue) => return Err(issue)
  }
  let scope = match
    collection_json(
      {
        "version": "actql-gcs-resource-scope/0.1",
        "project": project.to_json(),
        "bucket": bucket.to_json(),
        "prefix": prefix.to_json(),
      },
      limits,
    ) {
    Ok(value) => collection_cid(value)
    Err(issue) => return Err(issue)
  }
  // This is the existing Mapping collection_resource_identity body, not a
  // provider-specific replacement identity domain or an installation permit.
  let identity_wire = match
    collection_json(
      {
        "version": "actql.collection_resource_identity/0.1",
        "provider_namespace": "gcs",
        "resource_kind": resource_kind.to_json(),
        "target_ref": target_ref.to_json(),
        "collection_identity": {
          "project": project.to_json(),
          "bucket": bucket.to_json(),
          "prefix": prefix.to_json(),
        },
        "boundary_topology": "connector_connection",
      },
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let identity_cid = collection_cid(identity_wire)
  let resource_wire = match
    collection_json(
      {
        "$actql_ref": "resource",
        "version": "actql-resource-ref/0.1",
        "provider_namespace": "gcs",
        "resource_kind": resource_kind.to_json(),
        "provider_identity_cid": provider.to_json(),
        "authority_scope_cid": scope.to_json(),
        "boundary_cid": catalog_cid.to_json(),
        "identity_cid": identity_cid.to_json(),
      },
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    installation_cid,
    target_ref,
    identity_wire,
    identity_cid,
    resource_wire,
  })
}

///|
pub fn object_collection_identity_json(
  binding : ObjectCollectionBinding,
) -> String {
  binding.identity_wire
}

///|
pub fn object_collection_identity_cid(
  binding : ObjectCollectionBinding,
) -> String {
  binding.identity_cid
}

///|
pub fn object_collection_resource_json(
  binding : ObjectCollectionBinding,
) -> String {
  binding.resource_wire
}

///|
// Receiver DATA guard, not a Common reference issuer or currentness predicate.
// Equal strings from another binding do not transfer its installation custody.
pub fn check_object_collection_binding(
  original : ObjectCollectionBinding,
  selected : ObjectCollectionBinding,
  installation_cid : String,
  target_ref : String,
) -> Result[Unit, ObjectCollectionIssue] {
  if !physical_equal(original, selected) ||
    original.installation_cid != installation_cid ||
    original.target_ref != target_ref {
    Err(ForeignBinding)
  } else {
    Ok(())
  }
}
