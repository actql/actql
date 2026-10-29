///|
extern "js" fn native_reader_test_program() -> NativeJsonValue =
  #|() => JSON.parse('{"version":"actql/0.1","id":"native-é","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"v"}],"results":{"rows":{"from":"v","fields":["n"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}')

///|
extern "js" fn native_reader_test_without_json(run : () -> Unit) -> Unit =
  #|(run) => {
  #| const stringify = JSON.stringify, parse = JSON.parse;
  #| JSON.stringify = JSON.parse = () => {throw new Error('second whole JSON conversion')};
  #| try {run()} finally {JSON.stringify = stringify; JSON.parse = parse;}
  #|}

///|
test "actual Node captured reader enters the original Program constructor without a second whole JSON conversion" {
  let captured = native_reader_test_program()
  let original : Ref[@stage_syntax.Program?] = Ref(None)
  native_reader_test_without_json(() => {
    let input = @stage_syntax.admit_captured_program_input(
      captured,
      native_json_reader,
      @publication_host.client_standard_program_preparation_limits().checking.input,
    ).unwrap()
    let program = @stage_syntax.finish_program_input(input).unwrap()
    original.val = Some(program)
  })
  let program = original.val.unwrap()
  assert_eq(program.id, "native-é")
  assert_eq(@stage_syntax.stage_count(program), 1)
  assert_eq(@stage_syntax.export_count(program), 1)
}

///|
extern "js" fn native_reader_test_parameter_presence() -> FixedArray[
  NativeJsonValue,
] =
  #|() => [null, JSON.parse('1e999')]

///|
test "actual Node native Parameter absence distinguishes literal null from a supplied nonfinite value" {
  let values = native_reader_test_parameter_presence()
  assert_true(native_json_parameter_is_absent(values[0]))
  assert_false(native_json_parameter_is_absent(values[1]))
  let original = @local_preparation.admit_captured_local_parameters(
    values[1],
    native_json_reader,
  ).unwrap()
  assert_true(@decode.is_null(original))
}

///|
extern "js" fn native_reader_test_parameter_data() -> NativeJsonValue =
  #|() => JSON.parse('{"é":"é","nested":{"array":[1,null,true]}}')

///|
test "actual Node native Parameters preserve the existing Local key and exact String policy without serialization" {
  let captured = native_reader_test_parameter_data()
  let output : Ref[@decode.Cursor?] = Ref(None)
  native_reader_test_without_json(() => {
    output.val = Some(
      @local_preparation.admit_captured_local_parameters(
        captured, native_json_reader,
      ).unwrap(),
    )
  })
  let cursor = output.val.unwrap()
  let object = @decode.open_object(cursor).unwrap()
  assert_eq(
    @decode.text(@decode.required(object, "é").unwrap()).unwrap(),
    "é",
  )
  let textual = @local_preparation.admit_local_program_input(
    "json",
    Some("{\"é\":\"é\",\"nested\":{\"array\":[1,null,true]}}"),
  ).unwrap().1.unwrap()
  assert_eq(@decode.admission_usage(cursor), @decode.admission_usage(textual))
  assert_eq(@decode.object_field_names(cursor).unwrap(), ["é", "nested"])
  let nested = @decode.open_object(@decode.required(object, "nested").unwrap()).unwrap()
  let array = @decode.required(nested, "array").unwrap()
  assert_eq(
    @decode.finite_number(@decode.element_at(array, 0).unwrap()).unwrap(),
    1.0,
  )
  assert_true(@decode.is_null(@decode.element_at(array, 1).unwrap()))
  assert_true(@decode.boolean(@decode.element_at(array, 2).unwrap()).unwrap())
}
