///|
fn compilation_canonical_fixture(wire:String,s:CompilationCanonicalShape) -> Unit raise {
  let source=@source.parse_json(wire,{max_input_bytes:100000,max_nodes:s.nodes,max_depth:s.depth}).unwrap()
  let value=@identity.from_source(source,s.nodes,s.depth,100000,data_keys=true)
  let actual=@identity.representation_extent(value,s.nodes,s.depth,100000).unwrap()
  assert_eq(actual.nodes,s.nodes.to_int64())
  assert_eq(actual.arrays,s.arrays.to_int64())
  assert_eq(actual.objects,s.objects.to_int64())
  let quote=compilation_canonical_layout(s).unwrap()
  let containers=actual.arrays+actual.objects
  // Same selected layout, but use actually allocated backing capacity rather
  // than the preconstruction append upper. Text remains a shared source owner.
  let measured:PreparationRepresentationUnits={
    record_headers:actual.nodes+3L*containers+s.fields.to_int64(),
    reference_slots:actual.nodes+2L*containers+actual.array_backing_slots+actual.object_backing_slots+2L*s.fields.to_int64(),
    scalar_words:actual.nodes+2L*containers,
    owned_utf16_units:0L,owned_wire_bytes:0L,
  }
  assert_true(preparation_representation_cost(quote.tree).unwrap()>=preparation_representation_cost(measured).unwrap())
}

///|
test "compilation canonical quote covers actual source admission backing without copying text" {
  for rows in [0,1,17,100] {
    let data=Array::make(rows,"{\"v\":1}").join(",")
    let wire="{\"rows\":["+data+"],\"schema\":{\"v\":{\"nullable\":false,\"type\":\"number\"}}}"
    compilation_canonical_fixture(wire,{nodes:6+2*rows,arrays:1,objects:3+rows,fields:5+rows,depth:3,largest_object:2})
  }
  compilation_canonical_fixture("[[[[1]]]]",{nodes:5,arrays:4,objects:0,fields:0,depth:4,largest_object:0})
}

///|
test "compilation canonical quote rejects invalid shapes and bounds sort ancestry" {
  let small:CompilationCanonicalShape={nodes:2,arrays:0,objects:1,fields:1,depth:1,largest_object:1}
  assert_true(compilation_canonical_layout({..small,nodes:0}) is None)
  assert_true(compilation_canonical_layout({..small,fields:2}) is None)
  assert_true(compilation_canonical_layout({..small,largest_object:2}) is None)
  let wide=compilation_canonical_layout({nodes:101,arrays:0,objects:1,fields:100,depth:1,largest_object:100}).unwrap()
  assert_true(preparation_representation_cost(wide.temporary).unwrap()>preparation_representation_cost(compilation_canonical_layout(small).unwrap().temporary).unwrap())
}

///|
test "compilation canonical duplicate map ownership follows active ancestors not sibling count" {
  let narrow=compilation_canonical_layout({nodes:300001,arrays:1,objects:100000,fields:100000,depth:2,largest_object:1}).unwrap()
  let wide=compilation_canonical_layout({nodes:300001,arrays:1,objects:100000,fields:100000,depth:2,largest_object:100000}).unwrap()
  // Same retained tree; only private duplicate maps and sort width differ.
  assert_true(narrow.tree==wide.tree)
  assert_true(preparation_representation_cost(narrow.temporary).unwrap()<preparation_representation_cost(wide.temporary).unwrap())
}
