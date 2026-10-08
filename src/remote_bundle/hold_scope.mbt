///|
/// Immutable query scope before the physical Store has supplied a catalog
/// incarnation and bundle revision. It identifies the intended hold, without
/// asserting that the member is installed, retained, ready or authorized.
struct RemoteBundleHoldScope {
  distribution : RemoteBundleDistribution
  coordinator_authority : String
  workspace_id : String
  authority_scope_cid : String
  environment : String
  set_revision_cid : String
  runtime_bundle_cid : String
  site_key : String
  site_generation : Int
  attempt_id : String
  scope_cid : String
}

///|
fn valid_bundle_hold_scope(value : RemoteBundleHoldScope) -> Bool {
  bundle_distribution_json(value.distribution) is Ok(_) &&
  bounded(value.coordinator_authority, 512) &&
  bounded(value.workspace_id, 512) &&
  valid_cid(value.authority_scope_cid) &&
  bounded(value.environment, 512) &&
  valid_cid(value.set_revision_cid) &&
  bundle_distribution_contains(value.distribution, value.runtime_bundle_cid) &&
  bounded(value.site_key, 512) &&
  value.site_generation >= 0 &&
  flat_bundle_hold_attempt(value.attempt_id)
}

///|
fn bundle_hold_scope_body(
  value : RemoteBundleHoldScope,
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
    @encode.key(writer, "coordinator_authority")
    @encode.string_value(writer, value.coordinator_authority)
    @encode.key(writer, "distribution_cid")
    @encode.string_value(writer, value.distribution.distribution_cid)
    @encode.key(writer, "environment")
    @encode.string_value(writer, value.environment)
    @encode.key(writer, "runtime_bundle_cid")
    @encode.string_value(writer, value.runtime_bundle_cid)
    @encode.key(writer, "set_revision_cid")
    @encode.string_value(writer, value.set_revision_cid)
    @encode.key(writer, "site_generation")
    @encode.number_value(writer, value.site_generation.to_double())
    @encode.key(writer, "site_key")
    @encode.string_value(writer, value.site_key)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-runtime-bundle-hold-scope/0.1")
    @encode.key(writer, "workspace_id")
    @encode.string_value(writer, value.workspace_id)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidBundle)
  }
}

///|
pub fn prepare_bundle_hold_scope(
  distribution : RemoteBundleDistribution,
  coordinator_authority : String,
  workspace_id : String,
  authority_scope_cid : String,
  environment : String,
  set_revision_cid : String,
  runtime_bundle_cid : String,
  site_key : String,
  site_generation : Int,
  attempt_id : String,
) -> Result[RemoteBundleHoldScope, RemoteBundleIssue] {
  let pending : RemoteBundleHoldScope = {
    distribution,
    coordinator_authority,
    workspace_id,
    authority_scope_cid,
    environment,
    set_revision_cid,
    runtime_bundle_cid,
    site_key,
    site_generation,
    attempt_id,
    scope_cid: "pending",
  }
  if !valid_bundle_hold_scope(pending) {
    return Err(InvalidBundle)
  }
  let body = match bundle_hold_scope_body(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let scope_cid = match bundle_value_identity(body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, scope_cid, })
}

///|
pub fn bundle_hold_scope_identity(value : RemoteBundleHoldScope) -> String {
  value.scope_cid
}

///|
pub fn bundle_hold_scope_json(
  value : RemoteBundleHoldScope,
) -> Result[String, RemoteBundleIssue] {
  if !valid_bundle_hold_scope(value) {
    return Err(InvalidBundle)
  }
  let body = match bundle_hold_scope_body(value) {
    Ok(body) => body
    Err(issue) => return Err(issue)
  }
  match bundle_value_identity(body) {
    Ok(identity) if identity == value.scope_cid => Ok(body)
    Ok(_) => Err(BundleIdentityMismatch)
    Err(issue) => Err(issue)
  }
}

///|
pub fn bundle_hold_scope_projection(
  value : RemoteBundleHoldScope,
) -> Array[String] {
  [
    value.scope_cid,
    value.coordinator_authority,
    value.workspace_id,
    value.authority_scope_cid,
    value.environment,
    value.set_revision_cid,
    value.distribution.distribution_cid,
    value.runtime_bundle_cid,
    value.site_key,
    value.site_generation.to_string(),
    value.attempt_id,
  ]
}

