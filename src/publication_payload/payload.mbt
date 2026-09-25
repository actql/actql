///|
pub(all) enum PublicationPayloadIssue {
  InvalidRequest
  InvalidRecord
  InvalidTransition
  IdentityMismatch
  StateCollision
} derive(Debug)

///|
pub(all) enum PublicationPayloadState {
  Intent
  Reserved
  Writing
  Sealed
  Reclaiming
  Reclaimed
} derive(Eq, Debug)

///|
struct PublicationPayloadRequest {
  store_authority_cid : String
  publication_attempt_cid : String
  material_generation_cid : String
  result_definition_cid : String
  logical_relation_cid : String
  result_schema_cid : String
  ordering_evidence_cid : String
  durable_codec_cid : String
  max_bytes : Int64
  row_count : Int64
  request_cid : String
  body : String
}

///|
pub(all) struct PublicationPayloadGeneration {
  device : UInt64
  inode : UInt64
  size : Int64
} derive(Eq, Debug)

///|
pub(all) struct PublicationPayloadOwnership {
  device : UInt64
  inode : UInt64
} derive(Eq, Debug)

///|
struct PublicationPayloadRecord {
  request : PublicationPayloadRequest
  mut revision : Int
  mut state : PublicationPayloadState
  mut ownership : PublicationPayloadOwnership?
  mut generation : PublicationPayloadGeneration?
  mut opaque_ownership_cid : String?
  mut opaque_generation_cid : String?
  mut actual_bytes : Int64
  mut physical_digest : String
}

///|
struct PublicationPayloadTransition {
  record : PublicationPayloadRecord
  expected_revision : Int
  next_state : PublicationPayloadState
  next_ownership : PublicationPayloadOwnership?
  next_generation : PublicationPayloadGeneration?
  next_opaque_ownership_cid : String?
  next_opaque_generation_cid : String?
  next_actual_bytes : Int64
  next_physical_digest : String
}

///|
struct DurablePublicationPayloadRecord {
  request : PublicationPayloadRequest
  revision : Int
  state : PublicationPayloadState
  ownership : PublicationPayloadOwnership?
  generation : PublicationPayloadGeneration?
  opaque_ownership_cid : String?
  opaque_generation_cid : String?
  actual_bytes : Int64
  physical_digest : String
  body : String
}

///|
priv suberror PayloadStop {
  PayloadStop
}

///|
fn valid_sha256_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let character = value[index]
    if !((character >= '0' && character <= '9') ||
      (character >= 'a' && character <= 'f')) {
      return false
    }
  }
  true
}

