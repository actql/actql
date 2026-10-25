///|
test "closed Values literal owners count numeric cells independently from source backing" {
  let empty = closed_values_literal_layout(1,0).unwrap()
  assert_eq(empty.retained.record_headers,18L)
  assert_eq(empty.retained.reference_slots,28L)
  assert_eq(empty.retained.scalar_words,22L)
  let one = closed_values_literal_layout(1,1).unwrap()
  assert_eq(one.retained.record_headers,26L)
  assert_eq(one.retained.reference_slots,55L)
  assert_eq(one.retained.scalar_words,29L)
  assert_eq(one.retained.owned_utf16_units,0L)
  assert_eq(one.retained.owned_wire_bytes,0L)
  assert_eq(one.cell_count,1L)
  let wide = closed_values_literal_layout(100,99).unwrap()
  assert_eq(wide.cell_count,9900L)
  assert_eq(wide.field_capacity,128L)
  assert_eq(wide.row_capacity,128L)
  assert_eq(wide.retained.record_headers,40212L)
  assert_eq(wide.retained.reference_slots,73041L)
  assert_eq(wide.retained.scalar_words,40117L)
}

///|
test "closed Values literal layout rejects invalid dimensions and tariff overflow" {
  assert_true(closed_values_literal_layout(0,1) is None)
  assert_true(closed_values_literal_layout(-1,1) is None)
  assert_true(closed_values_literal_layout(1,-1) is None)
  assert_true(closed_values_literal_layout(2147483647,2147483647) is None)
  for (length,expected) in [(0,0L),(1,8L),(8,8L),(9,16L),(16,16L),(17,32L),(99,128L),(100,128L)] {
    assert_eq(closed_values_append_capacity(length),Some(expected))
  }
  for fields in 1..<8 {
    let a = closed_values_literal_layout(fields,3).unwrap().retained
    let b = closed_values_literal_layout(fields+1,3).unwrap().retained
    assert_eq(b.record_headers-a.record_headers,14L)
    assert_eq(b.reference_slots-a.reference_slots,20L)
    assert_eq(b.scalar_words-a.scalar_words,14L)
  }
}

///|
test "closed Values lower and DAG owner components retain borrowed rows only once" {
  let lower = closed_values_lower_retained_layout()
  assert_eq(preparation_representation_cost(lower),Some(1000L))
  let graph = closed_values_dag_retained_layout()
  assert_eq(preparation_representation_cost(graph),Some(1456L))
  assert_eq(graph.owned_utf16_units,0L)
  assert_eq(graph.owned_wire_bytes,0L)
  // Changing row dimensions changes literal owners, not the borrowing
  // BoundPrepared/CheckedDAG components. Neither is a second row allocation.
  let one = closed_values_literal_layout(1,1).unwrap().retained
  let many = closed_values_literal_layout(1,100).unwrap().retained
  assert_true(preparation_representation_cost(many).unwrap() > preparation_representation_cost(one).unwrap())
  assert_eq(lower.owned_utf16_units,8L)
}

///|
test "closed Values pipeline accounts separately for copied carrier field wrappers" {
  let one=closed_values_pipeline_retained_layout(1).unwrap()
  let wide=closed_values_pipeline_retained_layout(100).unwrap()
  assert_eq(one.record_headers,82L)
  assert_eq(one.reference_slots,259L)
  assert_eq(one.scalar_words,140L)
  assert_eq(wide.record_headers-one.record_headers,297L)
  assert_eq(wide.reference_slots-one.reference_slots,495L)
  assert_eq(wide.scalar_words-one.scalar_words,297L)
  assert_eq(wide.owned_utf16_units,0L)
  assert_true(closed_values_pipeline_retained_layout(0) is None)
}

///|
test "closed Values checker wrapper tables have one stage and no operation limits" {
  let wrappers=closed_values_program_wrappers_layout()
  assert_eq(preparation_representation_cost(wrappers),Some(2488L))
  assert_eq(wrappers.owned_utf16_units,0L)
  assert_eq(wrappers.owned_wire_bytes,0L)
}

///|
test "closed Values map and traversal components include growth coexistence" {
  let six=closed_values_map_constructor_layout(6).unwrap()
  let seven=closed_values_map_constructor_layout(7).unwrap()
  assert_eq(six.record_headers,27L)
  assert_eq(six.reference_slots,54L)
  assert_eq(seven.record_headers,31L)
  assert_eq(seven.reference_slots,76L)
  let walk=closed_values_walk_storage_layout(9,3).unwrap()
  assert_eq(walk.record_headers,41L)
  assert_eq(walk.reference_slots,99L)
  assert_eq(walk.scalar_words,41L)
  assert_true(closed_values_walk_storage_layout(0,0) is None)
  assert_true(closed_values_walk_storage_layout(1,2) is None)
  assert_true(closed_values_map_constructor_layout(-1) is None)
}

///|
test "closed Values numeric admission scratch is one original cell transition" {
  let scratch=closed_values_numeric_admission_scratch_layout()
  assert_eq(preparation_representation_cost(scratch),Some(648L))
  assert_eq(scratch.owned_wire_bytes,0L)
  assert_eq(scratch.owned_utf16_units,0L)
}

///|
test "closed Values Number contract scratch includes both decoder views" {
  let maps=closed_values_map_constructor_layout(2).unwrap()
  let reader=closed_values_number_contract_scratch_layout()
  assert_eq(reader.record_headers-2L*maps.record_headers,34L)
  assert_eq(reader.reference_slots-2L*maps.reference_slots,39L)
  assert_eq(reader.scalar_words-2L*maps.scalar_words,43L)
  assert_eq(reader.owned_utf16_units,0L)
}

