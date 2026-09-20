///|
pub(all) enum NativeRemoteTransferClientIssue {
  InvalidRequest
  SourceMismatch
  Rejected(Int)
  Physical(@http.NativeHttpIssue)
  Durable(@journal.NativeRemoteTransferJournalIssue)
  Protocol(@transfer.RemoteTransferIssue)
  ReconciliationRequired
}

///|
fn admit_source(
  request : @transfer.RemoteTransferRequest,
  chunks : Array[Bytes],
  route : String,
) -> Result[Unit, NativeRemoteTransferClientIssue] {
  let projection = @transfer.request_projection(request)
  if projection[1] != route {
    return Err(InvalidRequest)
  }
  let expected_cids = @transfer.request_chunk_cids(request)
  let expected_lengths = @transfer.request_chunk_byte_lengths(request)
  if chunks.length() != expected_cids.length() ||
    chunks.length() != expected_lengths.length() {
    return Err(SourceMismatch)
  }
  for index, chunk in chunks {
    if chunk.length().to_int64() != expected_lengths[index] ||
      "sha256:" + @sha.hex(chunk) != expected_cids[index] {
      return Err(SourceMismatch)
    }
  }
  Ok(())
}

///|
pub fn admit_direct_source(
  request : @transfer.RemoteTransferRequest,
  chunks : Array[Bytes],
) -> Result[Unit, NativeRemoteTransferClientIssue] {
  admit_source(request, chunks, "direct")
}

///|
pub fn admit_store_source(
  request : @transfer.RemoteTransferRequest,
  chunks : Array[Bytes],
) -> Result[Unit, NativeRemoteTransferClientIssue] {
  admit_source(request, chunks, "store")
}

///|
fn transfer_unreserved(byte : Byte) -> Bool {
  let value = byte.to_int()
  (value >= 65 && value <= 90) ||
  (value >= 97 && value <= 122) ||
  (value >= 48 && value <= 57) ||
  value == 45 ||
  value == 46 ||
  value == 95 ||
  value == 126
}

///|
fn transfer_path_component(value : String) -> String? {
  if value.is_empty() {
    return None
  }
  let source = @utf8.encode(value)
  let digits = b"0123456789ABCDEF"
  let output : Array[Byte] = []
  for byte in source {
    if transfer_unreserved(byte) {
      output.push(byte)
    } else {
      output.push((37 : Byte))
      output.push(digits[byte.to_int() >> 4])
      output.push(digits[byte.to_int() & 15])
    }
  }
  Some(@utf8.decode(Bytes::from_array(output)) catch { _ => return None })
}

///|
fn transfer_response(
  response : @http.NativeHttpResponse,
  request : @transfer.RemoteTransferRequest,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferClientIssue] {
  if response.status != 200 && response.status != 201 {
    return Err(Rejected(response.status))
  }
  let body = @utf8.decode(response.body) catch {
    _ => return Err(Protocol(@transfer.InvalidTransfer))
  }
  match @transfer.admit_remote_transfer_reply_json(body, request) {
    Ok(record) => Ok(record)
    Err(issue) => Err(Protocol(issue))
  }
}

///|
fn transfer_exchange(
  client : @http.Client,
  verb : @http.NativeHttpMethod,
  url : String,
  headers : Array[@http.NativeHttpHeader],
  body : Bytes,
  request : @transfer.RemoteTransferRequest,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferClientIssue] {
  let response = match client.request(verb, url, headers, body) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  transfer_response(response, request)
}

///|
fn direct_cancel(
  client : @http.Client,
  url : String,
  request : @transfer.RemoteTransferRequest,
) -> Unit {
  ignore(
    transfer_exchange(
      client,
      @http.Post,
      url + "/cancel",
      [{ name: "content-length", value: "0", }],
      b"",
      request,
    ),
  )
}

///|
fn direct_location(
  origin : String,
  request : @transfer.RemoteTransferRequest,
) -> Result[(String, String), NativeRemoteTransferClientIssue] {
  if !origin.has_prefix("https://") || origin.has_suffix("/") {
    return Err(InvalidRequest)
  }
  let projection = @transfer.request_projection(request)
  if projection[1] != "direct" {
    return Err(InvalidRequest)
  }
  guard transfer_path_component(projection[4]) is Some(destination_site) else {
    return Err(InvalidRequest)
  }
  guard transfer_path_component(@transfer.request_cid(request))
    is Some(request_identity) else {
    return Err(InvalidRequest)
  }
  let base = origin +
    "/v1/sites/" +
    destination_site +
    "/generations/" +
    projection[5] +
    "/transfers"
  Ok((base, base + "/" + request_identity))
}

///|
fn store_upload_location(
  origin : String,
  request : @transfer.RemoteTransferRequest,
) -> Result[(String, String), NativeRemoteTransferClientIssue] {
  if !origin.has_prefix("https://") ||
    origin.has_suffix("/") ||
    @transfer.request_projection(request)[1] != "store" {
    return Err(InvalidRequest)
  }
  guard transfer_path_component(@transfer.request_cid(request))
    is Some(request_identity) else {
    return Err(InvalidRequest)
  }
  let base = origin + "/v1/transfer-store/uploads"
  Ok((base, base + "/" + request_identity))
}

