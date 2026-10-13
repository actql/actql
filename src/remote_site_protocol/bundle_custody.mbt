///|
/// The authenticated Site channel carries Run work and pre-Run Set custody
/// separately. A Bundle request never manufactures a dispatch or a Run.
pub(all) enum RemoteSitePollOperation {
  Run(RemotePollOperation)
  BundleCustody(RemotePollBundleCustody)
}

///|
struct RemotePollBundleCustody {
  request : @bundle.RemoteBundleCustodyRequest
  delivery_revision : Int64
}

///|
pub fn remote_poll_bundle_custody_request(
  value : RemotePollBundleCustody,
) -> @bundle.RemoteBundleCustodyRequest {
  value.request
}

///|
pub fn remote_poll_bundle_custody_delivery_revision(
  value : RemotePollBundleCustody,
) -> Int64 {
  value.delivery_revision
}

///|
fn bundle_delivery_revision_valid(value : Int64) -> Bool {
  value > 0L && value <= 9007199254740991L
}

///|
pub fn remote_poll_bundle_custody_json(
  request : @bundle.RemoteBundleCustodyRequest,
  delivery_revision : Int64,
) -> Result[String, DispatchIssue] {
  if !bundle_delivery_revision_valid(delivery_revision) {
    return Err(InvalidDispatch)
  }
  let body = match @bundle.bundle_custody_request_json(request) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let writer = @encode.writer(131072, 16, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "delivery_revision")
    @encode.number_value(writer, delivery_revision.to_double())
    @encode.key(writer, "request_cid")
    @encode.string_value(
      writer,
      @bundle.bundle_custody_request_identity(request),
    )
    @encode.key(writer, "request_json")
    @encode.string_value(writer, body)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-poll-bundle-custody/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_poll_bundle_custody_json(
  body : String,
) -> Result[RemotePollBundleCustody, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 131072, 16, 2), [
      "delivery_revision", "request_cid", "request_json", "version",
    ])
    if evidence_text(object, "version") !=
      "actql-remote-poll-bundle-custody/0.1" {
      raise EvidenceJsonStop
    }
    let delivery_revision = evidence_decoded(
      @decode.safe_integer(
        evidence_decoded(@decode.required(object, "delivery_revision")),
      ),
    )
    let request = match
      @bundle.admit_bundle_custody_request_json(
        evidence_text(object, "request_json"),
        evidence_text(object, "request_cid"),
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if remote_poll_bundle_custody_json(request, delivery_revision) != Ok(body) {
      raise EvidenceJsonStop
    }
    Ok({ request, delivery_revision, })
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_site_poll_operation_json(
  body : String,
) -> Result[RemoteSitePollOperation, DispatchIssue] {
  match admit_remote_poll_bundle_custody_json(body) {
    Ok(request) => Ok(BundleCustody(request))
    Err(_) =>
      match admit_remote_poll_operation_json(body) {
        Ok(operation) => Ok(Run(operation))
        Err(issue) => Err(issue)
      }
  }
}

///|
/// The original Set/member request supplies all scope. Neither the wrapper
/// nor a caller-selected route grants permission or acknowledges Store custody.
pub fn remote_bundle_custody_observation_json(
  request : @bundle.RemoteBundleCustodyRequest,
  response : @bundle.RemoteBundleCustodyResponse,
  delivery_revision : Int64,
) -> Result[String, DispatchIssue] {
  if !bundle_delivery_revision_valid(delivery_revision) {
    return Err(InvalidDispatch)
  }
  let body = match @bundle.bundle_custody_response_json(response) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let response_cid = @bundle.bundle_custody_response_identity(response)
  if @bundle.admit_bundle_custody_response_json(request, body, response_cid)
    is Err(_) {
    return Err(DispatchIdentityMismatch)
  }
  let writer = @encode.writer(131072, 16, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "delivery_revision")
    @encode.number_value(writer, delivery_revision.to_double())
    @encode.key(writer, "request_cid")
    @encode.string_value(
      writer,
      @bundle.bundle_custody_request_identity(request),
    )
    @encode.key(writer, "response_cid")
    @encode.string_value(writer, response_cid)
    @encode.key(writer, "response_json")
    @encode.string_value(writer, body)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-bundle-custody-observation/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_bundle_custody_observation_json(
  body : String,
  request : @bundle.RemoteBundleCustodyRequest,
  delivery_revision : Int64,
) -> Result[@bundle.RemoteBundleCustodyResponse, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 131072, 16, 2), [
      "delivery_revision", "request_cid", "response_cid", "response_json", "version",
    ])
    if evidence_decoded(
        @decode.safe_integer(
          evidence_decoded(@decode.required(object, "delivery_revision")),
        ),
      ) !=
      delivery_revision ||
      evidence_text(object, "version") !=
      "actql-remote-bundle-custody-observation/0.1" ||
      evidence_text(object, "request_cid") !=
      @bundle.bundle_custody_request_identity(request) {
      raise EvidenceJsonStop
    }
    let response = match
      @bundle.admit_bundle_custody_response_json(
        request,
        evidence_text(object, "response_json"),
        evidence_text(object, "response_cid"),
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if remote_bundle_custody_observation_json(
        request, response, delivery_revision,
      ) !=
      Ok(body) {
      raise EvidenceJsonStop
    }
    Ok(response)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
/// A checked transport ACK names the exact admitted response. It is not
/// independent evidence of Bundle retention or permission to start a Run.
pub fn remote_bundle_custody_observation_ack_json(
  request : @bundle.RemoteBundleCustodyRequest,
  response : @bundle.RemoteBundleCustodyResponse,
  delivery_revision : Int64,
) -> Result[String, DispatchIssue] {
  if remote_bundle_custody_observation_json(
      request, response, delivery_revision,
    )
    is Err(_) {
    return Err(DispatchIdentityMismatch)
  }
  let writer = @encode.writer(4096, 8, 1) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "delivery_revision")
    @encode.number_value(writer, delivery_revision.to_double())
    @encode.key(writer, "request_cid")
    @encode.string_value(
      writer,
      @bundle.bundle_custody_request_identity(request),
    )
    @encode.key(writer, "response_cid")
    @encode.string_value(
      writer,
      @bundle.bundle_custody_response_identity(response),
    )
    @encode.key(writer, "version")
    @encode.string_value(
      writer, "actql-remote-bundle-custody-observation-ack/0.1",
    )
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_bundle_custody_observation_ack_json(
  body : String,
  request : @bundle.RemoteBundleCustodyRequest,
  response : @bundle.RemoteBundleCustodyResponse,
  delivery_revision : Int64,
) -> Result[Unit, DispatchIssue] {
  // The exact canonical comparison also rejects extra fields, duplicate keys,
  // wrong identities, another response and an unbound bare HTTP success.
  match
    remote_bundle_custody_observation_ack_json(
      request, response, delivery_revision,
    ) {
    Ok(expected) if body == expected => Ok(())
    _ => Err(InvalidDispatch)
  }
}

///|
/// Accepted acknowledges the exact persisted response. Obsolete retires only
/// its transport duty after the current Set Owner proves supersession; it is
/// not evidence of retention, release, or permission to run.
pub(all) enum RemoteBundleCustodyObservationReply {
  Accepted
  Obsolete
}

///|
pub fn remote_bundle_custody_observation_obsolete_json(
  request : @bundle.RemoteBundleCustodyRequest,
  response : @bundle.RemoteBundleCustodyResponse,
  delivery_revision : Int64,
) -> Result[String, DispatchIssue] {
  if remote_bundle_custody_observation_json(
      request, response, delivery_revision,
    )
    is Err(_) {
    return Err(DispatchIdentityMismatch)
  }
  let writer = @encode.writer(4096, 8, 1) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "delivery_revision")
    @encode.number_value(writer, delivery_revision.to_double())
    @encode.key(writer, "disposition")
    @encode.string_value(writer, "obsolete")
    @encode.key(writer, "request_cid")
    @encode.string_value(
      writer,
      @bundle.bundle_custody_request_identity(request),
    )
    @encode.key(writer, "response_cid")
    @encode.string_value(
      writer,
      @bundle.bundle_custody_response_identity(response),
    )
    @encode.key(writer, "version")
    @encode.string_value(
      writer, "actql-remote-bundle-custody-observation-disposition/0.1",
    )
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_bundle_custody_observation_reply_json(
  body : String,
  request : @bundle.RemoteBundleCustodyRequest,
  response : @bundle.RemoteBundleCustodyResponse,
  delivery_revision : Int64,
) -> Result[RemoteBundleCustodyObservationReply, DispatchIssue] {
  if admit_remote_bundle_custody_observation_ack_json(
      body, request, response, delivery_revision,
    )
    is Ok(_) {
    return Ok(Accepted)
  }
  match
    remote_bundle_custody_observation_obsolete_json(
      request, response, delivery_revision,
    ) {
    Ok(expected) if body == expected => Ok(Obsolete)
    _ => Err(InvalidDispatch)
  }
}