///|
fn emit_payload_request(
  store_authority_cid : String,
  publication_attempt_cid : String,
  material_generation_cid : String,
  result_definition_cid : String,
  logical_relation_cid : String,
  result_schema_cid : String,
  ordering_evidence_cid : String,
  durable_codec_cid : String,
  max_bytes : Int64,
  row_count : Int64,
) -> Result[(String, String), PublicationPayloadIssue] {
  if !valid_sha256_cid(store_authority_cid) ||
    !valid_sha256_cid(publication_attempt_cid) ||
    !valid_sha256_cid(material_generation_cid) ||
    !valid_sha256_cid(result_definition_cid) ||
    !valid_sha256_cid(logical_relation_cid) ||
    !valid_sha256_cid(result_schema_cid) ||
    !valid_sha256_cid(ordering_evidence_cid) ||
    !valid_sha256_cid(durable_codec_cid) ||
    max_bytes <= 0L ||
    row_count < 0L {
    return Err(InvalidRequest)
  }
  let writer = @encode.hashing_writer(32768, 64, 2) catch {
    _ => return Err(InvalidRequest)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "durable_codec_cid")
    @encode.string_value(writer, durable_codec_cid)
    @encode.key(writer, "logical_relation_cid")
    @encode.string_value(writer, logical_relation_cid)
    @encode.key(writer, "material_generation_cid")
    @encode.string_value(writer, material_generation_cid)
    @encode.key(writer, "max_bytes")
    @encode.string_value(writer, max_bytes.to_string())
    @encode.key(writer, "ordering_evidence_cid")
    @encode.string_value(writer, ordering_evidence_cid)
    @encode.key(writer, "publication_attempt_cid")
    @encode.string_value(writer, publication_attempt_cid)
    @encode.key(writer, "result_definition_cid")
    @encode.string_value(writer, result_definition_cid)
    @encode.key(writer, "result_schema_cid")
    @encode.string_value(writer, result_schema_cid)
    @encode.key(writer, "row_count")
    @encode.string_value(writer, row_count.to_string())
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, store_authority_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-publication-payload-request/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidRequest)
  }
  let (digest, _, _) = @encode.finish_hash_usage(writer) catch {
    _ => return Err(InvalidRequest)
  }
  let body_writer = @encode.writer(32768, 64, 2) catch {
    _ => return Err(InvalidRequest)
  }
  try {
    @encode.begin_object(body_writer)
    @encode.key(body_writer, "durable_codec_cid")
    @encode.string_value(body_writer, durable_codec_cid)
    @encode.key(body_writer, "logical_relation_cid")
    @encode.string_value(body_writer, logical_relation_cid)
    @encode.key(body_writer, "material_generation_cid")
    @encode.string_value(body_writer, material_generation_cid)
    @encode.key(body_writer, "max_bytes")
    @encode.string_value(body_writer, max_bytes.to_string())
    @encode.key(body_writer, "ordering_evidence_cid")
    @encode.string_value(body_writer, ordering_evidence_cid)
    @encode.key(body_writer, "publication_attempt_cid")
    @encode.string_value(body_writer, publication_attempt_cid)
    @encode.key(body_writer, "result_definition_cid")
    @encode.string_value(body_writer, result_definition_cid)
    @encode.key(body_writer, "result_schema_cid")
    @encode.string_value(body_writer, result_schema_cid)
    @encode.key(body_writer, "row_count")
    @encode.string_value(body_writer, row_count.to_string())
    @encode.key(body_writer, "store_authority_cid")
    @encode.string_value(body_writer, store_authority_cid)
    @encode.key(body_writer, "version")
    @encode.string_value(body_writer, "actql-publication-payload-request/0.1")
    @encode.end_object(body_writer)
  } catch {
    _ => return Err(InvalidRequest)
  }
  let body = @encode.finish(body_writer) catch {
    _ => return Err(InvalidRequest)
  }
  Ok((body, "sha256:" + digest))
}

///|
pub fn prepare_publication_payload_request(
  store_authority_cid : String,
  publication_attempt_cid : String,
  material_generation_cid : String,
  result_definition_cid : String,
  logical_relation_cid : String,
  result_schema_cid : String,
  ordering_evidence_cid : String,
  durable_codec_cid : String,
  max_bytes : Int64,
  row_count : Int64,
) -> Result[PublicationPayloadRequest, PublicationPayloadIssue] {
  match
    emit_payload_request(
      store_authority_cid, publication_attempt_cid, material_generation_cid, result_definition_cid,
      logical_relation_cid, result_schema_cid, ordering_evidence_cid, durable_codec_cid,
      max_bytes, row_count,
    ) {
    Ok((body, request_cid)) =>
      Ok({
        store_authority_cid,
        publication_attempt_cid,
        material_generation_cid,
        result_definition_cid,
        logical_relation_cid,
        result_schema_cid,
        ordering_evidence_cid,
        durable_codec_cid,
        max_bytes,
        row_count,
        request_cid,
        body,
      })
    Err(issue) => Err(issue)
  }
}

///|
pub fn publication_payload_request_identity(
  request : PublicationPayloadRequest,
) -> String {
  request.request_cid
}

///|
/// Return the canonical request body used by durable publication and remote
/// output journals. The body carries no Store authority beyond the admitted
/// request itself.
pub fn publication_payload_request_json(
  request : PublicationPayloadRequest,
) -> Result[String, PublicationPayloadIssue] {
  match
    emit_payload_request(
      request.store_authority_cid,
      request.publication_attempt_cid,
      request.material_generation_cid,
      request.result_definition_cid,
      request.logical_relation_cid,
      request.result_schema_cid,
      request.ordering_evidence_cid,
      request.durable_codec_cid,
      request.max_bytes,
      request.row_count,
    ) {
    Ok((body, identity)) if body == request.body &&
      identity == request.request_cid => Ok(body)
    _ => Err(IdentityMismatch)
  }
}

///|
pub fn publication_payload_material_identity(
  request : PublicationPayloadRequest,
) -> String {
  request.material_generation_cid
}

