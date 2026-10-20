///|
/// A bounded CLI container of existing admitted receipts. This has no identity
/// or authority of its own; membership and order are not authenticated by an
/// individual receipt. All members are admitted before any output is matched.
struct ClientResultDeliveryReceipts {
  receipts : Array[(String, Int64, String)]
  collection : Bool
}

///|
pub(all) enum ClientResultDeliveryReceiptIssue {
  InvalidContainer
  InvalidReceipt(Int, @publication.PublicationContractIssue)
  InvalidOutputDigest
  OutputMismatch
} derive(Eq, Debug)

///|
fn client_delivery_receipt_values(
  wire : String,
) -> Result[
  (@canonical.CanonicalValue, Array[@canonical.CanonicalValue], Bool),
  ClientResultDeliveryReceiptIssue,
] {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidContainer)
  }
  let value = @canonical.from_source(source, 8192, 64, 65536) catch {
    _ => return Err(InvalidContainer)
  }
  match value {
    @canonical.Object(_) => Ok((value, [value], false))
    @canonical.Array(items) => {
      let count = @canonical.array_count(items)
      if count > 16 {
        return Err(InvalidContainer)
      }
      Ok((value, @canonical.array_values(items), true))
    }
    _ => Err(InvalidContainer)
  }
}

///|
/// Accept the singleton object or a bounded ordered array. Unrelated malformed
/// members and bad self-CIDs fail the entire admission, including an otherwise
/// matching output. No Run receipt or command response is accepted here.
pub fn admit_client_result_delivery_receipts(
  wire : String,
) -> Result[ClientResultDeliveryReceipts, ClientResultDeliveryReceiptIssue] {
  let (_, values, collection) = match client_delivery_receipt_values(wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let receipts = []
  for index, value in values {
    let wire = @canonical.stringify_value(value, 65536, 8192, 64) catch {
      _ => return Err(InvalidContainer)
    }
    let contract = match
      @publication.admit_publication_contract(
        "result_delivery_receipt", wire, 65536, 8192, 64,
      ) {
      Ok(value) => value
      Err(issue) => return Err(InvalidReceipt(index, issue))
    }
    guard @canonical.object_field(value, "delivered_byte_count")
      is Some(@canonical.Number(count)) &&
      @canonical.object_field(value, "delivered_sha256")
      is Some(@canonical.String(digest)) else {
      return Err(InvalidContainer)
    }
    // The closed receipt admission above already requires a nonnegative safe
    // integer and lowercase SHA256. These are copied integrity facts only.
    receipts.push(
      (
        @publication.publication_contract_identity(contract),
        count.to_int64(),
        digest,
      ),
    )
  }
  Ok({ receipts, collection, })
}

///|
pub fn ClientResultDeliveryReceipts::count(
  self : ClientResultDeliveryReceipts,
) -> Int {
  self.receipts.length()
}

///|
pub fn ClientResultDeliveryReceipts::is_collection(
  self : ClientResultDeliveryReceipts,
) -> Bool {
  self.collection
}

///|
/// Match one actually observed file's byte count and SHA. Return every matching
/// identity in first occurrence order, deduplicating repeated identical members.
/// This says nothing about output files for other valid receipts in the input.
pub fn ClientResultDeliveryReceipts::matching_identities(
  self : ClientResultDeliveryReceipts,
  byte_count : Int64,
  sha256 : String,
) -> Result[Array[String], ClientResultDeliveryReceiptIssue] {
  if byte_count < 0L ||
    sha256.length() != 64 ||
    !sha256.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
    return Err(InvalidOutputDigest)
  }
  let matches : Array[String] = []
  for (identity, count, digest) in self.receipts {
    if count == byte_count && digest == sha256 && !matches.contains(identity) {
      matches.push(identity)
    }
  }
  if matches.is_empty() {
    Err(OutputMismatch)
  } else {
    Ok(matches)
  }
}

///|
/// Export only successful per-delivery receipt objects in authored request
/// order. One requested delivery preserves its existing canonical object bytes.
/// Multiple requests always use an array, even when zero or one succeeded.
/// Export neither retries a delivery nor certifies an aggregate success.
pub fn client_result_delivery_receipt_file(
  successful_receipts : Array[String],
  requested_deliveries : Int,
) -> Result[String, ClientResultDeliveryReceiptIssue] {
  if requested_deliveries < 1 ||
    requested_deliveries > 16 ||
    successful_receipts.length() > requested_deliveries ||
    (requested_deliveries == 1 && successful_receipts.length() != 1) {
    return Err(InvalidContainer)
  }
  let admitted : Array[String] = []
  for index, wire in successful_receipts {
    let receipt = match
      @publication.admit_publication_contract(
        "result_delivery_receipt", wire, 65536, 8192, 64,
      ) {
      Ok(value) => value
      Err(issue) => return Err(InvalidReceipt(index, issue))
    }
    admitted.push(@publication.publication_contract_json(receipt))
  }
  let wire = if requested_deliveries == 1 {
    admitted[0]
  } else {
    "[" + admitted.join(",") + "]"
  }
  // Bound the whole container as well as each member, including total nodes.
  match admit_client_result_delivery_receipts(wire) {
    Ok(_) => Ok(wire)
    Err(issue) => Err(issue)
  }
}
