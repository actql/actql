///|
/// Immutable source geometry shared by the current scalar and compiler
/// construction domains. This DATA does not select a parser, prove ASCII
/// eligibility or authorize another input-preparation path.
struct ClosedValuesLexicalFacts {
  input_bytes : Int
  node_upper : Int
  objects : Int
  arrays : Int
  fields_upper : Int
  quoted_tokens : Int
  quoted_utf16_units : Int
  longest_quoted_utf16 : Int
  longest_atom_utf16 : Int
  depth_upper : Int
} derive(Eq, Debug)