///|
pub fn publication_payload_request_max_bytes(
  request : PublicationPayloadRequest,
) -> Int64 {
  request.max_bytes
}

///|
pub fn publication_payload_request_store_authority(
  request : PublicationPayloadRequest,
) -> String {
  request.store_authority_cid
}

///|
pub fn publication_payload_request_attempt(
  request : PublicationPayloadRequest,
) -> String {
  request.publication_attempt_cid
}

///|
pub fn publication_payload_request_result_definition(
  request : PublicationPayloadRequest,
) -> String {
  request.result_definition_cid
}

///|
pub fn publication_payload_request_logical_relation(
  request : PublicationPayloadRequest,
) -> String {
  request.logical_relation_cid
}

///|
pub fn publication_payload_request_schema(
  request : PublicationPayloadRequest,
) -> String {
  request.result_schema_cid
}

///|
pub fn publication_payload_request_ordering_evidence(
  request : PublicationPayloadRequest,
) -> String {
  request.ordering_evidence_cid
}

///|
pub fn publication_payload_request_codec(
  request : PublicationPayloadRequest,
) -> String {
  request.durable_codec_cid
}

///|
pub fn publication_payload_request_row_count(
  request : PublicationPayloadRequest,
) -> Int64 {
  request.row_count
}

///|
pub fn publication_payload_staging_name(
  request : PublicationPayloadRequest,
) -> String {
  "stage-" + request.material_generation_cid[7:].to_owned()
}

///|
pub fn publication_payload_object_name(
  request : PublicationPayloadRequest,
) -> String {
  "payload-" + request.material_generation_cid[7:].to_owned()
}

///|
pub fn prepare_publication_payload_record(
  request : PublicationPayloadRequest,
) -> PublicationPayloadRecord {
  {
    request,
    revision: 0,
    state: Intent,
    ownership: None,
    generation: None,
    opaque_ownership_cid: None,
    opaque_generation_cid: None,
    actual_bytes: -1L,
    physical_digest: "",
  }
}

///|
fn prepare_payload_transition(
  record : PublicationPayloadRecord,
  next_state : PublicationPayloadState,
  next_ownership : PublicationPayloadOwnership?,
  next_generation : PublicationPayloadGeneration?,
  next_opaque_ownership_cid : String?,
  next_opaque_generation_cid : String?,
  next_actual_bytes : Int64,
  next_physical_digest : String,
) -> PublicationPayloadTransition {
  {
    record,
    expected_revision: record.revision,
    next_state,
    next_ownership,
    next_generation,
    next_opaque_ownership_cid,
    next_opaque_generation_cid,
    next_actual_bytes,
    next_physical_digest,
  }
}

///|
pub fn prepare_publication_payload_reserved(
  record : PublicationPayloadRecord,
) -> Result[PublicationPayloadTransition, PublicationPayloadIssue] {
  if record.state != Intent {
    return Err(InvalidTransition)
  }
  Ok(prepare_payload_transition(record, Reserved, None, None, None, None, -1L, ""))
}

///|
pub fn prepare_publication_payload_writing(
  record : PublicationPayloadRecord,
) -> Result[PublicationPayloadTransition, PublicationPayloadIssue] {
  if record.state != Reserved {
    return Err(InvalidTransition)
  }
  Ok(prepare_payload_transition(record, Writing, None, None, None, None, -1L, ""))
}

///|
/// Persist the exact allocation obtained by a successful exclusive create.
/// Its size may change while writing, so ownership is distinct from a sealed
/// generation.
pub fn prepare_publication_payload_owned(
  record : PublicationPayloadRecord,
  ownership : PublicationPayloadOwnership,
) -> Result[PublicationPayloadTransition, PublicationPayloadIssue] {
  if record.state != Writing ||
    record.ownership is Some(_) ||
    record.generation is Some(_) ||
    record.opaque_ownership_cid is Some(_) ||
    record.opaque_generation_cid is Some(_) {
    return Err(InvalidTransition)
  }
  Ok(
    prepare_payload_transition(record, Writing, Some(ownership), None, None, None, -1L, ""),
  )
}

