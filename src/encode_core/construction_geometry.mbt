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
/// Same canonical dependency emission with its original synchronous work
/// view. This sink uses the existing ordered-key checker, so only depth-sized
/// frame/parent storage is needed before actual body geometry is known.
/// A declined/expired view closes the writer before the next work step.
pub fn work_construction_measuring_writer(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work : (Int) -> Bool,
) -> Writer raise EncodeFailure {
  create_writer(
    max_bytes,
    max_nodes,
    max_depth,
    WorkGeometryOutput(
      {
        arrays: 0,
        objects: 0,
        fields: 0,
        largest_object: 0,
        strings: 0,
        text_units: 0,
      },
      work,
      false,
    ),
  )
}

///|
// Private managed dependency census. Object order is irrelevant to geometry;
// admitted owners already establish keys. This sink cannot return text/hash
// or admit DATA; final owned emission retains canonical/identity checks.
pub fn work_construction_census_writer(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work : (Int) -> Bool,
) -> Writer raise EncodeFailure {
  create_writer(
    max_bytes,
    max_nodes,
    max_depth,
    WorkGeometryOutput(
      {
        arrays: 0,
        objects: 0,
        fields: 0,
        largest_object: 0,
        strings: 0,
        text_units: 0,
      },
      work,
      true,
    ),
  )
}

///|
pub fn construction_census_mode(writer : Writer) -> Bool {
  writer.output is WorkGeometryOutput(_, _, true)
}

///|
// Owned second pass of that SAME private dependency emission. No work
// callback is installed on legacy/public writers. Its caller funds the full
// measured construction before this builder and fresh synchronous view exist.
pub fn work_writer(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work : (Int) -> Bool,
) -> Writer raise EncodeFailure {
  create_writer(
    max_bytes,
    max_nodes,
    max_depth,
    WorkTextOutput(StringBuilder(), work),
  )
}

///|
/// Debit the actual next typed-graph/iterator step or borrowed String span.
/// Existing sinks have no work callback and retain their original behavior.
/// This is neither a node-count credit nor permission to emit an owned body.
pub fn construction_work_step(
  writer : Writer,
  units : Int,
) -> Unit raise EncodeFailure {
  match writer.output {
    WorkGeometryOutput(_, work, _)
    | WorkTextOutput(_, work)
    | WorkCompareOutput(_, work) => {
      active(writer)
      if units < 0 || !work(units) {
        fail(writer, OutputLimit)
      }
    }
    _ => ()
  }
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
  construction_work_step(writer, 1)
  let state = match writer.output {
    GeometryOutput(state) | WorkGeometryOutput(state, _, _) => state
    _ => fail(writer, InvalidStructure)
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
  guard writer.output is GeometryOutput(_) ||
    writer.output is WorkGeometryOutput(_, _, _) else {
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
  match writer.output {
    GeometryOutput(state) | WorkGeometryOutput(state, _, _) =>
      if object {
        state.objects += 1
      } else {
        state.arrays += 1
      }
    _ => ()
  }
}

///|
fn observe_construction_field(writer : Writer) -> Unit {
  match writer.output {
    GeometryOutput(state) | WorkGeometryOutput(state, _, _) => state.fields += 1
    _ => ()
  }
}

///|
fn observe_embedded_construction(
  writer : Writer,
  nodes : Int,
  bytes : Int,
  shape : EncodingConstructionGeometry?,
) -> Unit {
  match writer.output {
    GeometryOutput(state) | WorkGeometryOutput(state, _, _) =>
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
    _ => ()
  }
}

///|
fn observe_construction_object_end(writer : Writer, fields : Int) -> Unit {
  match writer.output {
    GeometryOutput(state) | WorkGeometryOutput(state, _, _) =>
      state.largest_object = Int::max(state.largest_object, fields)
    _ => ()
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
  match writer.output {
    GeometryOutput(state) | WorkGeometryOutput(state, _, _) => {
      state.text_units += units
      if value {
        state.strings += 1
      }
    }
    _ => ()
  }
}

///|
// Compare a duplicate DATA body's exact canonical emission without allocating
// a second text. The previous text belongs to this SAME funded export group;
// equality/CID is not a physical input/Source-owner sharing proof.
pub fn work_comparing_writer(
  expected : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work : (Int) -> Bool,
) -> Writer raise EncodeFailure {
  create_writer(
    max_bytes,
    max_nodes,
    max_depth,
    WorkCompareOutput({ expected, offset: 0, equal: true, }, work),
  )
}
