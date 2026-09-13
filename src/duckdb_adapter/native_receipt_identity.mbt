///|
pub(all) enum NativeReceiptIdentityIssue {
  InvalidState
  InvalidLimits
  ReceiptRows
  ReceiptBytes
  Wire(NativeReceiptRole, @execution.RowWireIssue)
}

///|
priv struct ReceiptDigest {
  order : @execution.RowWireOrder
  columns : Int
  cid : String
  bytes : Int
  nodes : Int
  rows : Int
  work : Int
}

///|
/// Digests of exact retained receipts, not evidence records or a capture permit.
/// The owning reception must remain live; matching JSON/CIDs are insufficient.
struct NativeReceiptIdentities {
  owner : NativeReceiving
  validation : ReceiptDigest
  native : ReceiptDigest
}

///|
fn hash_native_receipt(
  receiver : PhysicalResult,
  batches : Array[PhysicalBatch],
  limits : @execution.RowWireLimits,
) -> Result[ReceiptDigest, @execution.RowWireIssue] {
  let width = @schema.field_count(receiver.schema)
  if width > limits.max_columns || width > limits.max_order_work {
    return Err(OrderLimit)
  }
  let names = Array::makei(width, i => {
    @schema.reference_name(@schema.field_at(receiver.schema, i).unwrap().name)
  })
  let order = match
    @execution.prepare_row_wire_order(
      names,
      limits.max_columns,
      limits.max_order_work - width,
    ) {
    Ok(order) => order
    Err(issue) => return Err(issue)
  }
  try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @encode.begin_array(writer)
    for batch in batches {
      for row in 0..<batch.rows {
        @encode.begin_object(writer)
        for index in 0..<width {
          let (name, column) = @execution.row_wire_order_column(order, index).unwrap()
          @encode.key(writer, name)
          @admitted.emit_wire_value(
            physical_batch_cell(batch, row, column).unwrap().value,
            writer,
          )
        }
        @encode.end_object(writer)
      }
    }
    @encode.end_array(writer)
    let (hash, bytes, nodes) = @encode.finish_hash_usage(writer)
    Ok({
      order,
      columns: width,
      cid: "sha256:" + hash,
      bytes,
      nodes,
      rows: receiver.rows,
      work: width + @execution.row_wire_order_work(order),
    })
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
/// Hash both ordered typed-row arrays once in this operation. Wire byte/node/
/// ordering limits span both hashes; canonical receipt ceilings are independent
/// of physical writer bounds and Node transport frames. Failure aborts reception.
pub fn identify_native_receipts(
  value : NativeReceiving,
  limits : @execution.RowWireLimits,
  max_received_rows : Int,
  max_received_bytes : Int,
) -> Result[NativeReceiptIdentities, NativeReceiptIdentityIssue] {
  if !(value.phase is Received) {
    abort_native_receiving(value)
    return Err(InvalidState)
  }
  let result = identify_native_receipts_impl(
    value, limits, max_received_rows, max_received_bytes,
  )
  if result is Err(_) {
    abort_native_receiving(value)
  }
  result
}

///|
fn identify_native_receipts_impl(
  value : NativeReceiving,
  limits : @execution.RowWireLimits,
  max_rows : Int,
  max_bytes : Int,
) -> Result[NativeReceiptIdentities, NativeReceiptIdentityIssue] {
  if limits.max_columns < 0 ||
    limits.max_order_work < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 0 ||
    max_rows < 0 ||
    max_bytes < 0 {
    return Err(InvalidLimits)
  }
  let scan = value.validation.unwrap()
  let output = value.native.unwrap()
  if scan.rows > max_rows || output.rows > max_rows - scan.rows {
    return Err(ReceiptRows)
  }
  let validation = match
    hash_native_receipt(scan, value.validation_batches, limits) {
    Ok(digest) => digest
    Err(issue) => return Err(Wire(ValidationScan, issue))
  }
  if validation.bytes > max_bytes {
    return Err(ReceiptBytes)
  }
  let native = match
    hash_native_receipt(output, value.native_batches, {
      ..limits,
      max_bytes: limits.max_bytes - validation.bytes,
      max_nodes: limits.max_nodes - validation.nodes,
      max_order_work: limits.max_order_work - validation.work,
    }) {
    Ok(digest) => digest
    Err(issue) => return Err(Wire(NativeResult, issue))
  }
  if native.bytes > max_bytes - validation.bytes {
    return Err(ReceiptBytes)
  }
  Ok({ owner: value, validation, native, })
}

///|
pub fn native_receipts_match(
  receipts : NativeReceiptIdentities,
  owner : NativeReceiving,
) -> Bool {
  physical_equal(receipts.owner, owner) && owner.phase is Received
}

///|
fn receipt_digest(
  receipts : NativeReceiptIdentities,
  role : NativeReceiptRole,
) -> ReceiptDigest {
  match role {
    ValidationScan => receipts.validation
    NativeResult => receipts.native
  }
}

///|
pub fn native_receipt_digest(
  receipts : NativeReceiptIdentities,
  role : NativeReceiptRole,
) -> (String, Int, Int, Int) {
  let digest = receipt_digest(receipts, role)
  (digest.cid, digest.bytes, digest.nodes, digest.rows)
}

///|
pub fn native_receipt_field(
  receipts : NativeReceiptIdentities,
  role : NativeReceiptRole,
  index : Int,
) -> String? {
  let digest = receipt_digest(receipts, role)
  if index < 0 || index >= digest.columns {
    return None
  }
  @execution.row_wire_order_column(digest.order, index).map(pair => pair.0)
}
