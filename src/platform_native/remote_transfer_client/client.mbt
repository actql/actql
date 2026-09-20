///|
pub(all) enum NativeRemoteTransferClientIssue {
  InvalidRequest
  SourceMismatch
  Rejected(Int)
  Physical(@http.NativeHttpIssue)
  Protocol(@transfer.RemoteTransferIssue)
}

///|
pub fn admit_direct_source(
  request : @transfer.RemoteTransferRequest,
  chunks : Array[Bytes],
) -> Result[Unit, NativeRemoteTransferClientIssue] {
  let projection = @transfer.request_projection(request)
  if projection[1] != "direct" {
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
pub fn send_direct_transfer(
  client : @http.Client,
  origin : String,
  request : @transfer.RemoteTransferRequest,
  chunks : Array[Bytes],
) -> Result[@transfer.RemoteTransferRecord, NativeRemoteTransferClientIssue] {
  if !origin.has_prefix("https://") || origin.has_suffix("/") {
    return Err(InvalidRequest)
  }
  let projection = @transfer.request_projection(request)
  match admit_direct_source(request, chunks) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
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
  let envelope = match @transfer.transfer_admission_envelope_json(request) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  let admitted = transfer_exchange(
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
  if admitted is Err(issue) {
    return Err(issue)
  }
  let transfer_url = base + "/" + request_identity
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
  let committed = transfer_exchange(
    client,
    @http.Post,
    transfer_url + "/commit",
    [{ name: "content-length", value: "0", }],
    b"",
    request,
  )
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
