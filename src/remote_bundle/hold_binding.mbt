///|
/// Custody metadata for one Coordinator-owned pre-Run hold. This identity does
/// not grant authority: the Site must authenticate, authorize and verify its
/// selected existing manifest and artifact before a new hold is admitted.
struct RemoteBundleHoldBinding {
  distribution : RemoteBundleDistribution
  catalog_incarnation : String
  coordinator_authority : String
  workspace_id : String
  authority_scope_cid : String
  environment : String
  set_revision_cid : String
  distribution_cid : String
  runtime_bundle_cid : String
  site_key : String
  site_generation : Int
  initial_revision : Int
  attempt_id : String
  binding_cid : String
}

///|
pub fn valid_bundle_catalog_incarnation(value : String) -> Bool {
  if value.length() != 36 {
    return false
  }
  for index = 0; index < 36; index = index + 1 {
    let unit = value[index].to_int()
    if index == 8 || index == 13 || index == 18 || index == 23 {
      if unit != 45 {
        return false
      }
    } else if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn flat_bundle_hold_attempt(value : String) -> Bool {
  if !bounded(value, 512) {
    return false
  }
  for character in value.iter() {
    if !((character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '-' ||
      character == '_') {
      return false
    }
  }
  true
}

///|
fn bundle_hold_binding_body(
  value : RemoteBundleHoldBinding,
) -> Result[String, RemoteBundleIssue] {
  let writer = @encode.writer(65536, 32, 1) catch {
    _ => return Err(InvalidBundle)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "attempt_id")
    @encode.string_value(writer, value.attempt_id)
    @encode.key(writer, "authority_scope_cid")
    @encode.string_value(writer, value.authority_scope_cid)
    @encode.key(writer, "catalog_incarnation")
    @encode.string_value(writer, value.catalog_incarnation)
    @encode.key(writer, "coordinator_authority")
    @encode.string_value(writer, value.coordinator_authority)
    @encode.key(writer, "distribution_cid")
    @encode.string_value(writer, value.distribution_cid)
    @encode.key(writer, "environment")
    @encode.string_value(writer, value.environment)
    @encode.key(writer, "initial_revision")
    @encode.number_value(writer, value.initial_revision.to_double())
    @encode.key(writer, "runtime_bundle_cid")
    @encode.string_value(writer, value.runtime_bundle_cid)
    @encode.key(writer, "set_revision_cid")
    @encode.string_value(writer, value.set_revision_cid)
    @encode.key(writer, "site_generation")
    @encode.number_value(writer, value.site_generation.to_double())
    @encode.key(writer, "site_key")
    @encode.string_value(writer, value.site_key)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-runtime-bundle-hold-binding/0.1")
    @encode.key(writer, "workspace_id")
    @encode.string_value(writer, value.workspace_id)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidBundle)
  }
}

///|
pub fn prepare_bundle_hold_binding(
  distribution : RemoteBundleDistribution,
  catalog_incarnation : String,
  coordinator_authority : String,
  workspace_id : String,
  authority_scope_cid : String,
  environment : String,
  set_revision_cid : String,
  runtime_bundle_cid : String,
  site_key : String,
  site_generation : Int,
  initial_revision : Int,
  attempt_id : String,
) -> Result[RemoteBundleHoldBinding, RemoteBundleIssue] {
  if bundle_distribution_json(distribution) is Err(_) ||
    !valid_bundle_catalog_incarnation(catalog_incarnation) ||
    !bounded(coordinator_authority, 512) ||
    !bounded(workspace_id, 512) ||
    !valid_cid(authority_scope_cid) ||
    !bounded(environment, 512) ||
    !valid_cid(set_revision_cid) ||
    !bundle_distribution_contains(distribution, runtime_bundle_cid) ||
    !bounded(site_key, 512) ||
    site_generation < 0 ||
    initial_revision < 0 ||
    !flat_bundle_hold_attempt(attempt_id) {
    return Err(InvalidBundle)
  }
  let pending : RemoteBundleHoldBinding = {
    distribution,
    catalog_incarnation,
    coordinator_authority,
    workspace_id,
    authority_scope_cid,
    environment,
    set_revision_cid,
    distribution_cid: distribution.distribution_cid,
    runtime_bundle_cid,
    site_key,
    site_generation,
    initial_revision,
    attempt_id,
    binding_cid: "pending",
  }
  let body = match bundle_hold_binding_body(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let binding_cid = match bundle_value_identity(body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, binding_cid, })
}

///|
pub fn bundle_hold_binding_identity(value : RemoteBundleHoldBinding) -> String {
  value.binding_cid
}

///|
pub fn bundle_hold_binding_json(
  value : RemoteBundleHoldBinding,
) -> Result[String, RemoteBundleIssue] {
  if bundle_distribution_json(value.distribution) is Err(_) ||
    value.distribution_cid != value.distribution.distribution_cid ||
    !valid_bundle_catalog_incarnation(value.catalog_incarnation) ||
    !bounded(value.coordinator_authority, 512) ||
    !bounded(value.workspace_id, 512) ||
    !valid_cid(value.authority_scope_cid) ||
    !bounded(value.environment, 512) ||
    !valid_cid(value.set_revision_cid) ||
    !bundle_distribution_contains(value.distribution, value.runtime_bundle_cid) ||
    !bounded(value.site_key, 512) ||
    value.site_generation < 0 ||
    value.initial_revision < 0 ||
    !flat_bundle_hold_attempt(value.attempt_id) {
    return Err(InvalidBundle)
  }
  let body = match bundle_hold_binding_body(value) {
    Ok(body) => body
    Err(issue) => return Err(issue)
  }
  match bundle_value_identity(body) {
    Ok(identity) if identity == value.binding_cid => Ok(body)
    Ok(_) => Err(BundleIdentityMismatch)
    Err(issue) => Err(issue)
  }
}

///|
pub fn bundle_hold_binding_projection(
  value : RemoteBundleHoldBinding,
) -> Array[String] {
  [
    value.binding_cid,
    value.catalog_incarnation,
    value.coordinator_authority,
    value.workspace_id,
    value.authority_scope_cid,
    value.environment,
    value.set_revision_cid,
    value.distribution_cid,
    value.runtime_bundle_cid,
    value.site_key,
    value.site_generation.to_string(),
    value.initial_revision.to_string(),
    value.attempt_id,
  ]
}

///|
fn bundle_hold_int(
  object : @decode.ObjectView,
  key : String,
) -> Int raise RemoteBundleDecodeStop {
  let value = decoded(
    @decode.safe_integer(decoded(@decode.required(object, key))),
  )
  if value < 0L || value > 2147483647L {
    raise RemoteBundleDecodeStop
  }
  value.to_int()
}

///|
pub fn admit_bundle_hold_binding_json(
  distribution : RemoteBundleDistribution,
  body : String,
  claimed_binding_cid : String,
) -> Result[RemoteBundleHoldBinding, RemoteBundleIssue] {
  try {
    let object = bundle_control_object(body, [
      "attempt_id", "authority_scope_cid", "catalog_incarnation", "coordinator_authority",
      "distribution_cid", "environment", "initial_revision", "runtime_bundle_cid",
      "set_revision_cid", "site_generation", "site_key", "version", "workspace_id",
    ])
    if field(object, "version") !=
      "actql-remote-runtime-bundle-hold-binding/0.1" ||
      field(object, "distribution_cid") != distribution.distribution_cid {
      raise RemoteBundleDecodeStop
    }
    let binding = match
      prepare_bundle_hold_binding(
        distribution,
        field(object, "catalog_incarnation"),
        field(object, "coordinator_authority"),
        field(object, "workspace_id"),
        field(object, "authority_scope_cid"),
        field(object, "environment"),
        field(object, "set_revision_cid"),
        field(object, "runtime_bundle_cid"),
        field(object, "site_key"),
        bundle_hold_int(object, "site_generation"),
        bundle_hold_int(object, "initial_revision"),
        field(object, "attempt_id"),
      ) {
      Ok(value) => value
      Err(_) => raise RemoteBundleDecodeStop
    }
    if bundle_hold_binding_json(binding) != Ok(body) {
      raise RemoteBundleDecodeStop
    }
    if binding.binding_cid != claimed_binding_cid {
      Err(BundleIdentityMismatch)
    } else {
      Ok(binding)
    }
  } catch {
    RemoteBundleDecodeStop => Err(InvalidBundle)
  }
}
