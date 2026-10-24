///|
/// Allocation-free structural envelope over the original ASCII JSON document.
/// This is NOT a parser or a semantic admission: malformed grammar can produce
/// facts and must still be rejected by the existing parser. Escaped/non-ASCII
/// text falls back to its existing path until its construction proof is wired.
/// Quoted keys are deliberately included in node_upper, an explicit overbound.
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

///|
/// max_work is the selected preparation scan allowance, not source-byte
/// authority. One original UTF16 unit is inspected once; no token substring,
/// JSON node, name inventory or traversal array is allocated by this scan.
fn closed_values_lexical_facts(
  source : String, max_work : Int,
) -> ClosedValuesLexicalFacts? {
  let size = source.length()
  if size == 0 || max_work < size { return None }
  let mut objects = 0
  let mut arrays = 0
  let mut fields = 0
  let mut quoted = 0
  let mut quoted_units = 0
  let mut longest_quoted = 0
  let mut longest_atom = 0
  let mut atoms = 0
  let mut depth = 0
  let mut maximum_depth = 0
  let mut in_string = false
  let mut string_units = 0
  let mut atom_units = 0
  for index in 0..<size {
    let unit = source[index].to_int()
    if unit > 127 { return None }
    if in_string {
      if unit == 34 {
        in_string = false
        longest_quoted = if longest_quoted > string_units { longest_quoted } else { string_units }
      } else {
        if unit == 92 || unit < 32 { return None }
        string_units += 1
        quoted_units += 1
      }
    } else if unit == 34 {
      atom_units = 0
      in_string = true
      string_units = 0
      quoted += 1
    } else if unit == 123 || unit == 91 {
      atom_units = 0
      if unit == 123 { objects += 1 } else { arrays += 1 }
      depth += 1
      maximum_depth = if maximum_depth > depth { maximum_depth } else { depth }
    } else if unit == 125 || unit == 93 {
      atom_units = 0
      if depth == 0 { return None }
      depth -= 1
    } else if unit == 58 {
      atom_units = 0
      fields += 1
    } else if unit == 44 || unit == 32 || unit == 9 || unit == 10 || unit == 13 {
      atom_units = 0
    } else {
      if !((unit >= 48 && unit <= 57) || (unit >= 65 && unit <= 90) ||
          (unit >= 97 && unit <= 122) || unit == 43 || unit == 45 || unit == 46) {
        return None
      }
      if atom_units == 0 { atoms += 1 }
      atom_units += 1
      longest_atom = if longest_atom > atom_units { longest_atom } else { atom_units }
    }
  }
  if in_string || depth != 0 { return None }
  // Counts denote disjoint token starts, so their sum is at most size.
  Some({input_bytes:size,node_upper:objects+arrays+quoted+atoms,
    objects,arrays,fields_upper:fields,quoted_tokens:quoted,
    quoted_utf16_units:quoted_units,longest_quoted_utf16:longest_quoted,
    longest_atom_utf16:longest_atom,depth_upper:maximum_depth})
}
