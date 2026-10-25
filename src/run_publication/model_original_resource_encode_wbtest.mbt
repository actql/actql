///|
fn original_resource_encode_parts() -> (String, String, String) {
  // Extract DATA from the already independent complete artifact. Expected
  // whole bytes and hashes remain its handwritten vector, not encoder output.
  let value = parse_contract_wire(
    original_resource_document_vector(),
    10000,
    1000,
    16,
    data_keys=true,
  ).unwrap()
  (
    @json.stringify_value(
      @json.object_field(value, "origin").unwrap(),
      10000,
      1000,
      16,
    ) catch {
      _ => abort("fixture origin")
    },
    @json.stringify_value(
      @json.object_field(value, "resource_state").unwrap(),
      10000,
      1000,
      16,
    ) catch {
      _ => abort("fixture state")
    },
    "null",
  )
}

///|
test "original resource encoder retains independent complete bytes and exact limit" {
  let (origin, state, cut) = original_resource_encode_parts()
  let wire = encode_model_original_resource_document(
    origin, state, cut, "preparation_base", 1713, 200, 16,
  ).unwrap()
  assert_eq(wire, original_resource_document_vector())
  assert_eq(
    @sha.hex(@utf8.encode(wire)),
    "0c15b2030233db5aafb6ee124784d0e4e414ff8500ac9dc8ad5ee74b3b25a7cd",
  )
  assert_true(
    encode_model_original_resource_document(
      origin, state, cut, "preparation_base", 1712, 200, 16,
    )
    is Err(_),
  )
  for
    (bytes, nodes, depth) in [
      (0, 200, 16),
      (1713, 0, 16),
      (1713, 200, 0),
      (1713, 1, 16),
      (1713, 200, 1),
    ] {
    assert_true(
      encode_model_original_resource_document(
        origin, state, cut, "preparation_base", bytes, nodes, depth,
      )
      is Err(_),
    )
  }
}

///|
test "original resource encoder refuses rewritten Writer bytes and closed-shape violations" {
  let (origin, state, cut) = original_resource_encode_parts()
  for
    changed in [
      " " + state,
      state.replace(old="\"-3\"", new="\"-03\""),
      state.replace(old="\"17\",\"2\"", new="17,\"2\""),
    ] {
    assert_true(
      encode_model_original_resource_document(
        origin, changed, cut, "preparation_base", 10000, 1000, 16,
      )
      is Err(_),
    )
  }
  let extra_origin = origin.replace(old="{", new="{\"extra\":null,")
  assert_true(
    encode_model_original_resource_document(
      extra_origin, state, cut, "preparation_base", 10000, 1000, 16,
    )
    is Err(_),
  )
  assert_true(
    encode_model_original_resource_document(
      origin, state, "{}", "preparation_base", 10000, 1000, 16,
    )
    is Err(_),
  )
  assert_true(
    encode_model_original_resource_document(
      origin, state, cut, "parked", 10000, 1000, 16,
    )
    is Err(_),
  )
}

///|
test "original resource encoder preserves data strings without granting current origin" {
  let (origin, state, cut) = original_resource_encode_parts()
  let composed = origin.replace(old="original-é", new="original-é")
  let wire = encode_model_original_resource_document(
    composed, state, cut, "preparation_base", 10000, 1000, 16,
  ).unwrap()
  assert_eq(
    wire,
    original_resource_document_vector().replace(
      old="original-é",
      new="original-é",
    ),
  )
  let document = read_model_original_resource_document(wire, 10000, 1000, 16).unwrap()
  assert_eq(
    model_original_resource_origin_field(document, "run_id"),
    Some("original-é\r\n"),
  )
  // DATA admission accepts another syntactically valid origin. The existing
  // checked Run/Resource/actual Store guards, not this encoder, reject it.
  let foreign = origin.replace(old="original-é", new="foreign")
  assert_true(
    encode_model_original_resource_document(
      foreign, state, cut, "preparation_base", 10000, 1000, 16,
    )
    is Ok(_),
  )
}