///|
fn store_upload_response(
  response : @http.NativeHttpResponse,
  request : @transfer.RemoteTransferRequest,
  kind : @transfer.RemoteTransferStoreUploadReplyKind,
) -> Result[Array[String], NativeRemoteTransferClientIssue] {
  if response.status != 200 && response.status != 201 {
    return Err(Rejected(response.status))
  }
  let body = @utf8.decode(response.body) catch {
    _ => return Err(Protocol(@transfer.InvalidTransfer))
  }
  match
    @transfer.admit_remote_transfer_store_upload_reply_json(body, request, kind) {
    Ok(reply) =>
      Ok(@transfer.remote_transfer_store_upload_reply_projection(reply))
    Err(issue) => Err(Protocol(issue))
  }
}

///|
fn store_upload_exchange(
  client : @http.Client,
  verb : @http.NativeHttpMethod,
  url : String,
  headers : Array[@http.NativeHttpHeader],
  body : Bytes,
  request : @transfer.RemoteTransferRequest,
  kind : @transfer.RemoteTransferStoreUploadReplyKind,
) -> Result[Array[String], NativeRemoteTransferClientIssue] {
  let response = match client.request(verb, url, headers, body) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  store_upload_response(response, request, kind)
}

///|
fn admit_store_upload(
  client : @http.Client,
  base : String,
  request : @transfer.RemoteTransferRequest,
) -> Result[Array[String], NativeRemoteTransferClientIssue] {
  let projection = @transfer.request_projection(request)
  let envelope = match @transfer.transfer_admission_envelope_json(request) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  store_upload_exchange(
    client,
    @http.Post,
    base,
    [
      { name: "content-type", value: "application/json", },
      { name: "content-length", value: envelope.length().to_string(), },
      { name: "actql-transfer-cid", value: @transfer.request_cid(request), },
      { name: "actql-manifest-cid", value: projection[7], },
    ],
    envelope,
    request,
    @transfer.StoreUploadAdmissionReply,
  )
}

