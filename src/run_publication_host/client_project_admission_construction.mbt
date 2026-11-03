///|
// No configuration parse is performed to quote its parse. The original wire
// is borrowed from its funded reader; exact UTF-8 length needs no encoded copy.
fn client_project_admission_geometry(wire : String) -> (Int, Int, Int)? {
  guard @scalar.admit_utf8_length(wire, 65536) is Ok(bytes) else { return None }
  let mut nodes = 1
  let mut depth = 0
  let mut maximum = 0
  let mut quoted = false
  let mut escaped = false
  for index in 0..<wire.length() {
    let unit = wire.code_unit_at(index).to_int()
    // Counting punctuation inside quoted bodies is conservative as well.
    if unit == 123 || unit == 91 {
      nodes = Int::min(4096, nodes + 2)
    } else if unit == 58 || unit == 44 || unit == 92 {
      nodes = Int::min(4096, nodes + 1)
    }
    if quoted {
      if escaped {
        escaped = false
      } else if unit == 92 {
        escaped = true
      } else if unit == 34 {
        quoted = false
      }
    } else if unit == 34 {
      quoted = true
    } else if unit == 123 || unit == 91 {
      depth += 1
      maximum = Int::max(maximum, depth)
    } else if unit == 125 || unit == 93 {
      depth = Int::max(0, depth - 1)
    }
  }
  Some((bytes, nodes, Int::min(16, Int::max(1, maximum))))
}

///|
fn client_project_admission_construction_inventory(
  wire : String,
  connection_entries : Bool,
) -> @execution.PreparationRepresentationUnits? {
  guard client_project_admission_geometry(wire) is Some((bytes, nodes, depth)) &&
    @decode.preserving_json_admission_construction_inventory(
      Int::max(1, bytes),
      nodes,
      depth,
    )
    is Some(decoded) else {
    return None
  }
  let n = nodes.to_int64()
  // Each selected entry is an immediate object value in the original wire.
  // Its span is disjoint from the other entries: total decoded output <=B.
  // BytesView + JS subarray view + decoder FixedArray + output String, cursor
  // field/span/Option carriers and the retained two/three-String entry tuple
  // are independent of the parser's original tree and indexed key backing.
  guard @shape.collection_construction_extent({
      records: 12L + 9L * n,
      record_references: 16L + (if connection_entries { 13L } else { 12L }) * n,
      record_words: 16L + 8L * n,
      reference_arrays: 1L,
      reference_items: n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(output) else {
    return None
  }
  @execution.compose_preparation_representation([
    {
      record_headers: decoded.record_headers,
      reference_slots: decoded.reference_slots,
      scalar_words: decoded.scalar_words,
      owned_utf16_units: decoded.owned_utf16_units,
      owned_wire_bytes: 0L,
    },
    {
      record_headers: output.record_headers + 1L,
      reference_slots: output.reference_slots,
      scalar_words: output.scalar_words,
      owned_utf16_units: bytes.to_int64(),
      // The admission itself encodes one new Bytes before the bounded parser.
      // That copy is not the reader's original byte/transfer allocation.
      owned_wire_bytes: bytes.to_int64(),
    },
  ])
}

///|
/// One actual Catalog admission, including preserving parse/index, the native
/// encoded byte original and retained entry-span Strings. No entry is parsed,
/// selected, admitted or installed by this constructor DATA operation.
pub fn client_project_catalog_admission_construction_inventory(
  wire : String,
) -> @execution.PreparationRepresentationUnits? {
  client_project_admission_construction_inventory(wire, false)
}

///|
/// Same original constructor family with three-String connection entries.
/// This does not grant connection access or replace original connector fields.
pub fn client_project_connections_admission_construction_inventory(
  wire : String,
) -> @execution.PreparationRepresentationUnits? {
  client_project_admission_construction_inventory(wire, true)
}
