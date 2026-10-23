///|
priv enum MaterialFrame {
  MaterialArray(Array[CanonicalValue])
  MaterialObject(Array[(String, CanonicalValue)], String?)
}

///|
priv enum MaterialPending {
  MaterialIdle
  MaterialKey(@encode.OrderedKeyEmitCursor, String)
  MaterialText(@encode.StringEmitCursor, String)
  MaterialValue(CanonicalEmit, CanonicalValue)
}

///|
/// Canonical construction inside the existing admission owner. The private
/// measuring writer checks every occurrence, including retained children.
/// No partially constructed value or mutable backing array is exposed.
/// Container entries consume the writer's node budget and open frames its
/// depth budget. They become the final immutable backing arrays, not a second
/// copied tree. Key/text/child admission uses the existing bounded cursors.
struct CanonicalMaterial {
  writer : @encode.Writer
  frames : Array[MaterialFrame]
  mut pending : MaterialPending
  mut value : CanonicalValue?
  mut closed : Bool
}

///|
pub fn start_material(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> CanonicalMaterial raise @encode.EncodeFailure {
  {
    writer: @encode.measuring_writer(max_bytes, max_nodes, max_depth),
    frames: [],
    pending: MaterialIdle,
    value: None,
    closed: false,
  }
}

///|
fn CanonicalMaterial::idle(
  material : CanonicalMaterial,
) -> Unit raise @encode.EncodeFailure {
  if material.closed || !(material.pending is MaterialIdle) {
    raise @encode.ClosedWriter
  }
}

///|
fn CanonicalMaterial::append(
  material : CanonicalMaterial,
  value : CanonicalValue,
) -> Unit raise @encode.EncodeFailure {
  match material.frames.pop() {
    Some(MaterialArray(values)) => {
      values.push(value)
      material.frames.push(MaterialArray(values))
    }
    Some(MaterialObject(fields, Some(key))) => {
      fields.push((key, value))
      material.frames.push(MaterialObject(fields, None))
    }
    None if material.value is None => material.value = Some(value)
    _ => raise @encode.InvalidStructure
  }
}

///|
pub fn material_begin_object(
  material : CanonicalMaterial,
) -> Unit raise @encode.EncodeFailure {
  errdefer cancel_material(material)
  material.idle()
  @encode.begin_ordered_object(material.writer)
  material.frames.push(MaterialObject([], None))
}

///|
pub fn material_begin_array(
  material : CanonicalMaterial,
) -> Unit raise @encode.EncodeFailure {
  errdefer cancel_material(material)
  material.idle()
  @encode.begin_array(material.writer)
  material.frames.push(MaterialArray([]))
}

///|
pub fn material_end_object(
  material : CanonicalMaterial,
) -> Unit raise @encode.EncodeFailure {
  errdefer cancel_material(material)
  material.idle()
  @encode.end_object(material.writer)
  guard material.frames.pop() is Some(MaterialObject(fields, None)) else {
    raise @encode.InvalidStructure
  }
  material.append(Object({ values: fields, }))
}

///|
pub fn material_end_array(
  material : CanonicalMaterial,
) -> Unit raise @encode.EncodeFailure {
  errdefer cancel_material(material)
  material.idle()
  @encode.end_array(material.writer)
  guard material.frames.pop() is Some(MaterialArray(values)) else {
    raise @encode.InvalidStructure
  }
  material.append(Array({ values, }))
}

///|
pub fn material_key(
  material : CanonicalMaterial,
  key : String,
) -> Unit raise @encode.EncodeFailure {
  errdefer cancel_material(material)
  material.idle()
  material.pending = MaterialKey(
    @encode.start_ordered_key(material.writer, key),
    key,
  )
}

///|
pub fn material_text(
  material : CanonicalMaterial,
  text : String,
) -> Unit raise @encode.EncodeFailure {
  errdefer cancel_material(material)
  material.idle()
  material.pending = MaterialText(
    @encode.start_string_value(material.writer, text),
    text,
  )
}

///|
pub fn material_value(
  material : CanonicalMaterial,
  value : CanonicalValue,
) -> Unit raise @encode.EncodeFailure {
  errdefer cancel_material(material)
  material.idle()
  material.pending = MaterialValue(start_emit(value, material.writer), value)
}

///|
/// One existing bounded key/text/canonical-emitter transition. Reused children
/// still undergo complete aggregate byte/node/depth measurement before capture.
pub fn advance_material(
  material : CanonicalMaterial,
) -> Bool raise @encode.EncodeFailure {
  errdefer cancel_material(material)
  if material.closed {
    raise @encode.ClosedWriter
  }
  match material.pending {
    MaterialKey(cursor, key) => {
      if !@encode.advance_ordered_key(cursor) {
        return false
      }
      guard material.frames.pop() is Some(MaterialObject(fields, None)) else {
        raise @encode.InvalidStructure
      }
      material.frames.push(MaterialObject(fields, Some(key)))
    }
    MaterialText(cursor, text) => {
      if !@encode.advance_string_value(cursor) {
        return false
      }
      material.append(String(text))
    }
    MaterialValue(cursor, value) => {
      if !advance_emit(cursor) {
        return false
      }
      material.append(value)
    }
    MaterialIdle => raise @encode.InvalidStructure
  }
  material.pending = MaterialIdle
  true
}

///|
pub fn material_pending_frames(material : CanonicalMaterial) -> Int {
  match material.pending {
    MaterialValue(cursor, _) => emit_pending_frames(cursor)
    MaterialIdle => 0
    _ => 1
  }
}

///|
pub fn material_progress(
  material : CanonicalMaterial,
) -> (Int, Int, Int) raise @encode.EncodeFailure {
  if material.closed {
    raise @encode.ClosedWriter
  }
  @encode.writer_progress(material.writer)
}

///|
pub fn finish_material(
  material : CanonicalMaterial,
) -> (CanonicalValue, (Int, Int, Int)) raise @encode.EncodeFailure {
  errdefer cancel_material(material)
  material.idle()
  if !material.frames.is_empty() {
    raise @encode.InvalidStructure
  }
  guard material.value is Some(value) else { raise @encode.InvalidStructure }
  let usage = @encode.finish_measurement_usage(material.writer)
  material.value = None
  material.closed = true
  (value, usage)
}

///|
pub fn cancel_material(material : CanonicalMaterial) -> Unit {
  if material.closed {
    return
  }
  match material.pending {
    MaterialKey(cursor, _) => @encode.cancel_ordered_key(cursor)
    MaterialText(cursor, _) => @encode.cancel_string_value(cursor)
    MaterialValue(cursor, _) => cancel_emit(cursor)
    MaterialIdle => ()
  }
  @encode.cancel_writer(material.writer)
  material.pending = MaterialIdle
  material.frames.clear()
  material.value = None
  material.closed = true
}
