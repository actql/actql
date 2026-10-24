///|
/// Later plain captured-context issuance, AFTER snapshots already own their
/// canonical row arrays. This component does not price snapshot parse/admission
/// or Store re-admission. Scalar row objects have at most max_fields keys;
/// metadata_nodes bounds all non-row metadata occurrences in the capture.
/// Inputs must come from original publication owners/plan, never caller grants.
struct PublicationCaptureConstructorLayout {
  retained : PreparationRepresentationUnits
  temporary : PreparationRepresentationUnits
}

///|
fn publication_capture_constructor_layout(
  wire_bytes : Int, metadata_nodes : Int, depth : Int,
  results : Int, total_fields : Int, max_fields : Int, models : Int,
) -> PublicationCaptureConstructorLayout? {
  if wire_bytes<1 || metadata_nodes<1 || depth<1 || results<0 ||
    total_fields<0 || max_fields<0 || models<0 || (results==0 && (total_fields!=0 || max_fields!=0)) {return None}
  // A canonical row emitter visits one child at a time. Open ancestor object
  // keys comprise enclosing Result maps/roots, one row, and metadata siblings;
  // no map retains all rows' field names. The same ordered writer proves this.
  let live_keys=metadata_nodes.to_int64()+3L*results.to_int64()+max_fields.to_int64()+24L
  if live_keys>2147483647L || results>2147483647-models || depth>2147483645 {return None}
  guard @encode.hash_writer_live_key_inventory(live_keys.to_int(),depth) is Some(writer) &&
    closed_values_append_capacity(results) is Some(rc) &&
    closed_values_append_capacity(metadata_nodes) is Some(mc) &&
    closed_values_append_capacity(depth+2) is Some(dc) &&
    closed_values_append_capacity(results+models) is Some(ic) else {return None}
  let c=results.to_int64(); let f=total_fields.to_int64(); let m=models.to_int64()
  // Fixed root family majorant128H/256R/128W: context/envelope pre/post identity
  // root field tuples44H/88R; four root variants/frozen/array/backings16H/12R/8W;
  // nine empty metadata containers36H/27R/18W; material/inputs/phases6H/30R/8W;
  // result/contract/Some carriers8H/20R/16W. Remaining fixed slots are explicit
  // conservative slack, not a source-token census or physical stack charge.
  // Each Result adds three map tuples and its fields canonical array; field
  // String variants borrow names. Snapshot.rows and metadata values are shared.
  let retained : PreparationRepresentationUnits={
    record_headers:129L+7L*c+f+2L*m,
    reference_slots:256L+17L*c+3L*f+4L*m+3L*rc,
    scalar_words:128L+2L*c+2L*m,
    owned_utf16_units:wire_bytes.to_int64()+142L,
    owned_wire_bytes:0L,
  }
  // Context material/measuring→context hash→envelope measure→seal hash→seal
  // text are sequential. Slot clearing does not remove the caller
  // local: a finished material or measurement writer overlaps its successor.
  // Price TWO full writer control/key envelopes for that transition. Immutable
  // child values survive in retained; this deliberately overquotes residual
  // finished controls rather than asserting an immediate release.
  let writer_units : PreparationRepresentationUnits={
    record_headers:writer.record_headers,reference_slots:writer.reference_slots,
    scalar_words:writer.scalar_words,owned_utf16_units:writer.owned_utf16_units,
    owned_wire_bytes:writer.owned_wire_bytes,
  }
  // CanonicalEmit holds <=depth+2 frames, one mutable container cursor per
  // level, and its append backing. Text/key cursor storage is in writer_units.
  let emission : PreparationRepresentationUnits={
    record_headers:5L+2L*(depth.to_int64()+2L),
    reference_slots:5L+3L*(depth.to_int64()+2L)+dc,
    scalar_words:4L+2L*(depth.to_int64()+2L),
    owned_utf16_units:0L,owned_wire_bytes:0L,
  }
  // Protocol roots1882/2303 have maximum schema DAG chain10. Pending parent /
  // child frames plus pop/result overlap <=24. Result-values rule81 permits
  // arbitrary children without visiting row trees. Same-package regression
  // pins the generated graph; this is NOT a constant cap on input row count.
  let validation : PreparationRepresentationUnits={
    record_headers:29L,reference_slots:58L+32L,scalar_words:84L,
    owned_utf16_units:0L,owned_wire_bytes:0L,
  }
  // Unique metadata arrays (not row arrays) copy values and retain canonical
  // item Strings during comparison. All item wires together fit the enclosing
  // wire bound. No per-comparison history/closures are retained.
  let unique : PreparationRepresentationUnits={
    record_headers:4L+metadata_nodes.to_int64(),reference_slots:2L+2L*mc,
    scalar_words:4L,owned_utf16_units:wire_bytes.to_int64(),owned_wire_bytes:0L,
  }
  // TextOutput/StringBuilder + old/new backing and returned String coexist.
  // Four full wire UTF16 bounds are conservative; no claim about VM ropes/RSS.
  let text : PreparationRepresentationUnits={
    record_headers:6L,reference_slots:5L,scalar_words:6L,
    owned_utf16_units:4L*wire_bytes.to_int64(),owned_wire_bytes:0L,
  }
  // Capture inventories sort Result/model occurrences before materialization.
  // Two preparation/Sort records, key arrays with singleton String tuples,
  // detached selected arrays, and both integer merge backings are explicit.
  // Input values and names remain borrowed; no row traversal is repeated.
  let inventory : PreparationRepresentationUnits={
    record_headers:32L+2L*(c+m),reference_slots:64L+2L*(c+m)+4L*ic,
    scalar_words:64L+2L*(c+m)+6L*ic,owned_utf16_units:0L,owned_wire_bytes:0L,
  }
  guard closed_values_sum_layouts([writer_units,writer_units,emission,validation,unique,text,inventory]) is Some(temporary) &&
    preparation_representation_cost(retained) is Some(_) else {return None}
  Some({retained,temporary})
}
