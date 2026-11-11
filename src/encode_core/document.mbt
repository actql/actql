///|
/// Complete writer-owned JSON with its exact emitted UTF-8 byte length.
/// Abstract and immutable: callers cannot forge a text/count pair.
struct EncodedDocument {
  text : String
  bytes : Int
  nodes : Int
  depth : Int
}

///|
pub fn finish_document(w : Writer) -> EncodedDocument raise EncodeFailure {
  let text = finish(w)
  {
    text,
    bytes: w.max_bytes - w.remaining_bytes,
    nodes: w.max_nodes - w.remaining_nodes,
    depth: w.peak_depth,
  }
}

///|
pub fn document_text(value : EncodedDocument) -> String {
  value.text
}

///|
pub fn document_bytes(value : EncodedDocument) -> Int {
  value.bytes
}

///|
/// Original completed writer facts, without scanning, encoding or parsing.
pub fn document_usage(value : EncodedDocument) -> (Int, Int, Int) {
  (value.bytes, value.nodes, value.depth)
}

///|
/// Embed only complete writer-owned JSON, preserving exact bytes. This is not
/// canonical normalization. Parent punctuation and all subtree budgets count.
pub fn emit_document(
  w : Writer,
  value : EncodedDocument,
) -> Unit raise EncodeFailure {
  reserve_document_extent(w, value.bytes, value.nodes, value.depth)
  match w.output {
    TextOutput(output) => output.write_string(value.text)
    MeasureOutput | GeometryOutput(_) => ()
    CompareOutput(output) =>
      compare_range(output, value.text, 0, value.text.length())
    BufferedTextOutput(buffer) => buffer.text.write_string(value.text)
    HashOutput(h) =>
      // EncodedDocument text is already validated; stream its scalar UTF-8 bytes.
      for scalar in value.text.iter() {
        hash_scalar(w, h, scalar.to_int())
      }
    BufferedHashOutput(buffer) => {
      for scalar in value.text.iter() {
        hash_scalar(w, buffer.hash, scalar.to_int())
      }
      buffer.text.write_string(value.text)
    }
  }
}

///|
// The same parent separators, node debit and depth offset apply to real
// documents and text-free compiler measurements. This helper issues no text.
fn reserve_document_extent(
  w : Writer,
  bytes : Int,
  nodes : Int,
  depth : Int,
  shape? : EncodingConstructionGeometry? = None,
) -> Unit raise EncodeFailure {
  active(w)
  if nodes > w.remaining_nodes || depth > w.max_depth - w.frames.length() {
    fail(w, OutputLimit)
  }
  let peak = w.frames.length() + depth
  value_start(w)
  if bytes > w.remaining_bytes {
    fail(w, OutputLimit)
  }
  reserve_buffer(w, bytes)
  w.remaining_nodes -= nodes - 1
  w.remaining_bytes -= bytes
  w.peak_depth = w.peak_depth.max(peak)
  observe_embedded_construction(w, nodes, bytes, shape)
}

///|
/// Compose a completed subtree measurement without constructing its wire.
/// Counts are DATA only: this operation accepts only a measuring writer and
/// cannot create encoded text, a hash, a comparison result or an admitted tree.
/// The caller retains the same original serializer and its measured subtree.
pub fn emit_measurement(
  w : Writer,
  measurement : (Int, Int, Int),
) -> Unit raise EncodeFailure {
  active(w)
  guard w.output is MeasureOutput || w.output is GeometryOutput(_) else {
    fail(w, InvalidStructure)
  }
  let (bytes, nodes, depth) = measurement
  if bytes < 1 || nodes < 1 || depth < 0 || depth > nodes {
    fail(w, InvalidStructure)
  }
  reserve_document_extent(w, bytes, nodes, depth)
}
