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
