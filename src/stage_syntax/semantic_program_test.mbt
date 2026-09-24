///|
fn stripped(text : String) -> String raise {
  let document = parsed(text, format=Json)
  let out = @encode.writer(10000, 1000, 30)
  emit_metadata_stripped_program(document, out)
  @encode.finish(out)
}

///|
test "Plan Program removes annotations without removing business meta fields" {
  let source =
    #|{"version":"actql/0.1","id":"p","meta":{"note":"root"},"stages":[{"id":"s","meta":{"note":"stage"},"inputs":{},"steps":[{"values":{"schema":{"meta":{"type":"string","nullable":false}},"rows":[{"meta":"business"}]},"as":"rows","meta":{"note":"step"}}],"results":{"r":{"from":"rows","meta":{"note":"result"}}}}],"results":{"out":{"from":{"stage":"s","result":"r"}}}}
  let expected =
    #|{"id":"p","results":{"out":{"from":{"result":"r","stage":"s"}}},"stages":[{"id":"s","inputs":{},"results":{"r":{"from":"rows"}},"steps":[{"as":"rows","values":{"rows":[{"meta":"business"}],"schema":{"meta":{"nullable":false,"type":"string"}}}}]}],"version":"actql/0.1"}
  assert_eq(stripped(source), expected)
  assert_eq(
    stripped(
      source.replace(old="\"note\":\"root\"", new="\"note\":\"changed\""),
    ),
    expected,
  )
  assert_true(
    stripped(source.replace(old="business", new="changed")) != expected,
  )
  let document = parsed(source, format=Json)
  let out = @encode.writer(expected.length() - 1, 1000, 30)
  assert_true(
    try {
      emit_metadata_stripped_program(document, out)
      let _ = @encode.finish(out)
      false
    } catch {
      @encode.OutputLimit => true
      _ => false
    },
  )
}
