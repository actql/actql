///|
test "short COMMAND accepts the fixed-target operation syntax from the public contract" {
  for
    text in [
      "FROM replies |> EFFECT COMMAND gmail.send ID id INPUT (to = recipient, subject = subject, body = body);",
      "SELECT id, recipient, subject, body FROM replies |> EFFECT send_mail COMMAND gmail.send ID id INPUT (to = recipient, subject = subject, body = body);",
    ] {
    assert_true(parse_query(text, query_limits()) is Ok(_), msg=text)
  }
}

///|
test "short COMMAND accepts per-row targets and optional empty input" {
  for
    text in [
      "FROM requests AS r |> EFFECT COMMAND slack.reply TARGET r.channel ID r.id INPUT (thread_ts = r.thread, text = r.text);",
      "FROM requests |> EFFECT archive COMMAND slack.archive_channel TARGET channel ID id;",
      "FROM requests |> EFFECT archive COMMAND slack.archive_channel TARGET channel ID id INPUT ();",
    ] {
    assert_true(parse_query(text, query_limits()) is Ok(_), msg=text)
  }
}

///|
test "short COMMAND remains terminal and outside producer bodies" {
  for
    text in [
      "FROM replies |> EFFECT COMMAND gmail.send ID id |> SELECT id;", "WITH r AS (FROM replies |> EFFECT COMMAND gmail.send ID id) FROM r;",
      "FROM replies |> EFFECT COMMAND gmail.send ID id |> EFFECT STORE archive.objects;",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}

///|
test "short COMMAND rejects absent row identities and malformed input assignments" {
  for
    text in [
      "FROM replies |> EFFECT COMMAND gmail.send;", "FROM replies |> EFFECT COMMAND gmail.send INPUT (body = body);",
      "FROM replies |> EFFECT COMMAND gmail.send ID id INPUT (body = body, BODY = body);",
      "FROM replies |> EFFECT COMMAND gmail.send ID id INPUT (body = body,);", "FROM replies |> EFFECT COMMAND gmail.send TARGET ID id;",
    ] {
    assert_true(parse_query(text, query_limits()) is Err(_), msg=text)
  }
}
