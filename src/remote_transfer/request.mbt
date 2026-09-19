///|
/// The route changes physical transport, not the logical Transfer request.
pub(all) enum RemoteTransferRoute {
  DirectStream
  TransferStore
} derive(Eq, Debug)

///|
pub(all) enum RemoteTransferIssue {
  InvalidTransfer
  TransferIdentityMismatch
  TransferCapacityExceeded
} derive(Eq, Debug)

///|
/// One explicit preservation Transfer occurrence. The destination material is
/// absent because it does not exist until the physical operation succeeds.
struct RemoteTransferRequest {
  coordinator_authority : String
  transfer_attempt : String
  route : RemoteTransferRoute
  source_site_key : String
  source_site_generation : Int
  destination_site_key : String
  destination_site_generation : Int
  source_material_generation : String
  physical : @manifest.PhysicalManifest
  schema_contract_cid : String
  view_contract_cid : String
  codec_contract_cid : String
  physical_manifest_cid : String
  max_bytes : Int64
  expires_unix_ms : Int64
  source_grant_cid : String
  destination_grant_cid : String
  route_capability_cid : String
  request_cid : String
}

///|
fn valid_transfer_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn route_name(route : RemoteTransferRoute) -> String {
  match route {
    DirectStream => "direct"
    TransferStore => "store"
  }
}

///|
fn admitted_manifest(
  physical : @manifest.PhysicalManifest,
) -> @manifest.PhysicalManifest? {
  let chunks = physical.chunks
  let rebuilt = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    physical.schema_contract_cid,
    physical.view_contract_cid,
    physical.codec_contract_cid,
    physical.row_count,
    chunks.map(chunk => chunk.cid),
    chunks.map(chunk => chunk.byte_length),
    chunks.map(chunk => chunk.row_count),
    chunks.length(),
    physical.metadata_bytes,
    physical.referenced_bytes,
  )
  match rebuilt {
    Ok(value) =>
      if value.manifest_cid == physical.manifest_cid &&
        value.metadata_bytes == physical.metadata_bytes &&
        value.referenced_bytes == physical.referenced_bytes {
        Some(value)
      } else {
        None
      }
    Err(_) => None
  }
}

///|
fn valid_request_fields(request : RemoteTransferRequest) -> Bool {
  let physical = admitted_manifest(request.physical)
  !request.coordinator_authority.is_empty() &&
  !request.transfer_attempt.is_empty() &&
  !request.source_site_key.is_empty() &&
  request.source_site_generation >= 0 &&
  !request.destination_site_key.is_empty() &&
  request.destination_site_generation >= 0 &&
  !request.source_material_generation.is_empty() &&
  physical is Some(value) &&
  value.manifest_cid == request.physical_manifest_cid &&
  value.schema_contract_cid == request.schema_contract_cid &&
  value.view_contract_cid == request.view_contract_cid &&
  value.codec_contract_cid == request.codec_contract_cid &&
  valid_transfer_cid(request.schema_contract_cid) &&
  valid_transfer_cid(request.view_contract_cid) &&
  valid_transfer_cid(request.codec_contract_cid) &&
  valid_transfer_cid(request.physical_manifest_cid) &&
  request.max_bytes >= 0L &&
  request.expires_unix_ms > 0L &&
  valid_transfer_cid(request.source_grant_cid) &&
  valid_transfer_cid(request.destination_grant_cid) &&
  valid_transfer_cid(request.route_capability_cid)
}

///|
fn emit_request_body(
  request : RemoteTransferRequest,
) -> Result[String, RemoteTransferIssue] {
  let writer = @encode.writer(16384, 48, 2) catch {
    _ => return Err(InvalidTransfer)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "codec_contract_cid")
    @encode.string_value(writer, request.codec_contract_cid)
    @encode.key(writer, "coordinator_authority")
    @encode.string_value(writer, request.coordinator_authority)
    @encode.key(writer, "destination_grant_cid")
    @encode.string_value(writer, request.destination_grant_cid)
    @encode.key(writer, "destination_site_generation")
    @encode.number_value(
      writer,
      request.destination_site_generation.to_double(),
    )
    @encode.key(writer, "destination_site_key")
    @encode.string_value(writer, request.destination_site_key)
    @encode.key(writer, "expires_unix_ms")
    @encode.string_value(writer, request.expires_unix_ms.to_string())
    @encode.key(writer, "max_bytes")
    @encode.string_value(writer, request.max_bytes.to_string())
    @encode.key(writer, "physical_manifest_cid")
    @encode.string_value(writer, request.physical_manifest_cid)
    @encode.key(writer, "route")
    @encode.string_value(writer, route_name(request.route))
    @encode.key(writer, "route_capability_cid")
    @encode.string_value(writer, request.route_capability_cid)
    @encode.key(writer, "schema_contract_cid")
    @encode.string_value(writer, request.schema_contract_cid)
    @encode.key(writer, "source_grant_cid")
    @encode.string_value(writer, request.source_grant_cid)
    @encode.key(writer, "source_material_generation")
    @encode.string_value(writer, request.source_material_generation)
    @encode.key(writer, "source_site_generation")
    @encode.number_value(writer, request.source_site_generation.to_double())
    @encode.key(writer, "source_site_key")
    @encode.string_value(writer, request.source_site_key)
    @encode.key(writer, "transfer_attempt")
    @encode.string_value(writer, request.transfer_attempt)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-transfer-request/0.1")
    @encode.key(writer, "view_contract_cid")
    @encode.string_value(writer, request.view_contract_cid)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidTransfer)
  }
}

