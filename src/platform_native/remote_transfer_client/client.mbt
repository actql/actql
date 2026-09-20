///|
pub(all) enum NativeRemoteTransferClientIssue {
  InvalidRequest
  SourceMismatch
  Rejected(Int)
  Physical(@http.NativeHttpIssue)
  Durable(@journal.NativeRemoteTransferJournalIssue)
  Destination(@filesystem.NativeFilesystemIssue)
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
fn store_use_response(
  response : @http.NativeHttpResponse,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
  kind : @transfer.RemoteTransferStoreUseReplyKind,
) -> Result[Array[String], NativeRemoteTransferClientIssue] {
  if response.status != 200 && response.status != 201 {
    return Err(Rejected(response.status))
  }
  let body = @utf8.decode(response.body) catch {
    _ => return Err(Protocol(@transfer.InvalidTransfer))
  }
  match
    @transfer.admit_remote_transfer_store_use_reply_json(
      body, request, use_id, kind,
    ) {
    Ok(reply) => Ok(@transfer.remote_transfer_store_use_reply_projection(reply))
    Err(issue) => Err(Protocol(issue))
  }
}

///|
fn store_use_exchange(
  client : @http.Client,
  verb : @http.NativeHttpMethod,
  url : String,
  headers : Array[@http.NativeHttpHeader],
  body : Bytes,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
  kind : @transfer.RemoteTransferStoreUseReplyKind,
) -> Result[Array[String], NativeRemoteTransferClientIssue] {
  let response = match client.request(verb, url, headers, body) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  store_use_response(response, request, use_id, kind)
}

///|
fn cancel_store_use(
  client : @http.Client,
  origin : String,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
) -> Result[Unit, NativeRemoteTransferClientIssue] {
  let request_component = match
    transfer_path_component(@transfer.request_cid(request)) {
    Some(value) => value
    None => return Err(InvalidRequest)
  }
  let use_component = match transfer_path_component(use_id) {
    Some(value) => value
    None => return Err(InvalidRequest)
  }
  let response = match
    client.request(
      @http.Post,
      origin +
      "/v1/transfer-store/downloads/" +
      request_component +
      "/" +
      use_component +
      "/cancel",
      [{ name: "content-length", value: "0", }],
      b"",
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  if response.status != 200 {
    return Err(Rejected(response.status))
  }
  let body = @utf8.decode(response.body) catch {
    _ => return Err(Protocol(@transfer.InvalidTransfer))
  }
  match
    @transfer.admit_remote_transfer_store_use_cancellation_reply_json(
      body, request, use_id,
    ) {
    Ok(_) => Ok(())
    Err(issue) => Err(Protocol(issue))
  }
}

///|
fn admit_store_use(
  client : @http.Client,
  base : String,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
) -> Result[Array[String], NativeRemoteTransferClientIssue] {
  let projection = @transfer.request_projection(request)
  let envelope = match @transfer.transfer_admission_envelope_json(request) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  store_use_exchange(
    client,
    @http.Post,
    base + "/downloads",
    [
      { name: "content-type", value: "application/json", },
      { name: "content-length", value: envelope.length().to_string(), },
      { name: "actql-transfer-cid", value: @transfer.request_cid(request), },
      { name: "actql-manifest-cid", value: projection[7], },
      { name: "actql-transfer-use-id", value: use_id, },
    ],
    envelope,
    request,
    use_id,
    @transfer.StoreUseAdmissionReply,
  )
}

///|
fn destination_object_name(
  request : @transfer.RemoteTransferRequest,
  index : Int,
) -> Result[String, NativeRemoteTransferClientIssue] {
  match @sha.text_hex(@transfer.request_cid(request)) {
    Ok(value) => Ok("transfer-" + value + "-" + index.to_string())
    Err(_) => Err(Protocol(@transfer.InvalidTransfer))
  }
}

///|
fn destination_staging_name(
  request : @transfer.RemoteTransferRequest,
  use_id : String,
  index : Int,
) -> Result[String, NativeRemoteTransferClientIssue] {
  match @sha.text_hex(@transfer.request_cid(request) + "\n" + use_id) {
    Ok(value) => Ok("transfer-stage-" + value + "-" + index.to_string())
    Err(_) => Err(Protocol(@transfer.InvalidTransfer))
  }
}

///|
fn verify_destination_object(
  root : @filesystem.Root,
  name : String,
  generation : @filesystem.NativeFileGeneration,
  expected_cid : String,
  expected_bytes : Int64,
) -> Result[Bool, NativeRemoteTransferClientIssue] {
  if generation.size != expected_bytes {
    return Ok(false)
  }
  let reader = match root.open_reader(name, generation) {
    Ok(value) => value
    Err(issue) => return Err(Destination(issue))
  }
  let hash = @sha.hasher()
  let mut length = 0L
  while true {
    let chunk = match reader.next(1048576) {
      Ok(value) => value
      Err(issue) => {
        ignore(reader.close())
        return Err(Destination(issue))
      }
    }
    length = length + chunk.bytes.length().to_int64()
    @sha.update(hash, chunk.bytes) catch {
      _ => {
        ignore(reader.close())
        return Err(Protocol(@transfer.InvalidTransfer))
      }
    }
    if chunk.eof {
      break
    }
  }
  match reader.finish() {
    Ok(_) => ()
    Err(issue) => {
      ignore(reader.close())
      return Err(Destination(issue))
    }
  }
  match reader.close() {
    Ok(_) => ()
    Err(issue) => return Err(Destination(issue))
  }
  let digest = @sha.finish_hex(hash) catch {
    _ => return Err(Protocol(@transfer.InvalidTransfer))
  }
  Ok(length == expected_bytes && "sha256:" + digest == expected_cid)
}

///|
fn prepare_destination_chunk(
  root : @filesystem.Root,
  client : @http.Client,
  base : String,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
  index : Int,
  expected_cid : String,
  expected_bytes : Int64,
) -> Result[@filesystem.NativeFileGeneration, NativeRemoteTransferClientIssue] {
  let final_name = match destination_object_name(request, index) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let existing = match root.inspect_generation(final_name) {
    Ok(value) => value
    Err(issue) => return Err(Destination(issue))
  }
  match existing {
    Some(generation) =>
      match
        verify_destination_object(
          root, final_name, generation, expected_cid, expected_bytes,
        ) {
        Ok(true) => return Ok(generation)
        Ok(false) =>
          match root.reclaim_generation(final_name, generation) {
            Ok(_) => ()
            Err(issue) => return Err(Destination(issue))
          }
        Err(issue) => return Err(issue)
      }
    None => ()
  }
  let staging_name = match destination_staging_name(request, use_id, index) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match root.inspect_generation(staging_name) {
    Ok(Some(generation)) =>
      match root.reclaim_generation(staging_name, generation) {
        Ok(_) => ()
        Err(issue) => return Err(Destination(issue))
      }
    Ok(None) => ()
    Err(issue) => return Err(Destination(issue))
  }
  let request_cid = match
    transfer_path_component(@transfer.request_cid(request)) {
    Some(value) => value
    None => return Err(InvalidRequest)
  }
  let encoded_use = match transfer_path_component(use_id) {
    Some(value) => value
    None => return Err(InvalidRequest)
  }
  let response = match
    client.request(
      @http.Get,
      base +
      "/downloads/" +
      request_cid +
      "/" +
      encoded_use +
      "/chunks/" +
      index.to_string(),
      [],
      b"",
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  if response.status != 200 ||
    response.body.length().to_int64() != expected_bytes ||
    "sha256:" + @sha.hex(response.body) != expected_cid {
    return Err(SourceMismatch)
  }
  let writer = match root.create_writer(staging_name, expected_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Destination(issue))
  }
  match writer.append(response.body) {
    Ok(_) => ()
    Err(issue) => {
      ignore(writer.cancel())
      return Err(Destination(issue))
    }
  }
  match writer.seal(final_name) {
    Ok(value) => Ok(value)
    Err(issue) => {
      ignore(writer.cancel())
      Err(Destination(issue))
    }
  }
}

///|
fn destination_material_generation(
  request : @transfer.RemoteTransferRequest,
  generations : Array[@filesystem.NativeFileGeneration],
) -> Result[String, NativeRemoteTransferClientIssue] {
  let hash = @sha.hasher()
  @sha.update(hash, @utf8.encode(@transfer.request_cid(request))) catch {
    _ => return Err(Protocol(@transfer.InvalidTransfer))
  }
  for index, generation in generations {
    let name = match destination_object_name(request, index) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let fact = "\n" +
      name +
      "\n" +
      generation.device.to_string() +
      "\n" +
      generation.inode.to_string() +
      "\n" +
      generation.size.to_string()
    @sha.update(hash, @utf8.encode(fact)) catch {
      _ => return Err(Protocol(@transfer.InvalidTransfer))
    }
  }
  let digest = @sha.finish_hex(hash) catch {
    _ => return Err(Protocol(@transfer.InvalidTransfer))
  }
  Ok("sha256:" + digest)
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

///|
pub fn receive_durable_store_transfer(
  journal : @journal.Journal,
  client : @http.Client,
  destination_root : @filesystem.Root,
  origin : String,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
  max_destination_bytes : Int64,
  max_destination_objects : Int64,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferClientIssue] {
  if !origin.has_prefix("https://") ||
    origin.has_suffix("/") ||
    use_id.is_empty() ||
    use_id.length() > 256 ||
    @transfer.request_projection(request)[1] != "store" {
    return Err(InvalidRequest)
  }
  let (_, accepted) = match journal.accept(request) {
    Ok(value) => value
    Err(issue) => return Err(Durable(issue))
  }
  match
    journal.reserve_destination_holding(
      request, max_destination_bytes, max_destination_objects,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Durable(issue))
  }
  let mut record = accepted
  let mut progress = @transfer.store_upload_progress(record)
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
  let chunk_cids = @transfer.request_chunk_cids(request)
  let chunk_lengths = @transfer.request_chunk_byte_lengths(request)
  if chunk_cids.length() != chunk_lengths.length() {
    return Err(Protocol(@transfer.InvalidTransfer))
  }
  let generations : Array[@filesystem.NativeFileGeneration] = []
  if progress != @transfer.StoreUploadCommitted {
    let admitted = match
      admit_store_use(client, origin + "/v1/transfer-store", request, use_id) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if admitted[0] != @transfer.request_cid(request) || admitted[1] != use_id {
      return Err(Protocol(@transfer.InvalidTransfer))
    }
    if progress == @transfer.StoreUploadCopying {
      let settled = match @transfer.prepare_source_settled(record, true, true) {
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
      progress = @transfer.store_upload_progress(record)
    }
    if progress != @transfer.StoreUploadSealed {
      return Err(ReconciliationRequired)
    }
  }
  for index, expected_cid in chunk_cids {
    let generation = match
      prepare_destination_chunk(
        destination_root,
        client,
        origin + "/v1/transfer-store",
        request,
        use_id,
        index,
        expected_cid,
        chunk_lengths[index],
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    generations.push(generation)
  }
  match destination_root.sync_directory() {
    Ok(_) => ()
    Err(issue) => return Err(Destination(issue))
  }
  let material_generation = match
    destination_material_generation(request, generations) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if progress == @transfer.StoreUploadCommitted {
    let receipt = match journal.inspect_destination_receipt(request) {
      Ok(Some(value)) => value
      Ok(None) => return Err(ReconciliationRequired)
      Err(issue) => return Err(Durable(issue))
    }
    if @transfer.destination_receipt_projection(receipt)[4] !=
      material_generation {
      return Err(ReconciliationRequired)
    }
    return Ok(record)
  }
  let receipt = match
    @transfer.prepare_destination_receipt(request, material_generation) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let receipt = match journal.commit_destination_receipt(receipt, request) {
    Ok(value) => value
    Err(issue) => return Err(Durable(issue))
  }
  let receipt_body = match @transfer.destination_receipt_json(receipt) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  let request_component = match
    transfer_path_component(@transfer.request_cid(request)) {
    Some(value) => value
    None => return Err(InvalidRequest)
  }
  let use_component = match transfer_path_component(use_id) {
    Some(value) => value
    None => return Err(InvalidRequest)
  }
  let completed = match
    store_use_exchange(
      client,
      @http.Post,
      origin +
      "/v1/transfer-store/downloads/" +
      request_component +
      "/" +
      use_component +
      "/complete",
      [
        { name: "content-type", value: "application/json", },
        { name: "content-length", value: receipt_body.length().to_string(), },
        {
          name: "actql-destination-receipt-cid",
          value: @transfer.destination_receipt_cid(receipt),
        },
      ],
      receipt_body,
      request,
      use_id,
      @transfer.StoreUseCompletionReply,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if completed[2] != "1" {
    return Err(Protocol(@transfer.InvalidTransfer))
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
pub fn cancel_durable_store_transfer(
  journal : @journal.Journal,
  client : @http.Client,
  destination_root : @filesystem.Root,
  origin : String,
  request : @transfer.RemoteTransferRequest,
  use_id : String,
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferClientIssue] {
  if !origin.has_prefix("https://") ||
    origin.has_suffix("/") ||
    use_id.is_empty() ||
    use_id.length() > 256 ||
    @transfer.request_projection(request)[1] != "store" {
    return Err(InvalidRequest)
  }
  let mut record = match journal.require(request) {
    Ok(value) => value
    Err(issue) => return Err(Durable(issue))
  }
  let initial = @transfer.record_projection(record)
  if initial[1] == 2 {
    return Err(InvalidRequest)
  }
  if initial[1] == 1 {
    match cancel_store_use(client, origin, request, use_id) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let chunk_count = @transfer.request_chunk_cids(request).length()
  for index = 0; index < chunk_count; index = index + 1 {
    let final_name = match destination_object_name(request, index) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let staging_name = match destination_staging_name(request, use_id, index) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    for name in [final_name, staging_name] {
      match destination_root.inspect_generation(name) {
        Ok(Some(generation)) =>
          match destination_root.reclaim_generation(name, generation) {
            Ok(_) => ()
            Err(issue) => return Err(Destination(issue))
          }
        Ok(None) => ()
        Err(issue) => return Err(Destination(issue))
      }
    }
  }
  match destination_root.sync_directory() {
    Ok(_) => ()
    Err(issue) => return Err(Destination(issue))
  }
  let state = @transfer.record_projection(record)
  if state[1] != 3 && state[1] != 4 {
    let failure = match @transfer.prepare_failure(record, true, true) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    match commit_durable_transition(journal, failure) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    record = match require_durable_record(journal, request) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  if @transfer.record_projection(record)[4] != 1 {
    let cleanup = match @transfer.prepare_cleanup(record, true, true, true) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    match commit_durable_transition(journal, cleanup) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    record = match require_durable_record(journal, request) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  match journal.release_destination_holding(request) {
    Ok(_) => Ok(record)
    Err(issue) => Err(Durable(issue))
  }
}
