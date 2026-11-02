///|
fn source_facts_decimal_digits(value : Int64) -> Int64 {
  let mut rest = value
  let mut digits = 1L
  while rest >= 10L {
    rest /= 10L
    digits += 1L
  }
  digits
}

///|
/// The fixed deriveFinalViews producer in gcs-source-declaration.mjs, not a
/// generic declaration projection. It copies every initial view, then creates
/// file_listing and file_content/lookup_capacity facts and canonical strings.
/// The existing Common owner separately funds its snapshot and stringify.
/// Original CID strings are only measured; this grants no identity authority.
/// limits is the same eight original safe integers: listing items, examined
/// items, pages, attempts, listing bytes, duration, path bytes and page bytes.
pub fn source_facts_construction_capacity(
  view_count : Int,
  scope_cid : String,
  version_cid : String,
  listing_schema_cid : String,
  content_schema_cid : String,
  limits : Array[Int64],
) -> @execution.ExecutionCapacity? {
  if (view_count != 2 && view_count != 3) || limits.length() != 8 {
    return None
  }
  let mut digits = 0L
  for value in limits {
    if value < 0L || value > 9007199254740991L {
      return None
    }
    digits += source_facts_decimal_digits(value)
  }
  // Exact ASCII templates with CID slots empty and variable numbers zero:
  // listing431B/20nodes/3objects/1array/17fields; content+lookup425B/
  // 16nodes/4objects/15fields. Fixed lookup numbers1/2 remain in the template.
  // CID text can fail later identity validation: quote JSON escaping from its
  // actual original UTF-16 extent, not an assumed valid71-character digest.
  let cid_units = 2L * scope_cid.length().to_int64() +
    2L * version_cid.length().to_int64() +
    listing_schema_cid.length().to_int64() +
    content_schema_cid.length().to_int64()
  let wire_units = 431L + 425L - 8L + digits + 6L * cid_units
  let views = view_count.to_int64()
  let nodes = 36L
  let objects = 7L
  let fields = 32L
  // Object key populations are1,14,2,2,6,2,5. Sum k*(k-1)=238
  // co-counts both ordered comparison directions, including comparator's
  // destructuring iterator/frame alternatives. No whole input wire is nodes.
  let comparisons = 238L
  guard @shape.collection_construction_extent({
      // Seven fact objects, selectable array, and one7-property shallow copy
      // per view. Original schema/request/acquisition Strings remain borrowed.
      records: objects + views,
      record_references: fields + 7L * views,
      record_words: 13L,
      reference_arrays: 3L,
      reference_items: 2L + 2L * views,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: objects + views,
      map_entries: fields + 7L * views,
    })
    is Some(raw) &&
    @shape.collection_construction_extent({
      // canonicalJson(dataKeys=true): Object.entries/filter/map pairs,
      // key-set/map/sort scratch, encoded-member map/join, recursive options
      // objects, scalar callbacks and two view-map callback/control families.
      records: 4L * fields + 4L * nodes + 4L * comparisons + 4L * views + 16L,
      record_references: 8L * fields +
      8L * nodes +
      8L * comparisons +
      8L * views +
      32L,
      record_words: 4L * fields +
      6L * nodes +
      4L * comparisons +
      4L * views +
      16L,
      reference_arrays: 6L * objects + 2L * fields + 2L,
      reference_items: 10L * fields + 4L + nodes,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: objects,
      map_entries: fields,
    })
    is Some(canonical) else {
    return None
  }
  // Scalar quoted text, key/member fragments, comma joins and container
  // wrapping overlap through at most4 structural levels. Four complete text
  // families per level cover the entire synchronous canonical prefix, not
  // merely the two final Strings. The fixed32keys contain523 ASCII units.
  upload_peak_capacity({
    record_headers: raw.record_headers + canonical.record_headers,
    reference_slots: raw.reference_slots + canonical.reference_slots,
    scalar_words: raw.scalar_words + canonical.scalar_words,
    owned_utf16_units: 16L * wire_units + 2L * 523L + 2L * fields,
    owned_wire_bytes: 0L,
  })
}
