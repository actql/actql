///|
/// Constructor DATA for the original collect/observe_collect reader. Returned
/// bounds include growable backing, not a minimum or a physical-release claim.
/// A failed reader returns only its typed issue; its partially constructed
/// owners remain covered until that call returns. Original Source/tree/names
/// and supplied Limits are borrowed and separately backed by their owner.
pub(all) struct CollectionConstructionInventory {
  returned : @shape.CollectionConstructionExtent
  temporary : @shape.CollectionConstructionExtent
  returned_utf16_units : Int64
  temporary_utf16_units : Int64
} derive(Eq, Debug)

///|
fn collection_geometry_fits(g : CollectionConstructionGeometry) -> Bool {
  g.stages >= 0 &&
  g.inputs >= 0 &&
  g.remotes >= 0 &&
  g.remotes <= g.inputs &&
  g.max_stage_fields >= 0 &&
  g.max_input_fields >= 0 &&
  g.max_remote_fields >= 0 &&
  g.max_remote_nodes >= 0 &&
  g.max_request_fields >= 0 &&
  g.max_meta_fields >= 0 &&
  g.max_scan_fields >= 0 &&
  g.max_duplicates_fields >= 0 &&
  g.max_duplicates_items >= 0 &&
  g.max_first_fields >= 0 &&
  g.normalization_calls >= 0 &&
  g.normalization_calls.to_int64() <= 3L * g.remotes.to_int64() &&
  g.normalization_utf16 >= 0L &&
  g.max_normalization_utf16 >= 0 &&
  g.max_normalization_utf16.to_int64() <= g.normalization_utf16 &&
  g.order_owners >= 0 &&
  g.order_owners <= g.remotes &&
  g.order_terms >= g.order_owners &&
  g.max_order_fields >= 0 &&
  g.max_path_segments >= (if g.remotes > 0 { 9L } else { 0L }) &&
  g.inspection_work >= 0L
}