///|
/// Claim one exact non-filesystem allocation after the adapter has proved
/// exclusive ownership. The CID identifies physical custody, not Result data.
pub fn prepare_publication_payload_opaque_owned(
  record : PublicationPayloadRecord,
  custody_cid : String,
) -> Result[PublicationPayloadTransition, PublicationPayloadIssue] {
  if record.state != Writing ||
    record.ownership is Some(_) ||
    record.generation is Some(_) ||
    record.opaque_ownership_cid is Some(_) ||
    record.opaque_generation_cid is Some(_) ||
    !valid_sha256_cid(custody_cid) {
    return Err(InvalidTransition)
  }
  Ok(prepare_payload_transition(
    record, Writing, None, None, Some(custody_cid), None, -1L, "",
  ))
}

///|
pub fn prepare_publication_payload_sealed(
  record : PublicationPayloadRecord,
  generation : PublicationPayloadGeneration,
  physical_digest : String,
) -> Result[PublicationPayloadTransition, PublicationPayloadIssue] {
  guard record.ownership is Some(ownership) else {
    return Err(InvalidTransition)
  }
  if record.state != Writing ||
    ownership.device != generation.device ||
    ownership.inode != generation.inode ||
    record.opaque_ownership_cid is Some(_) ||
    record.opaque_generation_cid is Some(_) ||
    generation.size < 0L ||
    generation.size > record.request.max_bytes ||
    !valid_sha256_cid(physical_digest) {
    return Err(InvalidTransition)
  }
  Ok(
    prepare_payload_transition(
      record,
      Sealed,
      record.ownership,
      Some(generation),
      None,
      None,
      generation.size,
      physical_digest,
    ),
  )
}

///|
/// Seal the same opaque physical generation whose ownership was recorded.
/// The environment adapter must verify current bytes before this transition.
pub fn prepare_publication_payload_opaque_sealed(
  record : PublicationPayloadRecord,
  custody_cid : String,
  actual_bytes : Int64,
  physical_digest : String,
) -> Result[PublicationPayloadTransition, PublicationPayloadIssue] {
  if record.state != Writing ||
    record.ownership is Some(_) ||
    record.generation is Some(_) ||
    record.opaque_ownership_cid != Some(custody_cid) ||
    record.opaque_generation_cid is Some(_) ||
    !valid_sha256_cid(custody_cid) ||
    actual_bytes < 0L || actual_bytes > record.request.max_bytes ||
    !valid_sha256_cid(physical_digest) {
    return Err(InvalidTransition)
  }
  Ok(prepare_payload_transition(
    record, Sealed, None, None, Some(custody_cid), Some(custody_cid),
    actual_bytes, physical_digest,
  ))
}

///|
pub fn prepare_publication_payload_reclaiming(
  record : PublicationPayloadRecord,
  discovered_generation? : PublicationPayloadGeneration? = None,
) -> Result[PublicationPayloadTransition, PublicationPayloadIssue] {
  if record.state == Reclaimed || record.state == Reclaiming ||
    record.opaque_ownership_cid is Some(_) ||
    record.opaque_generation_cid is Some(_) {
    return Err(InvalidTransition)
  }
  let generation = match record.generation {
    Some(value) => {
      if discovered_generation is Some(other) && other != value {
        return Err(StateCollision)
      }
      Some(value)
    }
    None =>
      match (record.ownership, discovered_generation) {
        (None, None) => None
        (Some(_), None) => None
        (Some(owner), Some(value)) if owner.device == value.device &&
          owner.inode == value.inode => None
        _ => return Err(StateCollision)
      }
  }
  Ok(
    prepare_payload_transition(
      record,
      Reclaiming,
      record.ownership,
      generation,
      None,
      None,
      record.actual_bytes,
      record.physical_digest,
    ),
  )
}

///|
/// A caller may reclaim only the exact opaque custody it recorded. An
/// unknown or changed physical generation remains a reconciliation failure.
pub fn prepare_publication_payload_opaque_reclaiming(
  record : PublicationPayloadRecord,
  discovered_custody_cid : String,
) -> Result[PublicationPayloadTransition, PublicationPayloadIssue] {
  if record.state == Reclaimed || record.state == Reclaiming ||
    record.ownership is Some(_) || record.generation is Some(_) ||
    record.opaque_ownership_cid != Some(discovered_custody_cid) ||
    !valid_sha256_cid(discovered_custody_cid) ||
    (record.opaque_generation_cid is Some(sealed_cid) &&
      sealed_cid != discovered_custody_cid) {
    return Err(StateCollision)
  }
  Ok(prepare_payload_transition(
    record, Reclaiming, None, None, record.opaque_ownership_cid,
    record.opaque_generation_cid, record.actual_bytes,
    record.physical_digest,
  ))
}