///|
fn request_identity(
  request : RemoteTransferRequest,
) -> Result[String, RemoteTransferIssue] {
  let body = match emit_request_body(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidTransfer)
  }
}

///|
/// Prepare one route-independent request from an already admitted physical
/// manifest. Direct and Store adapters must consume this same identity.
pub fn prepare_request(
  coordinator_authority : String,
  transfer_attempt : String,
  route : RemoteTransferRoute,
  source_site_key : String,
  source_site_generation : Int,
  destination_site_key : String,
  destination_site_generation : Int,
  source_material_generation : String,
  physical : @manifest.PhysicalManifest,
  max_bytes : Int64,
  expires_unix_ms : Int64,
  source_grant_cid : String,
  destination_grant_cid : String,
  route_capability_cid : String,
) -> Result[RemoteTransferRequest, RemoteTransferIssue] {
  let physical = match admitted_manifest(physical) {
    Some(value) => value
    None => return Err(InvalidTransfer)
  }
  let pending : RemoteTransferRequest = {
    coordinator_authority,
    transfer_attempt,
    route,
    source_site_key,
    source_site_generation,
    destination_site_key,
    destination_site_generation,
    source_material_generation,
    physical,
    schema_contract_cid: physical.schema_contract_cid,
    view_contract_cid: physical.view_contract_cid,
    codec_contract_cid: physical.codec_contract_cid,
    physical_manifest_cid: physical.manifest_cid,
    max_bytes,
    expires_unix_ms,
    source_grant_cid,
    destination_grant_cid,
    route_capability_cid,
    request_cid: "pending",
  }
  if !valid_request_fields(pending) {
    return Err(InvalidTransfer)
  }
  if physical.referenced_bytes > max_bytes {
    return Err(TransferCapacityExceeded)
  }
  let identity = match request_identity(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, request_cid: identity, })
}

///|
priv suberror RemoteTransferDecodeStop {
  RemoteTransferDecodeStop
}

///|
fn[T] transfer_decoded(
  value : Result[T, @decode.Issue],
) -> T raise RemoteTransferDecodeStop {
  match value {
    Ok(result) => result
    Err(_) => raise RemoteTransferDecodeStop
  }
}

///|
fn transfer_text(
  object : @decode.ObjectView,
  key : String,
) -> String raise RemoteTransferDecodeStop {
  transfer_decoded(
    @decode.text(transfer_decoded(@decode.required(object, key))),
  )
}

///|
fn transfer_int(
  object : @decode.ObjectView,
  key : String,
) -> Int raise RemoteTransferDecodeStop {
  let value = transfer_decoded(
    @decode.safe_integer(transfer_decoded(@decode.required(object, key))),
  )
  if value < 0L || value > 2147483647L {
    raise RemoteTransferDecodeStop
  }
  value.to_int()
}

///|
fn transfer_int64_text(value : String) -> Int64 raise RemoteTransferDecodeStop {
  if value.is_empty() {
    raise RemoteTransferDecodeStop
  }
  let mut result = 0L
  for index = 0; index < value.length(); index = index + 1 {
    let digit = value[index].to_int() - 48
    if digit < 0 ||
      digit > 9 ||
      result > (9223372036854775807L - digit.to_int64()) / 10L {
      raise RemoteTransferDecodeStop
    }
    result = result * 10L + digit.to_int64()
  }
  result
}

