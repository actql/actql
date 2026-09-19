///|
/// Durable evidence that the exact destination Site adopted a new physical
/// material generation for one admitted Transfer. The receipt authenticates a
/// registered Site assertion; it is not a logical Result identity.
struct RemoteTransferDestinationReceipt {
  request_cid : String
  destination_site_key : String
  destination_site_generation : Int
  destination_material_generation : String
  physical_manifest_cid : String
  destination_grant_cid : String
  receipt_cid : String
}

///|
fn destination_receipt_body(
  receipt : RemoteTransferDestinationReceipt,
) -> Result[String, RemoteTransferIssue] {
  let writer = @encode.writer(4096, 16, 2) catch {
    _ => return Err(InvalidTransfer)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "destination_grant_cid")
    @encode.string_value(writer, receipt.destination_grant_cid)
    @encode.key(writer, "destination_material_generation")
    @encode.string_value(writer, receipt.destination_material_generation)
    @encode.key(writer, "destination_site_generation")
    @encode.number_value(
      writer,
      receipt.destination_site_generation.to_double(),
    )
    @encode.key(writer, "destination_site_key")
    @encode.string_value(writer, receipt.destination_site_key)
    @encode.key(writer, "physical_manifest_cid")
    @encode.string_value(writer, receipt.physical_manifest_cid)
    @encode.key(writer, "request_cid")
    @encode.string_value(writer, receipt.request_cid)
    @encode.key(writer, "version")
    @encode.string_value(
      writer, "actql-remote-transfer-destination-receipt/0.1",
    )
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidTransfer)
  }
}

///|
fn destination_receipt_identity(
  receipt : RemoteTransferDestinationReceipt,
) -> Result[String, RemoteTransferIssue] {
  let body = match destination_receipt_body(receipt) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidTransfer)
  }
}

///|
fn valid_destination_receipt(
  receipt : RemoteTransferDestinationReceipt,
) -> Bool {
  valid_transfer_cid(receipt.request_cid) &&
  !receipt.destination_site_key.is_empty() &&
  receipt.destination_site_generation >= 0 &&
  !receipt.destination_material_generation.is_empty() &&
  receipt.destination_material_generation.length() <= 256 &&
  valid_transfer_cid(receipt.physical_manifest_cid) &&
  valid_transfer_cid(receipt.destination_grant_cid) &&
  valid_transfer_cid(receipt.receipt_cid)
}

///|
pub fn prepare_destination_receipt(
  request : RemoteTransferRequest,
  destination_material_generation : String,
) -> Result[RemoteTransferDestinationReceipt, RemoteTransferIssue] {
  if !valid_request_fields(request) ||
    destination_material_generation.is_empty() ||
    destination_material_generation.length() > 256 {
    return Err(InvalidTransfer)
  }
  let pending : RemoteTransferDestinationReceipt = {
    request_cid: request.request_cid,
    destination_site_key: request.destination_site_key,
    destination_site_generation: request.destination_site_generation,
    destination_material_generation,
    physical_manifest_cid: request.physical_manifest_cid,
    destination_grant_cid: request.destination_grant_cid,
    receipt_cid: "pending",
  }
  let identity = match destination_receipt_identity(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, receipt_cid: identity, })
}

///|
pub fn destination_receipt_json(
  receipt : RemoteTransferDestinationReceipt,
) -> Result[String, RemoteTransferIssue] {
  if !valid_destination_receipt(receipt) {
    return Err(InvalidTransfer)
  }
  let identity = match destination_receipt_identity(receipt) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if identity != receipt.receipt_cid {
    return Err(TransferIdentityMismatch)
  }
  destination_receipt_body(receipt)
}

///|
pub fn destination_receipt_cid(
  receipt : RemoteTransferDestinationReceipt,
) -> String {
  receipt.receipt_cid
}

///|
pub fn destination_receipt_projection(
  receipt : RemoteTransferDestinationReceipt,
) -> Array[String] {
  [
    receipt.receipt_cid,
    receipt.request_cid,
    receipt.destination_site_key,
    receipt.destination_site_generation.to_string(),
    receipt.destination_material_generation,
    receipt.physical_manifest_cid,
    receipt.destination_grant_cid,
  ]
}

///|
pub fn admit_destination_receipt_json(
  body : String,
  request : RemoteTransferRequest,
  claimed_receipt_cid : String,
) -> Result[RemoteTransferDestinationReceipt, RemoteTransferIssue] {
  if !valid_request_fields(request) || body.length() > 4096 {
    return Err(InvalidTransfer)
  }
  try {
    let node = match
      @source.parse_json_bytes(@utf8.encode(body), {
        max_input_bytes: 4096,
        max_nodes: 16,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise RemoteTransferDecodeStop
    }
    let cursor = transfer_decoded(
      @decode.admit(node, {
        max_nodes: 16,
        max_depth: 2,
        max_string_bytes: 1024,
        max_total_string_bytes: 4096,
      }),
    )
    let object = transfer_decoded(
      @decode.closed_object(cursor, [
        "destination_grant_cid", "destination_material_generation", "destination_site_generation",
        "destination_site_key", "physical_manifest_cid", "request_cid", "version",
      ]),
    )
    if transfer_text(object, "version") !=
      "actql-remote-transfer-destination-receipt/0.1" {
      raise RemoteTransferDecodeStop
    }
    let generation = transfer_int(object, "destination_site_generation")
    let material = transfer_text(object, "destination_material_generation")
    let receipt = match prepare_destination_receipt(request, material) {
      Ok(value) => value
      Err(_) => raise RemoteTransferDecodeStop
    }
    if generation != receipt.destination_site_generation ||
      transfer_text(object, "destination_grant_cid") !=
      receipt.destination_grant_cid ||
      transfer_text(object, "destination_site_key") !=
      receipt.destination_site_key ||
      transfer_text(object, "physical_manifest_cid") !=
      receipt.physical_manifest_cid ||
      transfer_text(object, "request_cid") != receipt.request_cid ||
      receipt.receipt_cid != claimed_receipt_cid ||
      destination_receipt_json(receipt) != Ok(body) {
      return Err(TransferIdentityMismatch)
    }
    Ok(receipt)
  } catch {
    RemoteTransferDecodeStop => Err(InvalidTransfer)
  }
}
