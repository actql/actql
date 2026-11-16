///|
/// Representation facts of an admitted tree, not serialized bytes or a heap
/// reservation. Shared values are counted per occurrence. Backing slots use
/// the current backend's actual capacity, including unused slots. A Host must
/// account for its adopted node, text, array and control layouts separately.
pub(all) struct CanonicalRepresentationExtent {
  nodes : Int64
  strings : Int64
  text_utf16_units : Int64
  arrays : Int64
  objects : Int64
  array_backing_slots : Int64
  object_backing_slots : Int64
  max_frame_slots : Int64
} derive(Eq, Debug)

///|
priv enum RepresentationFrame {
  Value(CanonicalValue, Int)
  ArrayNext(FrozenArray[CanonicalValue], Int, Int)
  ObjectNext(FrozenArray[(String, CanonicalValue)], Int, Int)
}

///|
/// Read the original immutable representation without encoding, copying its
/// backing arrays, or preparing another tree. Limits bound traversal and text;
/// this grants no lifetime, authority or funding. Scratch frames are reported
/// separately from retained representation facts.
pub fn representation_extent(
  value : CanonicalValue,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
) -> Result[CanonicalRepresentationExtent, CanonicalFailure] {
  if max_nodes < 1 || max_depth < 0 || max_utf16_units < 0 {
    return Err(InputLimit)
  }
  let pending = [Value(value, 0)]
  let mut extent : CanonicalRepresentationExtent = {
    nodes: 0L,
    strings: 0L,
    text_utf16_units: 0L,
    arrays: 0L,
    objects: 0L,
    array_backing_slots: 0L,
    object_backing_slots: 0L,
    max_frame_slots: pending.capacity().to_int64(),
  }
  while pending.pop() is Some(frame) {
    match frame {
      Value(value, depth) => {
        if extent.nodes >= max_nodes.to_int64() {
          return Err(InputLimit)
        }
        extent = { ..extent, nodes: extent.nodes + 1L, }
        match value {
          Null | Bool(_) | Number(_) => ()
          String(text) => {
            if text.length().to_int64() >
              max_utf16_units.to_int64() - extent.text_utf16_units {
              return Err(InputLimit)
            }
            extent = {
              ..extent,
              strings: extent.strings + 1L,
              text_utf16_units: extent.text_utf16_units +
              text.length().to_int64(),
            }
          }
          Array(items) => {
            if depth >= max_depth {
              return Err(InputLimit)
            }
            extent = {
              ..extent,
              arrays: extent.arrays + 1L,
              array_backing_slots: extent.array_backing_slots +
              items.values.capacity().to_int64(),
            }
            pending.push(ArrayNext(items, 0, depth + 1))
          }
          Object(fields) => {
            if depth >= max_depth {
              return Err(InputLimit)
            }
            extent = {
              ..extent,
              objects: extent.objects + 1L,
              object_backing_slots: extent.object_backing_slots +
              fields.values.capacity().to_int64(),
            }
            pending.push(ObjectNext(fields, 0, depth + 1))
          }
        }
      }
      ArrayNext(items, index, depth) =>
        if index < items.values.length() {
          pending.push(ArrayNext(items, index + 1, depth))
          pending.push(Value(items.values[index], depth))
        }
      ObjectNext(fields, index, depth) =>
        if index < fields.values.length() {
          let (name, child) = fields.values[index]
          if name.length().to_int64() >
            max_utf16_units.to_int64() - extent.text_utf16_units {
            return Err(InputLimit)
          }
          extent = {
            ..extent,
            strings: extent.strings + 1L,
            text_utf16_units: extent.text_utf16_units + name.length().to_int64(),
          }
          pending.push(ObjectNext(fields, index + 1, depth))
          pending.push(Value(child, depth))
        }
    }
    extent = {
      ..extent,
      max_frame_slots: Int64::max(
        extent.max_frame_slots,
        pending.capacity().to_int64(),
      ),
    }
  }
  Ok(extent)
}
