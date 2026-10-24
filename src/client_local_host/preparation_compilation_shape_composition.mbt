///|
/// Add disjoint emitted wrapper/child occurrences. Extras count their actual
/// JSON containers/fields, not an entire padded limit or a duplicated child.
fn compilation_add_wire_shapes(
  a:ClosedValuesLexicalFacts,b:ClosedValuesLexicalFacts,depth:Int,
) -> ClosedValuesLexicalFacts? {
  if depth<0 {return None}
  let values=[a.input_bytes.to_int64()+b.input_bytes.to_int64(),
    a.node_upper.to_int64()+b.node_upper.to_int64(),
    a.objects.to_int64()+b.objects.to_int64(),a.arrays.to_int64()+b.arrays.to_int64(),
    a.fields_upper.to_int64()+b.fields_upper.to_int64(),
    a.quoted_tokens.to_int64()+b.quoted_tokens.to_int64(),
    a.quoted_utf16_units.to_int64()+b.quoted_utf16_units.to_int64()]
  for v in values {if v<0L || v>2147483647L {return None}}
  Some({input_bytes:values[0].to_int(),node_upper:values[1].to_int(),objects:values[2].to_int(),
    arrays:values[3].to_int(),fields_upper:values[4].to_int(),quoted_tokens:values[5].to_int(),
    quoted_utf16_units:values[6].to_int(),longest_quoted_utf16:Int::max(a.longest_quoted_utf16,b.longest_quoted_utf16),
    longest_atom_utf16:Int::max(a.longest_atom_utf16,b.longest_atom_utf16),depth_upper:depth})
}

///|
fn compilation_fragment_shape(
  pipeline:ClosedValuesLexicalFacts,node_id_units:Int,
) -> ClosedValuesLexicalFacts? {
  if node_id_units<0 || pipeline.depth_upper==2147483647 {return None}
  let l=node_id_units.to_int64()
  let bytes=255L+12L*l
  let text=255L+2L*l
  if bytes>2147483647L || text>2147483647L {return None}
  compilation_add_wire_shapes(pipeline,{input_bytes:bytes.to_int(),node_upper:7,
    objects:3,arrays:0,fields_upper:7,quoted_tokens:11,quoted_utf16_units:text.to_int(),
    longest_quoted_utf16:Int::max(71,node_id_units),longest_atom_utf16:0,depth_upper:0},pipeline.depth_upper+1)
}

///|
/// Componentwise maximum is a conservative envelope of mutually exclusive
/// synchronous constructor scratch phases. Retained child values are composed
/// separately; this function is not permission to drop a live owner's holding.
fn compilation_scratch_max(
  a:PreparationRepresentationUnits,b:PreparationRepresentationUnits,
) -> PreparationRepresentationUnits {
  {record_headers:Int64::max(a.record_headers,b.record_headers),
    reference_slots:Int64::max(a.reference_slots,b.reference_slots),
    scalar_words:Int64::max(a.scalar_words,b.scalar_words),
    owned_utf16_units:Int64::max(a.owned_utf16_units,b.owned_utf16_units),
    owned_wire_bytes:Int64::max(a.owned_wire_bytes,b.owned_wire_bytes)}
}
