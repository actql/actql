///|
test "Native terminal Content projects direct and encoder row limits" {
  let issues : Array[@local_host.NativeTerminalContentIssue] = [
    TerminalContentInput(RowLimit),
    TerminalContentInput(Encoding(ContentRowLimit)),
    TerminalContentEncoding(ContentRowLimit),
  ]
  for issue in issues {
    let reason : String = local_terminal_content_stop(issue) catch {
      ClientStop(message) => message
    }
    assert_eq(reason, "LocalContentRowLimit")
  }
}

///|
test "Native terminal Content preserves unrelated input refusals" {
  let issues : Array[@local_host.NativeTerminalContentIssue] = [
    TerminalContentInput(ForeignInput),
    TerminalContentInput(InputUnavailable),
    TerminalContentInput(InputOrderUnfulfilled),
  ]
  for issue in issues {
    let reason : String = local_terminal_content_stop(issue) catch {
      ClientStop(message) => message
    }
    assert_eq(reason, "LocalContentInputUnavailable")
  }
}