///|
pub fn admit_bundle_hold_scope_json(
  distribution : RemoteBundleDistribution,
  body : String,
  claimed_scope_cid : String,
) -> Result[RemoteBundleHoldScope, RemoteBundleIssue] {
  try {
    let object = bundle_control_object(body, [
      "attempt_id", "authority_scope_cid", "coordinator_authority", "distribution_cid",
      "environment", "runtime_bundle_cid", "set_revision_cid", "site_generation",
      "site_key", "version", "workspace_id",
    ])
    if field(object, "version") != "actql-remote-runtime-bundle-hold-scope/0.1" ||
      field(object, "distribution_cid") != distribution.distribution_cid {
      raise RemoteBundleDecodeStop
    }
    let scope = match
      prepare_bundle_hold_scope(
        distribution,
        field(object, "coordinator_authority"),
        field(object, "workspace_id"),
        field(object, "authority_scope_cid"),
        field(object, "environment"),
        field(object, "set_revision_cid"),
        field(object, "runtime_bundle_cid"),
        field(object, "site_key"),
        bundle_hold_int(object, "site_generation"),
        field(object, "attempt_id"),
      ) {
      Ok(value) => value
      Err(_) => raise RemoteBundleDecodeStop
    }
    if bundle_hold_scope_json(scope) != Ok(body) {
      raise RemoteBundleDecodeStop
    }
    if scope.scope_cid != claimed_scope_cid {
      Err(BundleIdentityMismatch)
    } else {
      Ok(scope)
    }
  } catch {
    RemoteBundleDecodeStop => Err(InvalidBundle)
  }
}

///|
pub fn prepare_bundle_hold_binding_from_scope(
  scope : RemoteBundleHoldScope,
  catalog_incarnation : String,
  initial_revision : Int,
) -> Result[RemoteBundleHoldBinding, RemoteBundleIssue] {
  if bundle_hold_scope_json(scope) is Err(_) {
    return Err(InvalidBundle)
  }
  prepare_bundle_hold_binding(
    scope.distribution,
    catalog_incarnation,
    scope.coordinator_authority,
    scope.workspace_id,
    scope.authority_scope_cid,
    scope.environment,
    scope.set_revision_cid,
    scope.runtime_bundle_cid,
    scope.site_key,
    scope.site_generation,
    initial_revision,
    scope.attempt_id,
  )
}

///|
pub fn bundle_hold_binding_matches_scope(
  binding : RemoteBundleHoldBinding,
  scope : RemoteBundleHoldScope,
) -> Bool {
  bundle_hold_binding_json(binding) is Ok(_) &&
  bundle_hold_scope_json(scope) is Ok(_) &&
  binding.coordinator_authority == scope.coordinator_authority &&
  binding.workspace_id == scope.workspace_id &&
  binding.authority_scope_cid == scope.authority_scope_cid &&
  binding.environment == scope.environment &&
  binding.set_revision_cid == scope.set_revision_cid &&
  binding.distribution_cid == scope.distribution.distribution_cid &&
  binding.runtime_bundle_cid == scope.runtime_bundle_cid &&
  binding.site_key == scope.site_key &&
  binding.site_generation == scope.site_generation &&
  binding.attempt_id == scope.attempt_id
}

///|
/// Recover the exact query scope from a validated binding. The distribution
/// retained by the opaque binding has already passed canonical membership
/// admission; callers do not manufacture catalog or revision placeholders.
pub fn bundle_hold_binding_scope(
  binding : RemoteBundleHoldBinding,
) -> Result[RemoteBundleHoldScope, RemoteBundleIssue] {
  if bundle_hold_binding_json(binding) is Err(_) {
    return Err(InvalidBundle)
  }
  prepare_bundle_hold_scope(
    binding.distribution,
    binding.coordinator_authority,
    binding.workspace_id,
    binding.authority_scope_cid,
    binding.environment,
    binding.set_revision_cid,
    binding.runtime_bundle_cid,
    binding.site_key,
    binding.site_generation,
    binding.attempt_id,
  )
}