///|
pub fn prepare_publication_payload_reclaimed(
  record : PublicationPayloadRecord,
) -> Result[PublicationPayloadTransition, PublicationPayloadIssue] {
  if record.state != Reclaiming {
    return Err(InvalidTransition)
  }
  Ok(
    prepare_payload_transition(
      record,
      Reclaimed,
      record.ownership,
      record.generation,
      record.opaque_ownership_cid,
      record.opaque_generation_cid,
      record.actual_bytes,
      record.physical_digest,
    ),
  )
}

///|
pub fn commit_publication_payload_transition(
  transition : PublicationPayloadTransition,
  durable : Bool,
) -> Result[PublicationPayloadRecord, PublicationPayloadIssue] {
  if !durable {
    return Err(InvalidTransition)
  }
  let record = transition.record
  if record.revision != transition.expected_revision {
    return Err(StateCollision)
  }
  record.revision += 1
  record.state = transition.next_state
  record.ownership = transition.next_ownership
  record.generation = transition.next_generation
  record.opaque_ownership_cid = transition.next_opaque_ownership_cid
  record.opaque_generation_cid = transition.next_opaque_generation_cid
  record.actual_bytes = transition.next_actual_bytes
  record.physical_digest = transition.next_physical_digest
  Ok(record)
}

///|
pub fn publication_payload_record_state(
  record : PublicationPayloadRecord,
) -> PublicationPayloadState {
  record.state
}

///|
pub fn publication_payload_record_revision(
  record : PublicationPayloadRecord,
) -> Int {
  record.revision
}

///|
pub fn publication_payload_record_request(
  record : PublicationPayloadRecord,
) -> PublicationPayloadRequest {
  record.request
}

///|
pub fn publication_payload_record_generation(
  record : PublicationPayloadRecord,
) -> PublicationPayloadGeneration? {
  record.generation
}

///|
pub fn publication_payload_record_opaque_generation(
  record : PublicationPayloadRecord,
) -> String? {
  record.opaque_generation_cid
}

///|
pub fn publication_payload_record_opaque_ownership(
  record : PublicationPayloadRecord,
) -> String? {
  record.opaque_ownership_cid
}

///|
pub fn publication_payload_record_ownership(
  record : PublicationPayloadRecord,
) -> PublicationPayloadOwnership? {
  record.ownership
}

///|
pub fn publication_payload_record_digest(
  record : PublicationPayloadRecord,
) -> String {
  record.physical_digest
}

///|
pub fn publication_payload_record_actual_bytes(
  record : PublicationPayloadRecord,
) -> Int64 {
  record.actual_bytes
}

///|
fn state_text(state : PublicationPayloadState) -> String {
  match state {
    Intent => "intent"
    Reserved => "reserved"
    Writing => "writing"
    Sealed => "sealed"
    Reclaiming => "reclaiming"
    Reclaimed => "reclaimed"
  }
}

///|
fn parse_state(value : String) -> PublicationPayloadState raise PayloadStop {
  match value {
    "intent" => Intent
    "reserved" => Reserved
    "writing" => Writing
    "sealed" => Sealed
    "reclaiming" => Reclaiming
    "reclaimed" => Reclaimed
    _ => raise PayloadStop
  }
}

