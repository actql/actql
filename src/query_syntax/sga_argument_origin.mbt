///|
// Parser-issued, occurrence-indexed provenance. It is never reconstructed from
// equal values, source text, a Program path or a separately parsed document.
priv struct SgaCallProvenance {
  document : @origin.Document
  arguments : Array[(String, SgaArgument)]
  ranges : Array[(Int, Int)]
}

///|
impl @debug.Debug for SgaCallProvenance with fn to_repr(
  self : SgaCallProvenance,
) -> @debug.Repr {
  ignore(self)
  @debug.Repr::string("<parser argument origins>")
}

///|
// Provenance is diagnostic metadata, not a new semantic equality domain.
pub impl Eq for SgaCall with fn equal(self : SgaCall, other : SgaCall) -> Bool {
  self.operation == other.operation &&
  self.arguments == other.arguments &&
  self.start == other.start &&
  self.end == other.end
}

///|
/// Return the original top-level argument value range only for the same source
/// document and unchanged AST occurrence. The private snapshot is never exposed.
/// Copies of parser-owned calls retain provenance; mutated views do not retarget it.
/// This range describes the entire argument value, not a nested child expression.
pub fn sga_argument_origin(
  call : SgaCall,
  index : Int,
  document : @origin.Document,
) -> @origin.Origin? {
  guard index >= 0 &&
    index < call.arguments.length() &&
    index < call.provenance.arguments.length() &&
    call.arguments.length() == call.provenance.arguments.length() &&
    call.arguments[index] == call.provenance.arguments[index] else {
    return None
  }
  let (start, end) = call.provenance.ranges[index]
  guard @origin.range(call.provenance.document, start, end) is Ok(origin) else {
    return None
  }
  if @origin.belongs_to(document, origin) {
    Some(origin)
  } else {
    None
  }
}
