///|
/// Bounds for canonical wire hashing, separate from expression logical work.
/// Column ordering charges UTF-16 comparison inputs before comparing them;
/// the shared writer bounds traversal and emission of all nested values.
pub(all) struct RowWireLimits {
  max_columns : Int
  max_order_work : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum RowWireIssue {
  InvalidLimits
  OrderLimit
  InvalidLayout
  Encoding(@encode.EncodeFailure)
}

///|
priv enum RowWireOwner {
  Receipt(QueryReceipt)
  Output(CompletedOutput)
}

///|
/// Canonical ordered rows, not acquisition evidence. Keep the exact immutable
/// source alive; equal hashes do not substitute for source/attempt ownership.
struct RowWireIdentity {
  owner : RowWireOwner
  cid : String
  bytes : Int
  nodes : Int
  rows : Int
}

///|
priv struct ReceiptWireRows {
  receipt : QueryReceipt
}

///|
impl IndexedRows for ReceiptWireRows with fn row_count(self) {
  captured_row_count(self.receipt.rows)
}

///|
impl IndexedRows for ReceiptWireRows with fn column_count(self) {
  @schema.field_count(self.receipt.rows.schema)
}

///|
impl IndexedRows for ReceiptWireRows with fn row_width(self, row) {
  self.receipt.rows.rows[row].length()
}

///|
impl IndexedRows for ReceiptWireRows with fn read_cell(self, row, column) {
  capture(self.receipt.rows.rows[row][column])
}

///|
fn row_wire_valid_limits(limits : RowWireLimits) -> Bool {
  limits.max_columns >= 0 &&
  limits.max_order_work >= 0 &&
  limits.max_bytes >= 0 &&
  limits.max_nodes >= 1 &&
  limits.max_depth >= 0
}

///|
/// The only allocated data-dependent storage is the bounded column permutation.
/// Physical rows/columns and selection views are read without materialization.
fn[T : IndexedRows] hash_row_wire(
  table : T,
  names : Array[String],
  limits : RowWireLimits,
) -> Result[(String, Int, Int), RowWireIssue] {
  if !row_wire_valid_limits(limits) {
    return Err(InvalidLimits)
  }
  let width = table.column_count()
  if width != names.length() {
    return Err(InvalidLayout)
  }
  if width > limits.max_columns || width > limits.max_order_work {
    return Err(OrderLimit)
  }
  let control = { remaining: limits.max_order_work - width, max_frames: 0, }
  let order : Array[Int] = []
  for i in 0..<width {
    let mut position = order.length()
    while position > 0 {
      let previous = names[order[position - 1]]
      if !spend_control(control, 1) ||
        !spend_control_text(control, names[i]) ||
        !spend_control_text(control, previous) {
        return Err(OrderLimit)
      }
      let comparison = @canonical.compare_utf16(previous, names[i])
      if comparison == 0 {
        return Err(InvalidLayout)
      }
      if comparison < 0 {
        break
      }
      position -= 1
    }
    order.push(i)
    for j = order.length() - 1; j > position; j = j - 1 {
      order[j] = order[j - 1]
    }
    order[position] = i
  }
  try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @encode.begin_array(writer)
    for row in 0..<table.row_count() {
      if table.row_width(row) != width {
        return Err(InvalidLayout)
      }
      @encode.begin_object(writer)
      for column in order {
        @encode.key(writer, names[column])
        emit_runtime_value(table.read_cell(row, column), writer)
      }
      @encode.end_object(writer)
    }
    let (hash, bytes, nodes) = {
      @encode.end_array(writer)
      @encode.finish_hash_usage(writer)
    }
    Ok(("sha256:" + hash, bytes, nodes))
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
pub fn identify_query_receipt_rows(
  receipt : QueryReceipt,
  limits : RowWireLimits,
) -> Result[RowWireIdentity, RowWireIssue] {
  if !row_wire_valid_limits(limits) {
    return Err(InvalidLimits)
  }
  let width = @schema.field_count(receipt.rows.schema)
  // The receipt adapter's name list also has a pre-allocation bound.
  if width > limits.max_columns || width > limits.max_order_work {
    return Err(OrderLimit)
  }
  let names = Array::makei(width, i => {
    @schema.reference_name(
      @schema.field_at(receipt.rows.schema, i).unwrap().name,
    )
  })
  hash_row_wire({ receipt, }, names, {
    ..limits,
    max_order_work: limits.max_order_work - width,
  }).map(value => {
    owner: Receipt(receipt),
    cid: value.0,
    bytes: value.1,
    nodes: value.2,
    rows: captured_row_count(receipt.rows),
  })
}

///|
pub fn identify_completed_rows(
  output : CompletedOutput,
  limits : RowWireLimits,
) -> Result[RowWireIdentity, RowWireIssue] {
  hash_row_wire(output.table, RelationRows::field_names(output.table), limits).map(value => {
      owner: Output(output),
      cid: value.0,
      bytes: value.1,
      nodes: value.2,
      rows: completed_row_count(output),
    },
  )
}

///|
pub fn row_wire_cid(value : RowWireIdentity) -> String {
  value.cid
}

///|
pub fn row_wire_usage(value : RowWireIdentity) -> (Int, Int, Int) {
  (value.bytes, value.nodes, value.rows)
}

///|
pub fn row_wire_matches_receipt(
  value : RowWireIdentity,
  receipt : QueryReceipt,
) -> Bool {
  match value.owner {
    Receipt(owner) => physical_equal(owner, receipt)
    Output(_) => false
  }
}

///|
pub fn row_wire_matches_output(
  value : RowWireIdentity,
  output : CompletedOutput,
) -> Bool {
  match value.owner {
    Output(owner) => physical_equal(owner, output)
    Receipt(_) => false
  }
}