///|
fn emit_payload_record(
  request : PublicationPayloadRequest,
  revision : Int,
  state : PublicationPayloadState,
  ownership : PublicationPayloadOwnership?,
  generation : PublicationPayloadGeneration?,
  opaque_ownership_cid : String?,
  opaque_generation_cid : String?,
  actual_bytes : Int64,
  physical_digest : String,
) -> Result[String, PublicationPayloadIssue] {
  if revision < 0 || actual_bytes < -1L {
    return Err(InvalidRecord)
  }
  if opaque_ownership_cid is Some(_) || opaque_generation_cid is Some(_) {
    if ownership is Some(_) || generation is Some(_) {
      return Err(InvalidRecord)
    }
    let writer = @encode.writer(65536, 32, 2) catch {
      _ => return Err(InvalidRecord)
    }
    try {
      @encode.begin_object(writer)
      @encode.key(writer, "actual_bytes")
      @encode.string_value(writer, actual_bytes.to_string())
      @encode.key(writer, "custody_generation_cid")
      @encode.string_value(writer, opaque_generation_cid.unwrap_or(""))
      @encode.key(writer, "custody_ownership_cid")
      @encode.string_value(writer, opaque_ownership_cid.unwrap_or(""))
      @encode.key(writer, "physical_digest")
      @encode.string_value(writer, physical_digest)
      @encode.key(writer, "request_cid")
      @encode.string_value(writer, request.request_cid)
      @encode.key(writer, "request_json")
      @encode.string_value(writer, request.body)
      @encode.key(writer, "revision")
      @encode.string_value(writer, revision.to_string())
      @encode.key(writer, "state")
      @encode.string_value(writer, state_text(state))
      @encode.key(writer, "version")
      @encode.string_value(writer, "actql-publication-payload-record/0.3")
      @encode.end_object(writer)
    } catch {
      _ => return Err(InvalidRecord)
    }
    return Ok(@encode.finish(writer) catch { _ => return Err(InvalidRecord) })
  }
  let writer = @encode.writer(65536, 32, 2) catch {
    _ => return Err(InvalidRecord)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "actual_bytes")
    @encode.string_value(writer, actual_bytes.to_string())
    @encode.key(writer, "device")
    @encode.string_value(
      writer,
      match generation {
        Some(value) => value.device.to_string()
        None => ""
      },
    )
    @encode.key(writer, "inode")
    @encode.string_value(
      writer,
      match generation {
        Some(value) => value.inode.to_string()
        None => ""
      },
    )
    @encode.key(writer, "ownership_device")
    @encode.string_value(
      writer,
      match ownership {
        Some(value) => value.device.to_string()
        None => ""
      },
    )
    @encode.key(writer, "ownership_inode")
    @encode.string_value(
      writer,
      match ownership {
        Some(value) => value.inode.to_string()
        None => ""
      },
    )
    @encode.key(writer, "physical_digest")
    @encode.string_value(writer, physical_digest)
    @encode.key(writer, "request_cid")
    @encode.string_value(writer, request.request_cid)
    @encode.key(writer, "request_json")
    @encode.string_value(writer, request.body)
    @encode.key(writer, "revision")
    @encode.string_value(writer, revision.to_string())
    @encode.key(writer, "state")
    @encode.string_value(writer, state_text(state))
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-publication-payload-record/0.2")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidRecord)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidRecord) })
}

///|
pub fn publication_payload_record_durable_json(
  record : PublicationPayloadRecord,
) -> Result[String, PublicationPayloadIssue] {
  emit_payload_record(
    record.request,
    record.revision,
    record.state,
    record.ownership,
    record.generation,
    record.opaque_ownership_cid,
    record.opaque_generation_cid,
    record.actual_bytes,
    record.physical_digest,
  )
}

///|
pub fn publication_payload_transition_durable_json(
  transition : PublicationPayloadTransition,
) -> Result[String, PublicationPayloadIssue] {
  emit_payload_record(
    transition.record.request,
    transition.expected_revision + 1,
    transition.next_state,
    transition.next_ownership,
    transition.next_generation,
    transition.next_opaque_ownership_cid,
    transition.next_opaque_generation_cid,
    transition.next_actual_bytes,
    transition.next_physical_digest,
  )
}

///|
pub fn publication_payload_transition_expected_revision(
  transition : PublicationPayloadTransition,
) -> Int {
  transition.expected_revision
}

///|
pub fn publication_payload_transition_material_identity(
  transition : PublicationPayloadTransition,
) -> String {
  transition.record.request.material_generation_cid
}

///|
fn[T] decoded(value : Result[T, @decode.Issue]) -> T raise PayloadStop {
  match value {
    Ok(result) => result
    Err(_) => raise PayloadStop
  }
}

///|
fn text(object : @decode.ObjectView, key : String) -> String raise PayloadStop {
  decoded(@decode.text(decoded(@decode.required(object, key))))
}

///|
fn parse_i64(value : String) -> Int64 raise PayloadStop {
  @string.from_str(value) catch {
    _ => raise PayloadStop
  }
}

