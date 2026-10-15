///|
// Structural lifetime evidence for the selected first-M1 two-field contract,
// not a physical byte coefficient, normal profile or Provider authorization.
fn first_m1_answer_contract() -> @contract.Contract {
  // Model-task JSON's additional_properties flag is lowered to this existing
  // closed Object contract; it is not a Value-contract authoring field.
  @contract.object_contract(
    [
      ("reason", @contract.primitive(StringType, nullable=true)),
      ("risk", @contract.primitive(StringType, nullable=false)),
    ],
    nullable=false,
    max_fields=2,
    max_name_bytes=10,
  ).unwrap()
}

///|
fn first_m1_answer_inventory(
  admission : TypedAdmission,
  root : @decode.Cursor,
) -> (TypedObjectAdmission?, ObjectBuilder?) raise {
  // One root object, one current scalar and the next/append continuation.
  // Unexpected nested input must not select a nested construction frame.
  assert_true(admission.frames.length() <= 3)
  let mut object = None
  let mut builder = None
  for frame in admission.frames {
    match frame {
      TypedObjectInput(value, _)
      | TypedObjectFind(value, _, _, _, _, _)
      | TypedObjectNames(value, _) => object = Some(value)
      TypedObjectNext(value, output, _) => {
        object = Some(value)
        builder = Some(output)
      }
      TypedObjectAppend(output, _) => {
        if builder is Some(prior) {
          assert_true(physical_equal(prior, output))
        }
        builder = Some(output)
      }
      ReadTyped(_, _, _, _) => ()
      _ =>
        abort("the fixed object/text contract cannot construct another carrier")
    }
  }
  if object is Some(value) {
    assert_true(physical_equal(value.source, root))
    assert_true(value.children.length() <= 2)
    assert_eq(value.depth, 1)
  }
  if builder is Some(value) {
    assert_eq(value.expected, 2)
    assert_true(value.values.length() <= 2)
  }
  (object, builder)
}

///|
test "first M1 typed answer bounds frames and transfers the same output backing" {
  let contract = first_m1_answer_contract()
  for
    (input, expected, expected_text) in [
      (
        (
          #|{"risk":"low","reason":null}
        ),
        (
          #|{"reason":null,"risk":"low"}
        ),
        13,
      ),
      (
        (
          #|{"risk":"low","reason":"e\u0301\r\n"}
        ),
        (
          #|{"reason":"é\r\n","risk":"low"}
        ),
        18,
      ),
    ] {
    let root = json_steps_cursor(input)
    let admission = start_typed_admission(contract, root, {
      max_nodes: 3,
      max_depth: 1,
      max_text_bytes: expected_text,
    }).unwrap()
    let mut object = None
    let mut builder = None
    let mut completed = None
    let mut peak_frames = 0
    let mut peak_children = 0
    for _ in 0..<128 {
      let (current_object, current_builder) = first_m1_answer_inventory(
        admission, root,
      )
      peak_frames = Int::max(peak_frames, admission.frames.length())
      if current_object is Some(value) {
        if object is Some(prior) {
          assert_true(physical_equal(prior, value))
        }
        object = Some(value)
        peak_children = Int::max(peak_children, value.children.length())
      }
      if current_builder is Some(value) {
        if builder is Some(prior) {
          assert_true(physical_equal(prior, value))
        }
        builder = Some(value)
      }
      match advance_typed_admission(admission) {
        TypedAdmissionContinue => ()
        TypedAdmissionComplete(value, nodes, text) => {
          assert_eq((nodes, text), (3, expected_text))
          completed = Some(value)
          break
        }
        _ => abort("the independently authored two-field answer must complete")
      }
    }
    assert_eq((peak_frames, peak_children), (3, 2))
    let checked = completed.unwrap()
    guard checked.value is Object(fields) else { abort("typed object") }
    let original_builder = builder.unwrap()
    assert_true(physical_equal(fields.values, original_builder.values))
    assert_false(original_builder.open)
    assert_eq(object.unwrap().children.length(), 0)
    assert_true(physical_equal(checked.contract, contract))
    assert_true(
      admission.root is None &&
      admission.value is None &&
      admission.frames.is_empty() &&
      admission.terminal,
    )
    // Terminal cursor retirement does not mutate the transferred result or
    // claim physical GC, raw Store/response cleanup or a capacity settlement.
    cancel_typed_admission(admission)
    assert_eq(typed_steps_wire(checked), expected)
    assert_eq(@decode.object_length(root), Some(2))
  }
}

///|
test "first M1 typed refusal never constructs nested answers or exposes partial output" {
  let contract = first_m1_answer_contract()
  let deep = "[".repeat(32) + "0" + "]".repeat(32)
  for
    (input, expected_issue) in [
      ("[]", "type"),
      ("{}", "missing"),
      ("{\"reason\":null,\"risk\":null}", "null"),
      ("{\"reason\":null,\"risk\":false}", "type"),
      // The existing container-depth check precedes scalar-kind admission.
      ("{\"reason\":null,\"risk\":" + deep + "}", "depth"),
      (
        "{\"reason\":null,\"risk\":\"low\",\"unexpected\":" + deep + "}",
        "unknown",
      ),
    ] {
    let root = json_steps_cursor(input)
    let admission = start_typed_admission(contract, root, {
      max_nodes: 3,
      max_depth: 1,
      max_text_bytes: 8192,
    }).unwrap()
    let mut object = None
    let mut builder = None
    let mut failure = None
    for _ in 0..<128 {
      let (current_object, current_builder) = first_m1_answer_inventory(
        admission, root,
      )
      if current_object is Some(value) {
        object = Some(value)
      }
      if current_builder is Some(value) {
        builder = Some(value)
      }
      match advance_typed_admission(admission) {
        TypedAdmissionContinue => ()
        TypedAdmissionFailed(issue) => {
          failure = Some(issue)
          break
        }
        _ =>
          abort("malformed output must not expose a complete or partial answer")
      }
    }
    let kind = match failure.unwrap() {
      Decode({ kind: @decode.WrongType, .. }) => "type"
      Decode({ kind: @decode.MissingField, .. }) => "missing"
      Decode({ kind: @decode.UnknownField, .. }) => "unknown"
      ValueIssue(UnexpectedNull, ..) => "null"
      ValueIssue(BudgetExceeded, ..) => "depth"
      _ => abort("preserve the independent typed refusal for " + input)
    }
    assert_eq(kind, expected_issue)
    if object is Some(value) {
      assert_eq(value.children.length(), 0)
    }
    if builder is Some(value) {
      assert_false(value.open)
      assert_true(value.values.is_empty())
    }
    assert_true(
      admission.root is None &&
      admission.value is None &&
      admission.frames.is_empty() &&
      admission.terminal,
    )
    assert_true(advance_typed_admission(admission) is TypedAdmissionTerminal)
  }
}
