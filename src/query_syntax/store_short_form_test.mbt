///|
test "public STORE forms parse as authored terminal declarations" {
  for
    text in [
      "FROM local.orders |> EFFECT STORE local.archive;", "FROM transfers |> EFFECT STORE local.files SET (path = name, content = content);",
      "FROM transfers |> EFFECT upload STORE gcs.objects SET (name = name, content = content, overwrite = TRUE);",
    ] {
    let result = parse_query_script(text, query_limits())
    match result {
      Ok(_) => ()
      Err(issue) => {
        debug_inspect(issue, content="adopted STORE source must parse")
        fail("STORE source was refused before published-contract resolution")
      }
    }
  }
}

///|
test "original explicit typed COMMAND remains a parser control" {
  assert_true(
    parse_query_script(
      "FROM transfers |> RESULT files; EFFECT upload COMMAND FROM RESULT files AS t TARGET t.destination CONTRACT `command:files.upload.v1` INPUT (name = t.name, content = t.content);",
      query_limits(),
    )
    is Ok(_),
  )
}