///|
fn parse_u64(value : String) -> UInt64 raise PayloadStop {
  @string.from_str(value) catch {
    _ => raise PayloadStop
  }
}

///|
fn admit_request_json(
  body : String,
) -> PublicationPayloadRequest raise PayloadStop {
  let bytes = @utf8.encode(body)
  let node = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: 32768,
      max_nodes: 64,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => raise PayloadStop
  }
  let cursor = decoded(
    @decode.admit(node, {
      max_nodes: 64,
      max_depth: 2,
      max_string_bytes: 32768,
      max_total_string_bytes: 32768,
    }),
  )
  let object = decoded(
    @decode.closed_object(cursor, [
      "durable_codec_cid", "logical_relation_cid", "material_generation_cid", "max_bytes",
      "ordering_evidence_cid", "publication_attempt_cid", "result_definition_cid",
      "result_schema_cid", "row_count", "store_authority_cid", "version",
    ]),
  )
  if text(object, "version") != "actql-publication-payload-request/0.1" {
    raise PayloadStop
  }
  let request = match
    prepare_publication_payload_request(
      text(object, "store_authority_cid"),
      text(object, "publication_attempt_cid"),
      text(object, "material_generation_cid"),
      text(object, "result_definition_cid"),
      text(object, "logical_relation_cid"),
      text(object, "result_schema_cid"),
      text(object, "ordering_evidence_cid"),
      text(object, "durable_codec_cid"),
      parse_i64(text(object, "max_bytes")),
      parse_i64(text(object, "row_count")),
    ) {
    Ok(value) => value
    Err(_) => raise PayloadStop
  }
  if request.body != body {
    raise PayloadStop
  }
  request
}

///|
/// Re-admit one exact canonical request. Durable callers must preserve both
/// the canonical body and its separately stored identity.
pub fn admit_publication_payload_request_json(
  body : String,
  claimed_request_cid : String,
) -> Result[PublicationPayloadRequest, PublicationPayloadIssue] {
  try {
    let request = admit_request_json(body)
    if request.request_cid != claimed_request_cid {
      raise PayloadStop
    }
    Ok(request)
  } catch {
    PayloadStop => Err(InvalidRequest)
  }
}

