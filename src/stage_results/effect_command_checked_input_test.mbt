///|
fn checked_command_fixture() -> (
  EffectCommandInputBinding,
  @value.CheckedValue,
  @value.CheckedValue,
) {
  let inputs = command_row_binding(
    (
      #|{"z":{"literal":false},"a":{"field":"amount"}}
    ),
    (
      #|{"a":{"nullable":true,"type":"number"},"z":{"nullable":false,"type":"boolean"}}
    ),
  )
  let binding = effect_command_input_at(inputs, 0).unwrap()
  guard effect_command_input_field_value(
      effect_command_input_field_at(binding, 0).unwrap(),
    )
    is ResultField(source) else {
    abort("original Result field")
  }
  guard effect_command_input_field_value(
      effect_command_input_field_at(binding, 1).unwrap(),
    )
    is Literal(literal) else {
    abort("original literal")
  }
  (
    binding,
    @value.checked_null_value(@schema.field_contract(source)).unwrap(),
    literal,
  )
}

///|
fn checked_command_wire(
  input : EffectCommandCheckedInput,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(1024, 100, 10)
  @value.emit_checked_wire_value(
    effect_command_checked_input_value(input),
    writer,
  )
  @encode.finish(writer)
}

///|
test "checked Command input retains exact typed Result and literal children" {
  let (binding, source, literal) = checked_command_fixture()
  let calls = Ref(0)
  let valid_arguments = Ref(true)
  let input = project_effect_command_checked_input(
    binding,
    7,
    fn(name, work, limits) {
      calls.val += 1
      if name != "amount" ||
        work <= 0 ||
        limits.max_depth != 3 ||
        limits.max_nodes != 19 ||
        limits.max_text_bytes != 98 {
        valid_arguments.val = false
      }
      Some((source, 1, 1, 0))
    },
    2,
    10000,
    { max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
  ).unwrap()
  assert_true(valid_arguments.val)
  assert_eq(calls.val, 1)
  assert_true(physical_equal(input.binding, binding))
  assert_eq(input.source_row_index, 7)
  assert_eq(effect_command_checked_input_field_count(input), 2)
  let (name, actual) = effect_command_checked_input_field_at(input, 0).unwrap()
  assert_eq(name, "a")
  assert_true(physical_equal(actual, source))
  assert_true(
    physical_equal(
      effect_command_checked_input_field_at(input, 1).unwrap().1,
      literal,
    ),
  )
  assert_true(effect_command_checked_input_field_at(input, 2) is None)
  assert_eq(checked_command_wire(input), "{\"a\":null,\"z\":false}")
}

///|
test "checked Command input refuses foreign contracts and invalid reader usage" {
  let (binding, source, _) = checked_command_fixture()
  let foreign = @value.checked_null_value(
    @contract.primitive(NumberType, nullable=true),
  ).unwrap()
  assert_true(
    project_effect_command_checked_input(
      binding,
      0,
      (_, _, _) => Some((foreign, 1, 1, 0)),
      2,
      10000,
      { max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
    )
    is Err(ForeignSourceContract("amount")),
  )
  for (work, nodes, text) in [(0, 1, 0), (1, 0, 0), (2, 1, -1), (3, 2, 0)] {
    assert_true(
      project_effect_command_checked_input(
        binding,
        0,
        (_, _, _) => Some((source, work, nodes, text)),
        2,
        10000,
        { max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      )
      is Err(InvalidReadUsage),
    )
  }
  assert_true(
    project_effect_command_checked_input(
      binding,
      0,
      (_, _, _) => None,
      2,
      10000,
      { max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
    )
    is Err(MissingSourceField("amount")),
  )
}

///|
test "checked Command input preserves optional omission explicit NULL and empty input" {
  let fields =
    #|{"name":{"nullable":false,"type":"string"},"overwrite":{"nullable":true,"type":"boolean"}}
  for
    (authored, expected) in [
      ("{\"name\":{\"literal\":\"n\"}}", "{\"name\":\"n\"}"),
      (
        "{\"name\":{\"literal\":\"n\"},\"overwrite\":{\"literal\":null}}", "{\"name\":\"n\",\"overwrite\":null}",
      ),
      ("{}", "{}"),
    ] {
    let inputs = bind_effect_command_inputs(
      presence_targets(authored, fields~, required="[]"),
      presence_limits(),
    ).unwrap()
    let calls = Ref(0)
    let input = project_effect_command_checked_input(
      effect_command_input_at(inputs, 0).unwrap(),
      0,
      fn(_, _, _) {
        calls.val += 1
        None
      },
      2,
      10000,
      { max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
    ).unwrap()
    assert_eq(calls.val, 0)
    assert_eq(checked_command_wire(input), expected)
  }
}

///|
test "checked Command input bounds complete composite work nodes text and depth" {
  let (binding, source, _) = checked_command_fixture()
  let calls = Ref(0)
  let read = fn(_ : String, _ : Int, _ : @value.Limits) {
    calls.val += 1
    Some((source, 1, 1, 0))
  }
  assert_true(
    project_effect_command_checked_input(binding, 0, read, 1, 10000, {
      max_nodes: 20,
      max_depth: 4,
      max_text_bytes: 100,
    })
    is Err(FieldLimit),
  )
  assert_true(
    project_effect_command_checked_input(binding, 0, read, 2, 0, {
      max_nodes: 20,
      max_depth: 4,
      max_text_bytes: 100,
    })
    is Err(WorkLimit),
  )
  assert_eq(calls.val, 0)
  assert_true(
    project_effect_command_checked_input(binding, 0, read, 2, 10000, {
      max_nodes: 2,
      max_depth: 4,
      max_text_bytes: 100,
    })
    is Err(ValueLimit),
  )
  assert_true(
    project_effect_command_checked_input(binding, 0, read, 2, 10000, {
      max_nodes: 3,
      max_depth: 4,
      max_text_bytes: 1,
    })
    is Err(ValueLimit),
  )
  let nested = command_row_binding(
    (
      #|{"z":{"literal":[false]}}
    ),
    (
      #|{"z":{"items":{"nullable":false,"type":"boolean"},"nullable":false,"type":"array"}}
    ),
  )
  assert_true(
    project_effect_command_checked_input(
      effect_command_input_at(nested, 0).unwrap(),
      0,
      read,
      1,
      10000,
      { max_nodes: 10, max_depth: 1, max_text_bytes: 10, },
    )
    is Err(ValueLimit),
  )
  let exact = project_effect_command_checked_input(binding, 0, read, 2, 10000, {
    max_nodes: 3,
    max_depth: 1,
    max_text_bytes: 2,
  }).unwrap()
  assert_eq(checked_command_wire(exact), "{\"a\":null,\"z\":false}")
}
