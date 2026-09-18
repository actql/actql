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
  CapturedSource(CapturedRows)
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
/// Registered logical Relation identity. Its preimage is the canonical object
/// `{sort:"relation",value:<ordered rows>}`, not the bare ordered-row array,
/// a physical payload digest, or a delivery hash.
struct LogicalRelationIdentity {
  cid : String
  bytes : Int
  nodes : Int
  rows : Int
}

///|
priv struct CapturedWireRows {
  rows : CapturedRows
}

///|
impl IndexedRows for CapturedWireRows with fn row_count(self) {
  captured_row_count(self.rows)
}

///|
impl IndexedRows for CapturedWireRows with fn column_count(self) {
  @schema.field_count(self.rows.schema)
}

///|
impl IndexedRows for CapturedWireRows with fn row_width(self, row) {
  self.rows.rows[row].length()
}

///|
impl IndexedRows for CapturedWireRows with fn read_cell(self, row, column) {
  capture(self.rows.rows[row][column])
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
  let order = match
    prepare_row_wire_order(names, limits.max_columns, limits.max_order_work) {
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
    for row in 0..<table.row_count() {
      if table.row_width(row) != width {
        return Err(InvalidLayout)
      }
      @encode.begin_object(writer)
      for (name, column) in order.columns {
        @encode.key(writer, name)
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
pub fn identify_captured_rows(
  rows : CapturedRows,
  limits : RowWireLimits,
) -> Result[RowWireIdentity, RowWireIssue] {
  if !row_wire_valid_limits(limits) {
    return Err(InvalidLimits)
  }
  let width = @schema.field_count(rows.schema)
  // The captured input adapter's name list also has a pre-allocation bound.
  if width > limits.max_columns || width > limits.max_order_work {
    return Err(OrderLimit)
  }
  let names = Array::makei(width, i => {
    @schema.reference_name(@schema.field_at(rows.schema, i).unwrap().name)
  })
  hash_row_wire(CapturedWireRows::{ rows, }, names, {
    ..limits,
    max_order_work: limits.max_order_work - width,
  }).map(value => {
    owner: CapturedSource(rows),
    cid: value.0,
    bytes: value.1,
    nodes: value.2,
    rows: captured_row_count(rows),
  })
}

///|
pub fn identify_completed_rows(
  output : CompletedOutput,
  limits : RowWireLimits,
) -> Result[RowWireIdentity, RowWireIssue] {
  if !row_wire_valid_limits(limits) {
    return Err(InvalidLimits)
  }
  guard output.table is Some(table) else {
    let receipt = output.representation.unwrap().receipt
    let width = @schema.field_count(receipt.schema)
    if width > limits.max_columns || width > limits.max_order_work {
      return Err(OrderLimit)
    }
    let names = Array::makei(width, column => {
      @schema.reference_name(
        @schema.field_at(receipt.schema, column).unwrap().name,
      )
    })
    match
      prepare_row_wire_order(names, limits.max_columns, limits.max_order_work) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if receipt.bytes > limits.max_bytes ||
      receipt.nodes > limits.max_nodes ||
      receipt.depth > limits.max_depth {
      return Err(Encoding(@encode.OutputLimit))
    }
    return Ok({
      owner: Output(output),
      cid: receipt.cid,
      bytes: receipt.bytes,
      nodes: receipt.nodes,
      rows: receipt.rows,
    })
  }
  hash_row_wire(table, RelationRows::field_names(table), limits).map(value => {
    owner: Output(output),
    cid: value.0,
    bytes: value.1,
    nodes: value.2,
    rows: completed_row_count(output),
  })
}

///|
pub fn row_wire_cid(value : RowWireIdentity) -> String {
  value.cid
}

///|
/// Machine-contract pin that defines the ordered typed-wire row-array CID used
/// by acquisition output and reused here. This is not a physical codec or a
/// Result relation-envelope identity.
pub fn ordered_rows_canonical_contract_cid() -> String {
  "sha256:4bb69dfaade0a15952fe23a8202a9475ff450c9f0fab93f9dd5cef1b82045ab1"
}

///|
pub fn row_wire_usage(value : RowWireIdentity) -> (Int, Int, Int) {
  (value.bytes, value.nodes, value.rows)
}

///|
pub fn logical_relation_cid(value : LogicalRelationIdentity) -> String {
  value.cid
}

///|
pub fn logical_relation_usage(
  value : LogicalRelationIdentity,
) -> (Int, Int, Int) {
  (value.bytes, value.nodes, value.rows)
}

///|
pub fn row_wire_matches_captured(
  value : RowWireIdentity,
  rows : CapturedRows,
) -> Bool {
  match value.owner {
    CapturedSource(owner) => physical_equal(owner, rows)
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
    CapturedSource(_) => false
  }
}
