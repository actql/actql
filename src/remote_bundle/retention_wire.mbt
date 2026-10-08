///|
/// Canonical control values for the existing authenticated Site channel. Their
/// identities bind the exact operation and payload; they grant no authority.
struct RemoteBundleCustodyRequest {
  distribution : RemoteBundleDistribution
  scope : RemoteBundleHoldScope
  binding : RemoteBundleHoldBinding?
  operation : String
  request_cid : String
}

///|
/// Context describes the Store's catalog before retention. Only an observation
/// response can report custody, and it is inseparable from its original request.
struct RemoteBundleCustodyResponse {
  request : RemoteBundleCustodyRequest
  binding : RemoteBundleHoldBinding
  observation : RemoteBundleHoldObservation?
  catalog_incarnation : String?
  record_revision : Int?
  response_cid : String
}

///|
fn valid_bundle_custody_operation(operation : String) -> Bool {
  operation == "retain" || operation == "query" || operation == "release"
}

///|
fn bundle_custody_request_body(
  value : RemoteBundleCustodyRequest,
) -> Result[String, RemoteBundleIssue] {
  let distribution = match bundle_distribution_json(value.distribution) {
    Ok(body) => body
    Err(issue) => return Err(issue)
  }
  let scope = match bundle_hold_scope_json(value.scope) {
    Ok(body) => body
    Err(issue) => return Err(issue)
  }
  if value.scope.distribution.distribution_cid !=
    value.distribution.distribution_cid ||
    !valid_bundle_custody_operation(value.operation) {
    return Err(InvalidBundle)
  }
  let binding = match value.binding {
    Some(binding) => {
      if !bundle_hold_binding_matches_scope(binding, value.scope) {
        return Err(InvalidBundle)
      }
      match bundle_hold_binding_json(binding) {
        Ok(body) => Some(body)
        Err(issue) => return Err(issue)
      }
    }
    None => {
      if value.operation != "query" {
        return Err(InvalidBundle)
      }
      None
    }
  }
  // The single outer writer charges escaped nested bodies against the same
  // total 64 KiB budget, rather than granting each component its own budget.
  let writer = @encode.writer(65536, 16, 1) catch {
    _ => return Err(InvalidBundle)
  }
  try {
    @encode.begin_object(writer)
    match (value.binding, binding) {
      (Some(value), Some(body)) => {
        @encode.key(writer, "binding")
        @encode.string_value(writer, body)
        @encode.key(writer, "binding_cid")
        @encode.string_value(writer, value.binding_cid)
      }
      _ => ()
    }
    @encode.key(writer, "distribution")
    @encode.string_value(writer, distribution)
    @encode.key(writer, "distribution_cid")
    @encode.string_value(writer, value.distribution.distribution_cid)
    @encode.key(writer, "operation")
    @encode.string_value(writer, value.operation)
    if value.binding is None {
      @encode.key(writer, "scope")
      @encode.string_value(writer, scope)
      @encode.key(writer, "scope_cid")
      @encode.string_value(writer, value.scope.scope_cid)
    }
    @encode.key(writer, "version")
    @encode.string_value(
      writer, "actql-remote-runtime-bundle-custody-request/0.1",
    )
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidBundle)
  }
}

