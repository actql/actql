///|
/// Project one retained file request into its draft Preview row. The expected
/// binding and mapping come from the checked installation and selected Effect.
/// The caller supplies the draft's shared unissued identity marker.
pub fn client_effect_file_preview_row(
  request : Json,
  binding : String,
  mapping : String,
  pending : String,
  deleting~ : Bool,
) -> Json? {
  guard request is Object(request) &&
    request.get("target") is Some(target) &&
    request.get("before") is Some(before) &&
    request.get("binding") is Some(String(original_binding)) &&
    original_binding == binding &&
    request.get("mapping") is Some(String(original_mapping)) &&
    original_mapping == mapping &&
    request.get("version") is Some(String(version)) else {
    return None
  }
  let value = match request.get("value") {
    None if deleting && request.length() == 5 => None
    Some(Object(_) as value) if !deleting && request.length() == 6 =>
      Some(value)
    _ => return None
  }
  Some(
    project_client_effect_file_preview_row(
      target,
      before,
      value,
      version,
      pending,
      Json::string,
      file_preview_json_object,
    ),
  )
}

///|
fn file_preview_json_object(fields : Array[(String, Json)]) -> Json {
  Json::object(Map::from_array(fields))
}

///|
// One row shape for the Native Json consumer and the bounded Wasm writer.
// Fields use canonical UTF-16 order when the writer emits them directly.
fn[T] project_client_effect_file_preview_row(
  target : T,
  before : T,
  value : T?,
  version : String,
  pending : String,
  text : (String) -> T,
  object : (Array[(String, T)]) -> T,
) -> T {
  let (after, intended_changes) = match value {
    Some(changes) =>
      (
        object([("state", text("present")), ("value", changes)]),
        object([("state", text("present")), ("value", changes)]),
      )
    None =>
      (
        object([("state", text("absent"))]),
        object([("state", text("not_applicable"))]),
      )
  }
  object([
    ("after", after),
    ("before", object([("state", text("present")), ("value", before)])),
    ("intended_changes", intended_changes),
    ("row_idempotency_key", text(pending)),
    ("row_preview_cid", text(pending)),
    (
      "target_guard",
      object([("state", text("version")), ("version_cid", text(version))]),
    ),
    ("target_row_identity", target),
  ])
}

///|
type FilePreviewRowEmitter = (@encode.Writer) -> Unit raise @encode.EncodeFailure

///|
fn file_preview_text_emitter(value : String) -> FilePreviewRowEmitter {
  writer => @encode.string_value(writer, value)
}

///|
fn file_preview_object_emitter(
  fields : Array[(String, FilePreviewRowEmitter)],
) -> FilePreviewRowEmitter {
  writer => {
    @encode.begin_object(writer)
    for (name, value) in fields {
      @encode.key(writer, name)
      value(writer)
    }
    @encode.end_object(writer)
  }
}

///|
/// Compose a draft UPDATE row from the documents that built the same checked
/// physical request. These inputs remain borrowed while the writer consumes them.
pub fn emit_client_effect_file_preview_update(
  writer : @encode.Writer,
  identity : String,
  before : @encode.EncodedDocument,
  changes : @encode.EncodedDocument,
  version : String,
  pending : String,
) -> Unit raise @encode.EncodeFailure {
  let emit_before : FilePreviewRowEmitter = writer => {
    @encode.emit_document(writer, before)
  }
  let emit_changes : FilePreviewRowEmitter = writer => {
    @encode.emit_document(writer, changes)
  }
  let emit = project_client_effect_file_preview_row(
    file_preview_text_emitter(identity),
    emit_before,
    Some(emit_changes),
    version,
    pending,
    file_preview_text_emitter,
    file_preview_object_emitter,
  )
  emit(writer)
}

///|
/// The file request parser retains its Json Map and Array backing. A row adds five objects and
/// fifteen fields (row, guard, three presence alternatives) and one request
/// CID entry. The parsed request's whole tree bounds the retained subtrees.
/// One lexical token, including the pinned 800-byte decimal fallback, is
/// temporary. Its scratch coexists with every preceding row prefix.
pub fn client_effect_file_preview_row_capacity(
  geometry : @source.JsonSourceGeometry,
) -> (Int64, Int64)? {
  let nodes = geometry.node_upper.to_int64()
  let fields = geometry.fields.to_int64()
  let depth = geometry.depth_upper.to_int64()
  let text = geometry.input_utf16_units.to_int64()
  guard @shape.collection_construction_extent({
      records: nodes + geometry.quoted_tokens.to_int64() + 20L,
      record_references: 2L * nodes + 24L,
      record_words: 3L * nodes + 20L,
      reference_arrays: geometry.arrays.to_int64(),
      reference_items: Int64::max(0L, nodes - fields - 1L),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: geometry.objects.to_int64() + 5L,
      map_entries: fields + 15L,
    })
    is Some(tree) &&
    @execution.preparation_representation_cost({
      record_headers: tree.record_headers,
      reference_slots: tree.reference_slots,
      scalar_words: tree.scalar_words,
      owned_utf16_units: text,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      // One parser context, lexer result and views, string builder
      // controls, active property/array tokens and failed token controls.
      // Include the common shape's five temporary field arrays and pairs.
      record_headers: 40L + 2L * depth,
      reference_slots: 84L + 3L * depth,
      scalar_words: 44L + 4L * depth,
      owned_utf16_units: 16L + 4L * text,
      owned_wire_bytes: 800L,
    })
    is Some(workspace) else {
    return None
  }
  Some((retained, workspace))
}