///|
fn upload_store_transfer(
  client : @http.Client,
  origin : String,
  request : @transfer.RemoteTransferRequest,
  chunks : Array[Bytes],
) -> Result[Unit, NativeRemoteTransferClientIssue] {
  match admit_store_source(request, chunks) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let (base, upload_url) = match store_upload_location(origin, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let admitted = match admit_store_upload(client, base, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if admitted[2] == "1" {
    return Ok(())
  }
  let next_chunk : Int = @string.from_str(admitted[1]) catch {
    _ => return Err(Protocol(@transfer.InvalidTransfer))
  }
  for index = next_chunk; index < chunks.length(); index = index + 1 {
    let chunk = chunks[index]
    let uploaded = match
      store_upload_exchange(
        client,
        @http.Put,
        upload_url + "/chunks/" + index.to_string(),
        [
          { name: "content-type", value: "application/octet-stream", },
          { name: "content-length", value: chunk.length().to_string(), },
        ],
        chunk,
        request,
        @transfer.StoreUploadChunkReply,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if uploaded[1] != (index + 1).to_string() || uploaded[2] != "0" {
      return Err(Protocol(@transfer.InvalidTransfer))
    }
  }
  let committed = match
    store_upload_exchange(
      client,
      @http.Post,
      upload_url + "/commit",
      [{ name: "content-length", value: "0", }],
      b"",
      request,
      @transfer.StoreUploadCommitReply,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if committed[2] == "1" {
    Ok(())
  } else {
    Err(Protocol(@transfer.InvalidTransfer))
  }
}

///|
fn admit_direct_destination(
  client : @http.Client,
  base : String,
  request : @transfer.RemoteTransferRequest,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferClientIssue] {
  let projection = @transfer.request_projection(request)
  let envelope = match @transfer.transfer_admission_envelope_json(request) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  transfer_exchange(
    client,
    @http.Post,
    base,
    [
      { name: "content-type", value: "application/json", },
      { name: "content-length", value: envelope.length().to_string(), },
      { name: "actql-transfer-cid", value: @transfer.request_cid(request), },
      { name: "actql-manifest-cid", value: projection[7], },
    ],
    envelope,
    request,
  )
}

///|
fn commit_direct_destination(
  client : @http.Client,
  transfer_url : String,
  request : @transfer.RemoteTransferRequest,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferClientIssue] {
  transfer_exchange(
    client,
    @http.Post,
    transfer_url + "/commit",
    [{ name: "content-length", value: "0", }],
    b"",
    request,
  )
}

///|
pub fn send_direct_transfer(
  client : @http.Client,
  origin : String,
  request : @transfer.RemoteTransferRequest,
  chunks : Array[Bytes],
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferClientIssue] {
  match admit_direct_source(request, chunks) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let (base, transfer_url) = match direct_location(origin, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let admitted = match admit_direct_destination(client, base, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if @transfer.record_is_destination_committed(admitted) {
    return Ok(admitted)
  }
  for index, chunk in chunks {
    let uploaded = transfer_exchange(
      client,
      @http.Put,
      transfer_url + "/chunks/" + index.to_string(),
      [
        { name: "content-type", value: "application/octet-stream", },
        { name: "content-length", value: chunk.length().to_string(), },
      ],
      chunk,
      request,
    )
    if uploaded is Err(issue) {
      direct_cancel(client, transfer_url, request)
      return Err(issue)
    }
  }
  let committed = commit_direct_destination(client, transfer_url, request)
  match committed {
    Err(issue) => {
      direct_cancel(client, transfer_url, request)
      Err(issue)
    }
    Ok(record) =>
      if @transfer.record_is_destination_committed(record) {
        Ok(record)
      } else {
        Err(Protocol(@transfer.InvalidTransfer))
      }
  }
}

///|
fn commit_durable_transition(
  journal : @journal.Journal,
  transition : @transfer.RemoteTransferTransition,
) -> Result[Unit, NativeRemoteTransferClientIssue] {
  match journal.commit_transition(transition) {
    Ok(_) => Ok(())
    Err(issue) => Err(Durable(issue))
  }
}

///|
fn require_durable_record(
  journal : @journal.Journal,
  request : @transfer.RemoteTransferRequest,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferClientIssue] {
  match journal.require(request) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Durable(issue))
  }
}

///|
pub fn send_durable_direct_transfer(
  journal : @journal.Journal,
  client : @http.Client,
  origin : String,
  request : @transfer.RemoteTransferRequest,
  chunks : Array[Bytes],
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferClientIssue] {
  let (_, accepted) = match journal.accept(request) {
    Ok(value) => value
    Err(issue) => return Err(Durable(issue))
  }
  let mut record = accepted
  let mut progress = @transfer.direct_transfer_progress(record)
  if progress == @transfer.DirectTransferCommitted {
    return Ok(record)
  }
  if progress == @transfer.DirectTransferReconciliationRequired {
    return Err(ReconciliationRequired)
  }
  if progress == @transfer.DirectTransferStart {
    let transition = match @transfer.prepare_start(record) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    match commit_durable_transition(journal, transition) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    record = match require_durable_record(journal, request) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    progress = @transfer.direct_transfer_progress(record)
  }
  let remote = if progress == @transfer.DirectTransferSourceSettled {
    let (base, transfer_url) = match direct_location(origin, request) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let admitted = match admit_direct_destination(client, base, request) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if @transfer.record_is_destination_committed(admitted) {
      Ok(admitted)
    } else {
      commit_direct_destination(client, transfer_url, request)
    }
  } else if progress == @transfer.DirectTransferCopying {
    send_direct_transfer(client, origin, request, chunks)
  } else {
    return Err(ReconciliationRequired)
  }
  match remote {
    Err(issue) => return Err(issue)
    Ok(value) =>
      if !@transfer.record_is_destination_committed(value) {
        return Err(Protocol(@transfer.InvalidTransfer))
      }
  }
  if progress == @transfer.DirectTransferCopying {
    let settled = match @transfer.prepare_source_settled(record, true, false) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    match commit_durable_transition(journal, settled) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    record = match require_durable_record(journal, request) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  let committed = match @transfer.prepare_destination_commit(record) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match commit_durable_transition(journal, committed) {
    Ok(_) => require_durable_record(journal, request)
    Err(issue) => Err(issue)
  }
}

///|
pub fn send_durable_store_upload(
  journal : @journal.Journal,
  client : @http.Client,
  origin : String,
  request : @transfer.RemoteTransferRequest,
  chunks : Array[Bytes],
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferClientIssue] {
  let (_, accepted) = match journal.accept(request) {
    Ok(value) => value
    Err(issue) => return Err(Durable(issue))
  }
  let mut record = accepted
  let mut progress = @transfer.store_upload_progress(record)
  if progress == @transfer.StoreUploadCommitted ||
    progress == @transfer.StoreUploadSealed {
    return Ok(record)
  }
  if progress == @transfer.StoreUploadReconciliationRequired {
    return Err(ReconciliationRequired)
  }
  if progress == @transfer.StoreUploadStart {
    let transition = match @transfer.prepare_start(record) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    match commit_durable_transition(journal, transition) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    record = match require_durable_record(journal, request) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    progress = @transfer.store_upload_progress(record)
  }
  if progress != @transfer.StoreUploadCopying {
    return Err(ReconciliationRequired)
  }
  match upload_store_transfer(client, origin, request, chunks) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let settled = match @transfer.prepare_source_settled(record, true, true) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match commit_durable_transition(journal, settled) {
    Ok(_) => require_durable_record(journal, request)
    Err(issue) => Err(issue)
  }
}