///|
fn finish_bundle_custody_request(
  value : RemoteBundleCustodyRequest,
) -> Result[RemoteBundleCustodyRequest, RemoteBundleIssue] {
  let body = match bundle_custody_request_body(value) {
    Ok(body) => body
    Err(issue) => return Err(issue)
  }
  match bundle_value_identity(body) {
    Ok(request_cid) => Ok({ ..value, request_cid, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn prepare_bundle_custody_context_query(
  distribution : RemoteBundleDistribution,
  scope : RemoteBundleHoldScope,
) -> Result[RemoteBundleCustodyRequest, RemoteBundleIssue] {
  finish_bundle_custody_request({
    distribution,
    scope,
    binding: None,
    operation: "query",
    request_cid: "pending",
  })
}

///|
pub fn prepare_bundle_custody_request(
  distribution : RemoteBundleDistribution,
  binding : RemoteBundleHoldBinding,
  operation : String,
) -> Result[RemoteBundleCustodyRequest, RemoteBundleIssue] {
  let scope = match bundle_hold_binding_scope(binding) {
    Ok(scope) => scope
    Err(issue) => return Err(issue)
  }
  finish_bundle_custody_request({
    distribution,
    scope,
    binding: Some(binding),
    operation,
    request_cid: "pending",
  })
}

///|
pub fn bundle_custody_request_identity(
  value : RemoteBundleCustodyRequest,
) -> String {
  value.request_cid
}

///|
pub fn bundle_custody_request_json(
  value : RemoteBundleCustodyRequest,
) -> Result[String, RemoteBundleIssue] {
  let body = match bundle_custody_request_body(value) {
    Ok(body) => body
    Err(issue) => return Err(issue)
  }
  match bundle_value_identity(body) {
    Ok(cid) if cid == value.request_cid => Ok(body)
    Ok(_) => Err(BundleIdentityMismatch)
    Err(issue) => Err(issue)
  }
}

///|
pub fn bundle_custody_request_operation(
  value : RemoteBundleCustodyRequest,
) -> String {
  value.operation
}

///|
pub fn bundle_custody_request_distribution(
  value : RemoteBundleCustodyRequest,
) -> RemoteBundleDistribution {
  value.distribution
}

///|
pub fn bundle_custody_request_scope(
  value : RemoteBundleCustodyRequest,
) -> RemoteBundleHoldScope {
  value.scope
}

///|
pub fn bundle_custody_request_binding(
  value : RemoteBundleCustodyRequest,
) -> RemoteBundleHoldBinding? {
  value.binding
}

///|
fn[T] bundle_custody_decoded(
  result : Result[T, RemoteBundleIssue],
) -> T raise RemoteBundleDecodeStop {
  match result {
    Ok(value) => value
    Err(_) => raise RemoteBundleDecodeStop
  }
}

///|
pub fn admit_bundle_custody_request_json(
  body : String,
  claimed_request_cid : String,
) -> Result[RemoteBundleCustodyRequest, RemoteBundleIssue] {
  try {
    let object = bundle_control_object(body, [
      "binding", "binding_cid", "distribution", "distribution_cid", "operation",
      "scope", "scope_cid", "version",
    ])
    if field(object, "version") !=
      "actql-remote-runtime-bundle-custody-request/0.1" {
      raise RemoteBundleDecodeStop
    }
    let distribution = bundle_custody_decoded(
      admit_bundle_distribution_json(
        field(object, "distribution"),
        field(object, "distribution_cid"),
      ),
    )
    let operation = field(object, "operation")
    let request = if @decode.lookup(object, "scope") is Some(_) {
      if operation != "query" ||
        @decode.lookup(object, "binding") is Some(_) ||
        @decode.lookup(object, "binding_cid") is Some(_) {
        raise RemoteBundleDecodeStop
      }
      let scope = bundle_custody_decoded(
        admit_bundle_hold_scope_json(
          distribution,
          field(object, "scope"),
          field(object, "scope_cid"),
        ),
      )
      bundle_custody_decoded(
        prepare_bundle_custody_context_query(distribution, scope),
      )
    } else {
      if @decode.lookup(object, "scope_cid") is Some(_) {
        raise RemoteBundleDecodeStop
      }
      let binding = bundle_custody_decoded(
        admit_bundle_hold_binding_json(
          distribution,
          field(object, "binding"),
          field(object, "binding_cid"),
        ),
      )
      bundle_custody_decoded(
        prepare_bundle_custody_request(distribution, binding, operation),
      )
    }
    if bundle_custody_request_json(request) != Ok(body) {
      raise RemoteBundleDecodeStop
    }
    if request.request_cid != claimed_request_cid {
      Err(BundleIdentityMismatch)
    } else {
      Ok(request)
    }
  } catch {
    RemoteBundleDecodeStop => Err(InvalidBundle)
  }
}

///|
fn valid_bundle_custody_observation(
  binding : RemoteBundleHoldBinding,
  observation : RemoteBundleHoldObservation,
  catalog_incarnation : String?,
  record_revision : Int?,
) -> Bool {
  match catalog_incarnation {
    Some(catalog) if !valid_bundle_catalog_incarnation(catalog) => return false
    None if observation != BundleHoldUnavailable => return false
    _ => ()
  }
  match record_revision {
    Some(revision) if revision < 0 => return false
    _ => ()
  }
  if observation == BundleHoldUnavailable {
    return true
  }
  if catalog_incarnation != Some(binding.catalog_incarnation) {
    return false
  }
  match (observation, record_revision) {
    (BundleHoldRetained, Some(revision)) | (BundleHoldFenced, Some(revision)) =>
      revision > binding.initial_revision
    (BundleHoldUnresolved, Some(revision)) =>
      revision == binding.initial_revision
    _ => false
  }
}

///|
fn bundle_custody_response_body(
  value : RemoteBundleCustodyResponse,
) -> Result[String, RemoteBundleIssue] {
  if bundle_custody_request_json(value.request) is Err(_) ||
    !bundle_hold_binding_matches_scope(value.binding, value.request.scope) {
    return Err(InvalidBundle)
  }
  let binding_body = match bundle_hold_binding_json(value.binding) {
    Ok(body) => body
    Err(issue) => return Err(issue)
  }
  match (value.request.binding, value.observation) {
    (None, None) =>
      if value.request.operation != "query" ||
        value.catalog_incarnation != Some(value.binding.catalog_incarnation) ||
        value.record_revision != Some(value.binding.initial_revision) {
        return Err(InvalidBundle)
      }
    (Some(binding), Some(observation)) =>
      if binding.binding_cid != value.binding.binding_cid ||
        !valid_bundle_custody_observation(
          binding,
          observation,
          value.catalog_incarnation,
          value.record_revision,
        ) {
        return Err(InvalidBundle)
      }
    _ => return Err(InvalidBundle)
  }
  let writer = @encode.writer(65536, 16, 1) catch {
    _ => return Err(InvalidBundle)
  }
  try {
    @encode.begin_object(writer)
    if value.observation is None {
      @encode.key(writer, "binding")
      @encode.string_value(writer, binding_body)
    }
    @encode.key(writer, "binding_cid")
    @encode.string_value(writer, value.binding.binding_cid)
    match value.observation {
      Some(observation) => {
        @encode.key(writer, "catalog_incarnation")
        match value.catalog_incarnation {
          Some(catalog) => @encode.string_value(writer, catalog)
          None => @encode.null_value(writer)
        }
        @encode.key(writer, "kind")
        @encode.string_value(writer, "observation")
        @encode.key(writer, "observation")
        @encode.string_value(
          writer,
          bundle_hold_observation_projection(observation),
        )
        @encode.key(writer, "record_revision")
        match value.record_revision {
          Some(revision) => @encode.number_value(writer, revision.to_double())
          None => @encode.null_value(writer)
        }
      }
      None => {
        @encode.key(writer, "kind")
        @encode.string_value(writer, "context")
      }
    }
    @encode.key(writer, "request_cid")
    @encode.string_value(writer, value.request.request_cid)
    @encode.key(writer, "version")
    @encode.string_value(
      writer, "actql-remote-runtime-bundle-custody-response/0.1",
    )
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidBundle)
  }
}

///|
fn finish_bundle_custody_response(
  value : RemoteBundleCustodyResponse,
) -> Result[RemoteBundleCustodyResponse, RemoteBundleIssue] {
  let body = match bundle_custody_response_body(value) {
    Ok(body) => body
    Err(issue) => return Err(issue)
  }
  match bundle_value_identity(body) {
    Ok(response_cid) => Ok({ ..value, response_cid, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn prepare_bundle_custody_context_response(
  request : RemoteBundleCustodyRequest,
  binding : RemoteBundleHoldBinding,
) -> Result[RemoteBundleCustodyResponse, RemoteBundleIssue] {
  finish_bundle_custody_response({
    request,
    binding,
    observation: None,
    catalog_incarnation: Some(binding.catalog_incarnation),
    record_revision: Some(binding.initial_revision),
    response_cid: "pending",
  })
}

///|
pub fn prepare_bundle_custody_response(
  request : RemoteBundleCustodyRequest,
  observation : RemoteBundleHoldObservation,
  catalog_incarnation : String?,
  record_revision : Int?,
) -> Result[RemoteBundleCustodyResponse, RemoteBundleIssue] {
  guard request.binding is Some(binding) else { return Err(InvalidBundle) }
  finish_bundle_custody_response({
    request,
    binding,
    observation: Some(observation),
    catalog_incarnation,
    record_revision,
    response_cid: "pending",
  })
}

///|
/// String admission for adapters. The shared owner retains the closed mapping
/// and proof checks; adapters do not interpret enum representation or truthiness.
pub fn prepare_bundle_custody_response_fields(
  request : RemoteBundleCustodyRequest,
  observation : String,
  catalog_incarnation : String?,
  record_revision : Int?,
) -> Result[RemoteBundleCustodyResponse, RemoteBundleIssue] {
  let observation = match observation {
    "retained" => BundleHoldRetained
    "fenced" => BundleHoldFenced
    "unresolved" => BundleHoldUnresolved
    "unavailable" => BundleHoldUnavailable
    _ => return Err(InvalidBundle)
  }
  prepare_bundle_custody_response(
    request, observation, catalog_incarnation, record_revision,
  )
}

///|
pub fn bundle_custody_response_identity(
  value : RemoteBundleCustodyResponse,
) -> String {
  value.response_cid
}

///|
pub fn bundle_custody_response_json(
  value : RemoteBundleCustodyResponse,
) -> Result[String, RemoteBundleIssue] {
  let body = match bundle_custody_response_body(value) {
    Ok(body) => body
    Err(issue) => return Err(issue)
  }
  match bundle_value_identity(body) {
    Ok(cid) if cid == value.response_cid => Ok(body)
    Ok(_) => Err(BundleIdentityMismatch)
    Err(issue) => Err(issue)
  }
}

///|
pub fn bundle_custody_response_kind(
  value : RemoteBundleCustodyResponse,
) -> String {
  if value.observation is None {
    "context"
  } else {
    "observation"
  }
}

///|
pub fn bundle_custody_response_binding(
  value : RemoteBundleCustodyResponse,
) -> RemoteBundleHoldBinding {
  value.binding
}

///|
pub fn bundle_custody_response_observation(
  value : RemoteBundleCustodyResponse,
) -> RemoteBundleHoldObservation? {
  value.observation
}

///|
pub fn bundle_custody_response_observation_text(
  value : RemoteBundleCustodyResponse,
) -> String {
  match value.observation {
    Some(observation) => bundle_hold_observation_projection(observation)
    None => ""
  }
}

///|
pub fn bundle_custody_response_catalog_incarnation(
  value : RemoteBundleCustodyResponse,
) -> String? {
  value.catalog_incarnation
}

///|
pub fn bundle_custody_response_catalog_incarnation_text(
  value : RemoteBundleCustodyResponse,
) -> String {
  value.catalog_incarnation.unwrap_or("")
}

///|
pub fn bundle_custody_response_record_revision(
  value : RemoteBundleCustodyResponse,
) -> Int? {
  value.record_revision
}

///|
pub fn bundle_custody_response_record_revision_text(
  value : RemoteBundleCustodyResponse,
) -> String {
  match value.record_revision {
    Some(revision) => revision.to_string()
    None => ""
  }
}

///|
pub fn admit_bundle_custody_response_json(
  request : RemoteBundleCustodyRequest,
  body : String,
  claimed_response_cid : String,
) -> Result[RemoteBundleCustodyResponse, RemoteBundleIssue] {
  if bundle_custody_request_json(request) is Err(_) {
    return Err(InvalidBundle)
  }
  try {
    let names = match request.binding {
      None => ["binding", "binding_cid", "kind", "request_cid", "version"]
      Some(_) =>
        [
          "binding_cid", "catalog_incarnation", "kind", "observation", "record_revision",
          "request_cid", "version",
        ]
    }
    let object = bundle_control_object(body, names)
    if field(object, "version") !=
      "actql-remote-runtime-bundle-custody-response/0.1" {
      raise RemoteBundleDecodeStop
    }
    if field(object, "request_cid") != request.request_cid {
      return Err(BundleIdentityMismatch)
    }
    let response = match request.binding {
      None => {
        if field(object, "kind") != "context" {
          raise RemoteBundleDecodeStop
        }
        let binding = bundle_custody_decoded(
          admit_bundle_hold_binding_json(
            request.distribution,
            field(object, "binding"),
            field(object, "binding_cid"),
          ),
        )
        bundle_custody_decoded(
          prepare_bundle_custody_context_response(request, binding),
        )
      }
      Some(binding) => {
        if field(object, "kind") != "observation" {
          raise RemoteBundleDecodeStop
        }
        if field(object, "binding_cid") != binding.binding_cid {
          return Err(BundleIdentityMismatch)
        }
        let revision = match @decode.lookup(object, "record_revision") {
          Some(cursor) =>
            if @decode.is_null(cursor) {
              None
            } else {
              Some(bundle_hold_int(object, "record_revision"))
            }
          None => raise RemoteBundleDecodeStop
        }
        let catalog = match @decode.lookup(object, "catalog_incarnation") {
          Some(cursor) =>
            if @decode.is_null(cursor) {
              None
            } else {
              Some(field(object, "catalog_incarnation"))
            }
          None => raise RemoteBundleDecodeStop
        }
        bundle_custody_decoded(
          prepare_bundle_custody_response_fields(
            request,
            field(object, "observation"),
            catalog,
            revision,
          ),
        )
      }
    }
    if bundle_custody_response_json(response) != Ok(body) {
      raise RemoteBundleDecodeStop
    }
    if response.response_cid != claimed_response_cid {
      Err(BundleIdentityMismatch)
    } else {
      Ok(response)
    }
  } catch {
    RemoteBundleDecodeStop => Err(InvalidBundle)
  }
}
