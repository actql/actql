///|
/// Readonly facts of the current editable Source tree, not parse usage, domain
/// admission or a capacity charge. Shared Nodes, Fields, spans and Strings are
/// counted per occurrence. Source paths in both Node and key spans are included.
/// Backing slots include spare capacity; JS capacity is not an engine heap size.
/// The traversal's frame backing is scratch, separate from the observed tree.
pub(all) struct SourceRepresentationExtent {
  nodes : Int64
  fields : Int64
  spans : Int64
  strings : Int64
  text_utf16_units : Int64
  arrays : Int64
  objects : Int64
  array_backing_slots : Int64
  object_backing_slots : Int64
  max_frame_slots : Int64
} derive(Eq, Debug)

///|
pub(all) enum SourceRepresentationExtentIssue {
  InvalidLimits
  NodeLimit
  DepthLimit
  TextLimit
} derive(Eq, Debug)

///|
priv enum SourceRepresentationFrame {
  Visit(Node, Int)
  ArrayNext(Array[Node], Int, Int)
  ObjectNext(Array[Field], Int, Int)
}

///|
/// Observe the original fields without parsing, normalizing, encoding or
/// copying their arrays. Editable syntax is not an admitted immutable value:
/// this result describes this call only, and grants no authority or lifetime.
/// Limits also bound repeated aliases/cycles made through editable arrays.
/// Parser buffers, indexed decoder trees and returned facts remain separate.
pub fn representation_extent(
  root : Node,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
) -> Result[SourceRepresentationExtent, SourceRepresentationExtentIssue] {
  if max_nodes < 1 || max_depth < 0 || max_utf16_units < 0 {
    return Err(InvalidLimits)
  }
  let pending = [Visit(root, 0)]
  let mut extent : SourceRepresentationExtent = {
    nodes: 0L,
    fields: 0L,
    spans: 0L,
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
      Visit(node, depth) => {
        if extent.nodes >= max_nodes.to_int64() {
          return Err(NodeLimit)
        }
        if node.span.source_path.length().to_int64() >
          max_utf16_units.to_int64() - extent.text_utf16_units {
          return Err(TextLimit)
        }
        extent = {
          ..extent,
          nodes: extent.nodes + 1L,
          spans: extent.spans + 1L,
          strings: extent.strings + 1L,
          text_utf16_units: extent.text_utf16_units +
          node.span.source_path.length().to_int64(),
        }
        match node.value {
          Null | Bool(_) | Number(_) => ()
          String(text) => {
            if text.length().to_int64() >
              max_utf16_units.to_int64() - extent.text_utf16_units {
              return Err(TextLimit)
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
              return Err(DepthLimit)
            }
            extent = {
              ..extent,
              arrays: extent.arrays + 1L,
              array_backing_slots: extent.array_backing_slots +
              items.capacity().to_int64(),
            }
            pending.push(ArrayNext(items, 0, depth + 1))
          }
          Object(fields) => {
            if depth >= max_depth {
              return Err(DepthLimit)
            }
            extent = {
              ..extent,
              objects: extent.objects + 1L,
              object_backing_slots: extent.object_backing_slots +
              fields.capacity().to_int64(),
            }
            pending.push(ObjectNext(fields, 0, depth + 1))
          }
        }
      }
      ArrayNext(items, index, depth) =>
        if index < items.length() {
          pending.push(ArrayNext(items, index + 1, depth))
          pending.push(Visit(items[index], depth))
        }
      ObjectNext(fields, index, depth) =>
        if index < fields.length() {
          let field = fields[index]
          let text = field.key.length().to_int64() +
            field.key_span.source_path.length().to_int64()
          if text > max_utf16_units.to_int64() - extent.text_utf16_units {
            return Err(TextLimit)
          }
          extent = {
            ..extent,
            fields: extent.fields + 1L,
            spans: extent.spans + 1L,
            strings: extent.strings + 2L,
            text_utf16_units: extent.text_utf16_units + text,
          }
          pending.push(ObjectNext(fields, index + 1, depth))
          pending.push(Visit(field.value, depth))
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