///|
fn admit_request_body(
  body : String,
  physical : @manifest.PhysicalManifest,
) -> RemoteTransferRequest raise RemoteTransferDecodeStop {
  let bytes = @utf8.encode(body)
  let node = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: 16384,
      max_nodes: 48,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => raise RemoteTransferDecodeStop
  }
  let cursor = transfer_decoded(
    @decode.admit(node, {
      max_nodes: 48,
      max_depth: 2,
      max_string_bytes: 16384,
      max_total_string_bytes: 16384,
    }),
  )
  let object = transfer_decoded(
    @decode.closed_object(cursor, [
      "codec_contract_cid", "coordinator_authority", "destination_grant_cid", "destination_site_generation",
      "destination_site_key", "expires_unix_ms", "max_bytes", "physical_manifest_cid",
      "route", "route_capability_cid", "schema_contract_cid", "source_grant_cid",
      "source_material_generation", "source_site_generation", "source_site_key",
      "transfer_attempt", "version", "view_contract_cid",
    ]),
  )
  if transfer_text(object, "version") != "actql-remote-transfer-request/0.1" {
    raise RemoteTransferDecodeStop
  }
  let route = match transfer_text(object, "route") {
    "direct" => DirectStream
    "store" => TransferStore
    _ => raise RemoteTransferDecodeStop
  }
  let request = match
    prepare_request(
      transfer_text(object, "coordinator_authority"),
      transfer_text(object, "transfer_attempt"),
      route,
      transfer_text(object, "source_site_key"),
      transfer_int(object, "source_site_generation"),
      transfer_text(object, "destination_site_key"),
      transfer_int(object, "destination_site_generation"),
      transfer_text(object, "source_material_generation"),
      physical,
      transfer_int64_text(transfer_text(object, "max_bytes")),
      transfer_int64_text(transfer_text(object, "expires_unix_ms")),
      transfer_text(object, "source_grant_cid"),
      transfer_text(object, "destination_grant_cid"),
      transfer_text(object, "route_capability_cid"),
    ) {
    Ok(value) => value
    Err(_) => raise RemoteTransferDecodeStop
  }
  let expected_fields = [
    request.codec_contract_cid,
    request.physical_manifest_cid,
    request.schema_contract_cid,
    request.view_contract_cid,
  ]
  let actual_fields = [
    transfer_text(object, "codec_contract_cid"),
    transfer_text(object, "physical_manifest_cid"),
    transfer_text(object, "schema_contract_cid"),
    transfer_text(object, "view_contract_cid"),
  ]
  if expected_fields != actual_fields || request_json(request) != Ok(body) {
    raise RemoteTransferDecodeStop
  }
  request
}

///|
/// Re-admit one canonical request and its separately canonical physical
/// manifest. Transport framing and identity remain independent.
pub fn admit_request_json(
  body : String,
  manifest_body : String,
  claimed_request_cid : String,
  claimed_manifest_cid : String,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[RemoteTransferRequest, RemoteTransferIssue] {
  let physical = match
    @manifest.admit_json(
      manifest_body, claimed_manifest_cid, max_chunks, max_manifest_bytes, max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidTransfer)
  }
  try {
    let request = admit_request_body(body, physical)
    if request.request_cid == claimed_request_cid {
      Ok(request)
    } else {
      Err(TransferIdentityMismatch)
    }
  } catch {
    RemoteTransferDecodeStop => Err(InvalidTransfer)
  }
}

///|
pub fn request_manifest_json(
  request : RemoteTransferRequest,
) -> Result[String, RemoteTransferIssue] {
  if !valid_request_fields(request) {
    return Err(InvalidTransfer)
  }
  match @manifest.manifest_json(request.physical) {
    Ok(value) => Ok(value)
    Err(_) => Err(InvalidTransfer)
  }
}

///|
/// Re-admit transport fields by recomputing the canonical request identity.
pub fn admit_request(
  coordinator_authority : String,
  transfer_attempt : String,
  route : RemoteTransferRoute,
  source_site_key : String,
  source_site_generation : Int,
  destination_site_key : String,
  destination_site_generation : Int,
  source_material_generation : String,
  physical : @manifest.PhysicalManifest,
  max_bytes : Int64,
  expires_unix_ms : Int64,
  source_grant_cid : String,
  destination_grant_cid : String,
  route_capability_cid : String,
  claimed_request_cid : String,
) -> Result[RemoteTransferRequest, RemoteTransferIssue] {
  let request = match
    prepare_request(
      coordinator_authority, transfer_attempt, route, source_site_key, source_site_generation,
      destination_site_key, destination_site_generation, source_material_generation,
      physical, max_bytes, expires_unix_ms, source_grant_cid, destination_grant_cid,
      route_capability_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if request.request_cid == claimed_request_cid {
    Ok(request)
  } else {
    Err(TransferIdentityMismatch)
  }
}

///|
pub fn request_json(
  request : RemoteTransferRequest,
) -> Result[String, RemoteTransferIssue] {
  if !valid_request_fields(request) {
    return Err(InvalidTransfer)
  }
  let identity = match request_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if identity != request.request_cid {
    return Err(TransferIdentityMismatch)
  }
  emit_request_body(request)
}

///|
pub fn request_cid(request : RemoteTransferRequest) -> String {
  request.request_cid
}

///|
pub fn request_route(request : RemoteTransferRequest) -> RemoteTransferRoute {
  request.route
}

///|
pub fn request_projection(request : RemoteTransferRequest) -> Array[String] {
  [
    request.request_cid,
    route_name(request.route),
    request.source_site_key,
    request.source_site_generation.to_string(),
    request.destination_site_key,
    request.destination_site_generation.to_string(),
    request.source_material_generation,
    request.physical_manifest_cid,
    request.max_bytes.to_string(),
    request.expires_unix_ms.to_string(),
    request.source_grant_cid,
    request.destination_grant_cid,
    request.route_capability_cid,
  ]
}
