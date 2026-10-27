///|
// Count the actual private production builder chosen at each typed append.
// This is a route/full generic append count, not an NFC, UTF8 or CPU count.
fn finish_contract_builder_path(
  admission : TypedAdmission,
) -> (Result[(CheckedValue, Int, Int), Issue], Int, Int) {
  let mut generic = 0
  let mut original_contract = 0
  for _ in 0..<10000 {
    if admission.frames.last() is Some(TypedObjectAppend(builder, _)) {
      if builder.contract_fields is Some(_) {
        original_contract += 1
      } else {
        generic += 1
      }
    }
    match advance_typed_admission(admission) {
      TypedAdmissionContinue => ()
      TypedAdmissionComplete(value, nodes, text) =>
        return (Ok((value, nodes, text)), generic, original_contract)
      TypedAdmissionFailed(issue) =>
        return (Err(issue), generic, original_contract)
      TypedAdmissionTerminal => abort("premature typed builder termination")
    }
  }
  cancel_typed_admission(admission)
  abort("typed builder route did not finish")
}

///|
test "typed default object uses original Contract builder without generic name readmission" {
  let contract = typed_steps_contract(
    (
      #|{"type":"object","nullable":false,"fields":{"a":{"type":"number","nullable":false},"child":{"type":"object","nullable":false,"fields":{"b":{"type":"boolean","nullable":false}}}}}
    ),
  )
  let source = json_steps_cursor("{\"child\":{\"b\":true},\"a\":1}")
  let original = start_typed_admission(contract, source, {
    max_nodes: 4,
    max_depth: 2,
    max_text_bytes: 7,
  }).unwrap()
  let (outcome, generic, closed) = finish_contract_builder_path(original)
  let (checked, nodes, text) = outcome.unwrap()
  assert_eq(typed_steps_wire(checked), "{\"a\":1,\"child\":{\"b\":true}}")
  assert_eq((nodes, text), (4, 7))
  assert_true(physical_equal(checked.contract, contract))
  assert_eq(generic + closed, 3)
  assert_eq(generic, 0)
  assert_eq(closed, 3)
}

///|
test "typed Unicode Object retains exact original Contract fields across output and cancel" {
  let contract = typed_steps_contract(
    (
      #|{"type":"object","nullable":false,"fields":{"é":{"type":"number","nullable":false},"雪":{"type":"string","nullable":false}}}
    ),
  )
  guard contract.shape is @contract.Object(original_fields) else {
    abort("object contract")
  }
  let source = json_steps_cursor("{\"雪\":\"ok\",\"é\":1}")
  let admission = start_typed_admission(contract, source, {
    max_nodes: 3,
    max_depth: 1,
    max_text_bytes: 7,
  }).unwrap()
  let mut seen = false
  let mut completed : CheckedValue? = None
  for _ in 0..<128 {
    for frame in admission.frames {
      if frame is TypedObjectNext(object, builder, _) {
        assert_true(physical_equal(object.contract, contract))
        assert_true(
          physical_equal(typed_object_fields(object), original_fields),
        )
        guard builder.contract_fields is Some(fields) else {
          abort("unbound typed builder")
        }
        assert_true(physical_equal(fields, original_fields))
        seen = true
      }
    }
    match advance_typed_admission(admission) {
      TypedAdmissionContinue => ()
      TypedAdmissionComplete(value, nodes, text) => {
        assert_eq((nodes, text), (3, 7))
        completed = Some(value)
        break
      }
      _ => abort("unexpected Unicode typed admission refusal")
    }
  }
  assert_true(seen)
  let checked = completed.unwrap()
  cancel_typed_admission(admission)
  assert_eq(typed_steps_wire(checked), "{\"é\":1,\"雪\":\"ok\"}")
  assert_true(physical_equal(checked.contract, contract))
}