///|
test "closed Values caller scratch funds wide object key maps and backing overlap" {
  let wide=closed_values_values_caller_scratch_layout(100,99).unwrap()
  assert_eq(wide.record_headers,2759L)
  assert_eq(wide.reference_slots,6754L)
  assert_eq(wide.scalar_words,3892L)
  let narrow=closed_values_values_caller_scratch_layout(1,0).unwrap()
  assert_true(preparation_representation_cost(wide).unwrap()>preparation_representation_cost(narrow).unwrap())
  assert_true(closed_values_values_caller_scratch_layout(0,1) is None)
}

///|
test "closed Values sorting bounds smaller-partition frames rather than comparisons" {
  let one=closed_values_sort_scratch_layout(1).unwrap()
  let three=closed_values_sort_scratch_layout(3).unwrap()
  let four=closed_values_sort_scratch_layout(4).unwrap()
  assert_eq(one.record_headers,16L)
  assert_eq(three.record_headers,24L)
  assert_eq(four.record_headers,32L)
  let wide=closed_values_sort_scratch_layout(100).unwrap()
  assert_eq(wide.record_headers,64L)
  assert_eq(wide.reference_slots,96L)
  assert_eq(wide.scalar_words,198L)
  assert_true(closed_values_sort_scratch_layout(0) is None)
}

///|
test "closed Values Result projection accounts for independent schema and carrier copies" {
  let wide=closed_values_result_port_retained_layout(100).unwrap()
  assert_eq(wide.record_headers,1391L)
  assert_eq(wide.reference_slots,2863L)
  assert_eq(wide.scalar_words,1175L)
  assert_eq(wide.owned_utf16_units,0L)
  let eight=closed_values_result_port_retained_layout(8).unwrap()
  let nine=closed_values_result_port_retained_layout(9).unwrap()
  assert_eq(nine.record_headers-eight.record_headers,13L)
  assert_eq(nine.reference_slots-eight.reference_slots,54L)
  assert_eq(nine.scalar_words-eight.scalar_words,10L)
  assert_true(closed_values_result_port_retained_layout(0) is None)
}

///|
test "closed Values complete compiler phase composes original shape and failure ownership" {
  let phase=closed_values_compiler_phase_layout(100,99,21000,8,10).unwrap()
  let cost=preparation_representation_cost(phase.retained).unwrap()
  assert_true(cost>1500000L)
  assert_true(preparation_representation_cost(phase.temporary).unwrap()>0L)
  assert_true(preparation_representation_cost(phase.failure).unwrap()>0L)
  let total=closed_values_sum_layouts([phase.retained,phase.temporary,phase.failure]).unwrap()
  assert_eq(preparation_representation_cost(total),Some(cost+
    preparation_representation_cost(phase.temporary).unwrap()+
    preparation_representation_cost(phase.failure).unwrap()))
  assert_true(closed_values_compiler_phase_layout(100,99,9899,8,10) is None)
  assert_true(closed_values_compiler_phase_layout(1,1,10,1,11) is None)
  assert_true(closed_values_compiler_phase_layout(1,1,10,-1,5) is None)
  assert_true(closed_values_compiler_phase_layout(2147483647,2147483647,2147483647,8,10) is None)
  let zero : PreparationRepresentationUnits={record_headers:0L,reference_slots:0L,scalar_words:0L,owned_utf16_units:0L,owned_wire_bytes:0L}
  assert_true(closed_values_sum_layouts([{..zero,owned_wire_bytes:9223372036854775807L},{..zero,owned_wire_bytes:1L}]) is None)
}

///|
test "closed Values actual acceptance fixture dimensions have quantitative phase quotes" {
  // Independent original JSON lexical counts: 304 bytes (1x1) and 98,034
  // bytes (100x99), including object keys; both have longest token23/depth8.
  let one=closed_values_compiler_phase_layout(1,1,51,23,8).unwrap()
  assert_eq(preparation_representation_cost(one.retained),Some(15368L))
  assert_eq(preparation_representation_cost(one.temporary),Some(39620L))
  assert_eq(preparation_representation_cost(one.failure),Some(3200L))
  let wide=closed_values_compiler_phase_layout(100,99,20640,23,8).unwrap()
  assert_eq(preparation_representation_cost(wide.retained),Some(1623800L))
  assert_eq(preparation_representation_cost(wide.temporary),Some(460964L))
  assert_eq(preparation_representation_cost(wide.failure),Some(3200L))
  assert_eq(preparation_representation_cost(closed_values_sum_layouts([
    wide.retained,wide.temporary,wide.failure]).unwrap()),Some(2087964L))
}

///|
test "guarded walk reuses constructor tariff while generic unproved inventory remains" {
  let wide=closed_values_guarded_walk_storage_layout(100,99).unwrap()
  assert_eq(wide.record_headers,516L)
  assert_eq(wide.reference_slots,1525L)
  assert_eq(wide.scalar_words,516L)
  assert_eq(preparation_representation_cost(wide),Some(24584L))
  let generic=closed_values_walk_storage_layout(20640,100).unwrap()
  assert_eq(preparation_representation_cost(generic),Some(3002304L))
  assert_true(closed_values_guarded_walk_storage_layout(2147483647,0) is None)
  for f in [1,2,7,8,9,31,100] {
    for r in [0,1,2,8,99] {
      let actual=closed_values_guarded_walk_storage_layout(f,r).unwrap()
      assert_true(actual==closed_values_walk_storage_from_extents(f+r+2,Int::max(f,r),Int::max(f,3)).unwrap())
    }
  }
}
