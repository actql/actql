///|
/// Exact emitted shape and conservative text bound of the existing single
/// nonnullable Number Values pipeline. Names/id are borrowed checked owners;
/// computing these bounds does not emit a second tree or authorize compilation.
struct CompilationPipelineShape {
  facts : ClosedValuesLexicalFacts
  largest_object : Int
}

///|
fn compilation_pipeline_shape(
  fields:Int, rows:Int, field_name_units:Int, node_id_units:Int,
) -> CompilationPipelineShape? {
  if fields<1 || rows<0 || field_name_units<0 || node_id_units<0 {return None}
  let f=fields.to_int64()
  let r=rows.to_int64()
  let u=field_name_units.to_int64()
  let l=node_id_units.to_int64()
  let nodes=12L+3L*f+r*(1L+f)
  let objects=5L+r+f
  let keys=10L+3L*f+r*f
  let quoted=keys+4L+f
  // Avoid overflowing before rejecting an unrepresentable wire. Int inputs
  // permit these sums, but R*(29F+6U+2) can exceed signed Int64.
  let row_width=2L+29L*f+6L*u
  if r>0L && row_width>9223372036854775806L/r {return None}
  let row_bytes=if rows==0 {2L} else {1L+r*row_width}
  let schema_bytes=1L+38L*f+6L*u
  if row_bytes>2147483647L || schema_bytes>2147483647L {return None}
  let bytes=130L+12L*l+row_bytes+schema_bytes
  let text=73L+2L*l+u*(r+1L)+18L*f
  if nodes>2147483647L || objects>2147483647L || keys>2147483647L ||
    quoted>2147483647L || bytes>2147483647L || text>2147483647L {return None}
  Some({facts:{input_bytes:bytes.to_int(),node_upper:nodes.to_int(),objects:objects.to_int(),arrays:3,
    fields_upper:keys.to_int(),quoted_tokens:quoted.to_int(),quoted_utf16_units:text.to_int(),
    longest_quoted_utf16:Int::max(16,Int::max(field_name_units,node_id_units)),
    longest_atom_utf16:25,depth_upper:6},largest_object:Int::max(4,fields)})
}