///|
pub fn admit_durable_publication_payload_record(
  bytes : Bytes,
) -> Result[DurablePublicationPayloadRecord, PublicationPayloadIssue] {
  try {
    let node = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: 65536,
        max_nodes: 32,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise PayloadStop
    }
    let cursor = decoded(
      @decode.admit(node, {
        max_nodes: 32,
        max_depth: 2,
        max_string_bytes: 32768,
        max_total_string_bytes: 65536,
      }),
    )
    let (object, is_opaque) = match
      @decode.closed_object(cursor, [
        "actual_bytes", "device", "inode", "physical_digest", "request_cid", "request_json",
        "ownership_device", "ownership_inode", "revision", "state", "version",
      ]) {
      Ok(value) => (value, false)
      Err(_) =>
        (
          decoded(@decode.closed_object(cursor, [
            "actual_bytes", "custody_generation_cid", "custody_ownership_cid",
            "physical_digest", "request_cid", "request_json", "revision", "state",
            "version",
          ])),
          true,
        )
    }
    if text(object, "version") !=
      (if is_opaque { "actql-publication-payload-record/0.3" } else {
        "actql-publication-payload-record/0.2"
      }) {
      raise PayloadStop
    }
    let request = admit_request_json(text(object, "request_json"))
    if text(object, "request_cid") != request.request_cid {
      raise PayloadStop
    }
    let revision64 = parse_i64(text(object, "revision"))
    if revision64 < 0L || revision64 > 2147483647L {
      raise PayloadStop
    }
    let revision = revision64.to_int()
    let state = parse_state(text(object, "state"))
    let actual_bytes = parse_i64(text(object, "actual_bytes"))
    let physical_digest = text(object, "physical_digest")
    let ownership = if is_opaque {
      None
    } else {
      let device = text(object, "ownership_device")
      let inode = text(object, "ownership_inode")
      if device == "" && inode == "" {
        None
      } else if device == "" || inode == "" {
        raise PayloadStop
      } else {
        Some({ device: parse_u64(device), inode: parse_u64(inode), })
      }
    }
    let generation = if is_opaque {
      None
    } else {
      let device = text(object, "device")
      let inode = text(object, "inode")
      if device == "" && inode == "" {
        None
      } else if device == "" || inode == "" || actual_bytes < 0L {
        raise PayloadStop
      } else {
        Some({
          device: parse_u64(device), inode: parse_u64(inode),
          size: actual_bytes,
        })
      }
    }
    let opaque_ownership_cid = if is_opaque {
      let value = text(object, "custody_ownership_cid")
      if value == "" { None } else if valid_sha256_cid(value) {
        Some(value)
      } else { raise PayloadStop }
    } else { None }
    let opaque_generation_cid = if is_opaque {
      let value = text(object, "custody_generation_cid")
      if value == "" { None } else if valid_sha256_cid(value) {
        Some(value)
      } else { raise PayloadStop }
    } else { None }
    if is_opaque && opaque_ownership_cid is None {
      raise PayloadStop
    }
    let native_sealed = ownership is Some(owner) &&
      generation is Some(_) &&
      generation.unwrap().device == owner.device &&
      generation.unwrap().inode == owner.inode
    let opaque_sealed = opaque_ownership_cid is Some(owner) &&
      opaque_generation_cid == Some(owner)
    let valid = match state {
      Intent | Reserved =>
        ownership is None &&
        generation is None &&
        opaque_ownership_cid is None &&
        opaque_generation_cid is None &&
        actual_bytes == -1L &&
        physical_digest == ""
      Writing =>
        generation is None && opaque_generation_cid is None &&
        actual_bytes == -1L && physical_digest == ""
      Sealed =>
        (native_sealed || opaque_sealed) &&
        actual_bytes >= 0L &&
        actual_bytes <= request.max_bytes &&
        valid_sha256_cid(physical_digest)
      Reclaiming | Reclaimed =>
        (generation is None && opaque_generation_cid is None &&
          actual_bytes == -1L && physical_digest == "") ||
        (
          (native_sealed || opaque_sealed) &&
          actual_bytes >= 0L &&
          actual_bytes <= request.max_bytes &&
          valid_sha256_cid(physical_digest)
        )
    }
    if !valid {
      raise PayloadStop
    }
    let body = @utf8.decode(bytes) catch { _ => raise PayloadStop }
    let canonical = match
      emit_payload_record(
        request, revision, state, ownership, generation, opaque_ownership_cid,
        opaque_generation_cid, actual_bytes, physical_digest,
      ) {
      Ok(value) => value
      Err(_) => raise PayloadStop
    }
    if canonical != body {
      raise PayloadStop
    }
    Ok({
      request,
      revision,
      state,
      ownership,
      generation,
      opaque_ownership_cid,
      opaque_generation_cid,
      actual_bytes,
      physical_digest,
      body,
    })
  } catch {
    PayloadStop => Err(InvalidRecord)
  }
}

///|
pub fn restore_durable_publication_payload_record(
  durable : DurablePublicationPayloadRecord,
) -> Result[PublicationPayloadRecord, PublicationPayloadIssue] {
  let record = prepare_publication_payload_record(durable.request)
  record.revision = durable.revision
  record.state = durable.state
  record.ownership = durable.ownership
  record.generation = durable.generation
  record.opaque_ownership_cid = durable.opaque_ownership_cid
  record.opaque_generation_cid = durable.opaque_generation_cid
  record.actual_bytes = durable.actual_bytes
  record.physical_digest = durable.physical_digest
  match publication_payload_record_durable_json(record) {
    Ok(body) if body == durable.body => Ok(record)
    _ => Err(InvalidRecord)
  }
}

///|
pub fn durable_publication_payload_record_revision(
  durable : DurablePublicationPayloadRecord,
) -> Int {
  durable.revision
}

///|
pub fn durable_publication_payload_record_state(
  durable : DurablePublicationPayloadRecord,
) -> PublicationPayloadState {
  durable.state
}

///|
pub fn durable_publication_payload_record_request(
  durable : DurablePublicationPayloadRecord,
) -> PublicationPayloadRequest {
  durable.request
}

///|
pub fn durable_publication_payload_record_request_identity(
  durable : DurablePublicationPayloadRecord,
) -> String {
  durable.request.request_cid
}

///|
pub fn durable_publication_payload_record_material_identity(
  durable : DurablePublicationPayloadRecord,
) -> String {
  durable.request.material_generation_cid
}
