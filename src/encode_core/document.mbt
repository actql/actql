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
/// Embed only complete writer-owned JSON, preserving exact bytes. This is not
/// canonical normalization. Parent punctuation and all subtree budgets count.
pub fn emit_document(
  w : Writer,
  value : EncodedDocument,
) -> Unit raise EncodeFailure {
  active(w)
  if value.nodes > w.remaining_nodes ||
    value.depth > w.max_depth - w.frames.length() {
    fail(w, OutputLimit)
  }
  let depth = w.frames.length() + value.depth
  value_start(w)
  if value.bytes > w.remaining_bytes {
    fail(w, OutputLimit)
  }
  w.remaining_nodes -= value.nodes - 1
  w.remaining_bytes -= value.bytes
  w.peak_depth = w.peak_depth.max(depth)
  match w.output {
    TextOutput(output) => output.write_string(value.text)
    MeasureOutput => ()
  }
}