///|
/// The SAME original widths, semantic budgets and constructor owners supply
/// this bound. This does not run collection, normalize text, admit an order,
/// select a Catalog or price bytes. Callers must fund the metadata/quote frame
/// before entry and bind its original Source/limits before issuing capacity.
pub fn collect_construction_inventory(
  g : CollectionConstructionGeometry,
  limits : Limits,
) -> CollectionConstructionInventory? {
  let zero : @shape.CollectionConstructionExtent = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
  }
  if collection_limits_invalid(limits) {
    // Original InvalidLimits/Err, before Budget, entries or by_name creation.
    return Some({
      returned: zero,
      temporary: { record_headers: 2L, reference_slots: 1L, scalar_words: 2L, },
      returned_utf16_units: 0L,
      temporary_utf16_units: 0L,
    })
  }
  if !collection_geometry_fits(g) {
    return None
  }
  let work = limits.max_work.to_int64()
  // Every remote is selected only after charged input/field work. Each
  // nonempty order consumes the original order budget BEFORE its keys Array.
  // These are construction-prefix bounds, not new logical row/input caps.
  let declarations = Int64::min(g.remotes.to_int64(), work)
  let keys = Int64::min(
    Int::min(g.order_terms, limits.max_order_keys).to_int64(),
    work,
  )
  let order_arrays = Int64::min(
    Int64::min(g.order_owners.to_int64(), keys),
    declarations,
  )
  let names = Int64::min(g.normalization_calls.to_int64(), 3L * declarations)
  let name_units = Int64::min(g.normalization_utf16, work)
  guard @canonical.nfc_lf_retained_output_units(name_units) is Some(text) else {
    return None
  }
  let key = @order.read_retained_construction_extent()
  // Inputs1H3R1W and returned Ok1H1R1W. Per declaration: record1H9R1W,
  // by_name tuple1H1R1W, original input/request Cursors2H4R2W, five optional
  // positions5H4R6W. Returned normalized Strings own one header each.
  // Each order Key retains the SAME caller-created term Cursor1H2R1W in
  // addition to its order-owned long-field Cursor. by_name aliases the same
  // Declaration; it does not clone it or the original names/tree.
  guard @shape.collection_construction_extent({
      records: 2L + 9L * declarations + names + (key.record_headers + 1L) * keys,
      record_references: 4L +
      18L * declarations +
      (key.reference_slots + 2L) * keys,
      record_words: 2L + 10L * declarations + (key.scalar_words + 1L) * keys,
      reference_arrays: 1L + order_arrays,
      reference_items: declarations + keys,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: declarations,
    })
    is Some(returned) else {
    return None
  }
  let active = g.stages > 0 && work >= g.stages.to_int64()
  let remote = active && g.remotes > 0
  // Preflight charges every child/field before constructing the later maps
  // or order reader. A wide input that exceeds work refuses before that map;
  // retain its actual bounded constructor prefix rather than a policy maximum.
  let fields = fn(n : Int) { Int::min(n, limits.max_work) }
  let root_depth = if remote { g.max_path_segments - 9L } else { 0L }
  let child = @decode.indexed_child_construction_extent()
  let field = @decode.indexed_field_construction_extent()
  // Budget1H2W; stage_at/pop options2H2R2W; one scalar ValueView1H1R2W;
  // eight object/array-length Some payloads8H16W; six required Ok6H6R6W;
  // original Decode/InvalidValue/InvalidMetadata/Order/Stop/Err6H6R6W.
  // Fourteen named child sites: stage inputs; outer connector/resource;
  // eight remote properties; scan mode; first_by_order/order_by. Three field
  // frames cover outer input, preflight and meta loops. Alternatives are
  // conservatively co-counted; they are replaced, not multiplied by inputs.
  guard @shape.collection_construction_extent({
      records: 1L +
      (if active {
        23L + 14L * child.record_headers + 3L * field.record_headers
      } else {
        2L
      }),
      record_references: if active {
        15L + 14L * child.reference_slots + 3L * field.reference_slots
      } else {
        2L
      },
      record_words: 2L +
      (if active {
        32L + 14L * child.scalar_words + 3L * field.scalar_words
      } else {
        2L
      }),
      // The literal eight allowed remote names survive the read_input frame;
      // scan/duplicates/first_by_order's three one-name arrays are co-counted.
      reference_arrays: if remote {
        4L
      } else {
        0L
      },
      reference_items: if remote {
        11L
      } else {
        0L
      },
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(frame) else {
    return None
  }
  let stage = if active {
    @decode.open_object_construction_extent(g.max_stage_fields)
  } else {
    Some(zero)
  }
  let input = if active && g.inputs > 0 {
    @decode.open_object_construction_extent(fields(g.max_input_fields))
  } else {
    Some(zero)
  }
  let body = if remote {
    @decode.closed_object_field_construction_extent(
      Some(fields(g.max_remote_fields)),
      8,
      root_depth + 4L,
    )
  } else {
    Some(zero)
  }
  let request = if remote {
    @decode.open_object_construction_extent(fields(g.max_request_fields))
  } else {
    Some(zero)
  }
  let metadata = if remote {
    @decode.open_object_construction_extent(fields(g.max_meta_fields))
  } else {
    Some(zero)
  }
  let scan = if remote {
    @decode.closed_object_field_construction_extent(
      Some(fields(g.max_scan_fields)),
      1,
      root_depth + 5L,
    )
  } else {
    Some(zero)
  }
  let duplicates = if remote {
    @decode.closed_object_field_construction_extent(
      Some(fields(g.max_duplicates_fields)),
      1,
      root_depth + 5L,
    )
  } else {
    Some(zero)
  }
  let first = if remote {
    @decode.closed_object_field_construction_extent(
      Some(fields(g.max_first_fields)),
      1,
      root_depth + 6L,
    )
  } else {
    Some(zero)
  }
  let order = if remote && keys > 0L {
    @order.read_construction_extent(fields(g.max_order_fields), root_depth + 8L)
  } else {
    Some(zero)
  }
  let issue = if active {
    @decode.issue_path_construction_extent(g.max_path_segments)
  } else {
    Some(zero)
  }
  guard stage is Some(stage) &&
    input is Some(input) &&
    body is Some(body) &&
    request is Some(request) &&
    metadata is Some(metadata) &&
    scan is Some(scan) &&
    duplicates is Some(duplicates) &&
    first is Some(first) &&
    order is Some(order) &&
    issue is Some(issue) else {
    return None
  }
  // preflight's original pending Array starts with a borrowed root. Child
  // counts are charged BEFORE push, bounding all created child Cursors by
  // min(original nodes,work+1). Native pop preserves vacated references: count
  // the whole backing through return, never its final logical length zero.
  let pending = if remote {
    Int64::max(1L, Int64::min(g.max_remote_nodes.to_int64(), work + 1L))
  } else {
    0L
  }
  let view_items = if remote {
    fields(g.max_duplicates_items).to_int64()
  } else {
    0L
  }
  guard @shape.collection_construction_extent({
      records: pending + view_items + (if remote { 2L } else { 0L }),
      record_references: 2L * (pending + view_items) +
      (if remote { 2L } else { 0L }),
      record_words: pending + view_items + (if remote { 2L } else { 0L }),
      reference_arrays: if remote {
        2L
      } else {
        0L
      },
      reference_items: pending + view_items,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(traversal) else {
    return None
  }
  // duplicates' original shallow view constructs its own ObjectView or child
  // Array before the closed policy read. Opaque grandchildren are borrowed.
  let view = if remote {
    @decode.open_object_construction_extent(fields(g.max_duplicates_fields))
  } else {
    Some(zero)
  }
  guard view is Some(view) else { return None }
  let normalization = if names > 0L {
    @canonical.nfc_lf_construction_scratch_extent(
      Int::min(g.max_normalization_utf16, limits.max_work),
    )
  } else {
    None
  }
  let normalization_units : @shape.CollectionConstructionExtent = match
    normalization {
    None => zero
    Some(n) =>
      {
        record_headers: n.record_headers,
        reference_slots: n.reference_slots,
        scalar_words: n.scalar_words,
      }
  }
  let mut temporary = frame
  for
    part in [
      stage, input, body, request, metadata, scan, duplicates, first, order, issue,
      traversal, view, normalization_units,
    ] {
    guard @shape.add_collection_construction_extents(temporary, part)
      is Some(sum) else {
      return None
    }
    temporary = sum
  }
  Some({
    returned,
    temporary,
    returned_utf16_units: text,
    temporary_utf16_units: normalization
    .map(n => n.owned_utf16_units)
    .unwrap_or(0L),
  })
}
