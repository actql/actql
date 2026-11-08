///|
/// Construction DATA from the SAME bounded emission. Bytes/nodes/depth are
/// exact; container/field counts are conservative when an embedded subtree
/// supplies only its existing three-scalar measurement. No text, admission,
/// Resource capacity or semantic identity can be issued from these quantities.
pub(all) struct EncodingConstructionGeometry {
  bytes : Int
  nodes : Int
  depth : Int
  arrays : Int
  objects : Int
  fields : Int
  largest_object : Int
  strings : Int
  text_units : Int
} derive(Eq, Debug)

///|
priv struct ConstructionGeometryState {
  mut arrays : Int
  mut objects : Int
  mut fields : Int
  mut largest_object : Int
  mut strings : Int
  mut text_units : Int
}

///|
/// Same writer and validation, with six additional construction counters.
/// Other sinks and the existing plain measuring writer retain their layout.
pub fn construction_measuring_writer(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Writer raise EncodeFailure {
  create_writer(
    max_bytes,
    max_nodes,
    max_depth,
    GeometryOutput({
      arrays: 0,
      objects: 0,
      fields: 0,
      largest_object: 0,
      strings: 0,
      text_units: 0,
    }),
  )
}

///|
pub fn construction_geometry_usage(
  value : EncodingConstructionGeometry,
) -> (Int, Int, Int) {
  (value.bytes, value.nodes, value.depth)
}

///|
pub fn finish_construction_measurement(
  writer : Writer,
) -> EncodingConstructionGeometry raise EncodeFailure {
  active(writer)
  guard writer.output is GeometryOutput(state) else {
    fail(writer, InvalidStructure)
  }
  finish_state(writer)
  {
    bytes: writer.max_bytes - writer.remaining_bytes,
    nodes: writer.max_nodes - writer.remaining_nodes,
    depth: writer.peak_depth,
    arrays: state.arrays,
    objects: state.objects,
    fields: state.fields,
    largest_object: state.largest_object,
    strings: state.strings,
    text_units: state.text_units,
  }
}

///|
/// Compose SAME-emitter construction DATA. This cannot emit text/hash or
/// create an EncodedDocument. A caller without subtree shape uses the original
/// emit_measurement, whose unknown categories remain independently bounded by
/// its full node count rather than being assumed empty.
pub fn emit_construction_measurement(
  writer : Writer,
  value : EncodingConstructionGeometry,
) -> Unit raise EncodeFailure {
  active(writer)
  guard writer.output is GeometryOutput(_) else {
    fail(writer, InvalidStructure)
  }
  if value.bytes < 1 ||
    value.nodes < 1 ||
    value.depth < 0 ||
    value.depth > value.nodes ||
    value.arrays < 0 ||
    value.arrays > value.nodes ||
    value.objects < 0 ||
    value.objects > value.nodes ||
    value.fields < 0 ||
    value.fields >= value.nodes ||
    value.largest_object < 0 ||
    value.largest_object > value.fields ||
    value.strings < 0 ||
    value.strings > value.nodes ||
    value.text_units < 0 ||
    value.text_units > value.bytes {
    fail(writer, InvalidStructure)
  }
  reserve_document_extent(
    writer,
    value.bytes,
    value.nodes,
    value.depth,
    shape=Some(value),
  )
}

///|
fn observe_construction_container(writer : Writer, object~ : Bool) -> Unit {
  if writer.output is GeometryOutput(state) {
    if object {
      state.objects += 1
    } else {
      state.arrays += 1
    }
  }
}

///|
fn observe_construction_field(writer : Writer) -> Unit {
  if writer.output is GeometryOutput(state) {
    state.fields += 1
  }
}

///|
fn observe_embedded_construction(
  writer : Writer,
  nodes : Int,
  bytes : Int,
  shape : EncodingConstructionGeometry?,
) -> Unit {
  if writer.output is GeometryOutput(state) {
    match shape {
      Some(value) => {
        state.arrays += value.arrays
        state.objects += value.objects
        state.fields += value.fields
        state.strings += value.strings
        state.text_units += value.text_units
        state.largest_object = Int::max(
          state.largest_object,
          value.largest_object,
        )
      }
      None => {
        // Categories are independent bounds, not a disjoint classification.
        state.arrays += nodes
        state.objects += nodes
        state.fields += nodes - 1
        state.strings += nodes
        state.text_units += bytes
        state.largest_object = Int::max(state.largest_object, nodes - 1)
      }
    }
  }
}

///|
fn observe_construction_object_end(writer : Writer, fields : Int) -> Unit {
  if writer.output is GeometryOutput(state) {
    state.largest_object = Int::max(state.largest_object, fields)
  }
}

///|
// Called only after the original quoted emission completed, so its existing
// byte budget already bounds the accumulated decoded UTF16 units. No new scan
// or additional Unicode/escaping decision is performed here.
fn observe_construction_text(
  writer : Writer,
  units : Int,
  value~ : Bool,
) -> Unit {
  if writer.output is GeometryOutput(state) {
    state.text_units += units
    if value {
      state.strings += 1
    }
  }
}
