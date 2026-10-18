///|
#export_name("slackPrepareMessageReplies")
pub fn slack_prepare_message_replies(
  page : @catalog.SlackMessagePage,
  index : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
  comparison_nodes : Int,
  comparison_depth : Int,
  comparison_text_bytes : Int,
  max_pages : Int,
  max_total_rows : Int,
  max_total_bytes : Int,
  max_work : Int,
) -> Result[@catalog.SlackMessageReplies, @catalog.SlackMessagePageIssue] {
  @catalog.prepare_slack_message_replies(page, index, {
    page: {
      max_bytes,
      max_nodes,
      max_depth,
      max_rows,
      max_cursor_bytes,
      max_value_nodes,
      max_value_text_bytes,
    },
    comparison: {
      max_nodes: comparison_nodes,
      max_depth: comparison_depth,
      max_text_bytes: comparison_text_bytes,
    },
    max_pages,
    max_total_rows,
    max_total_bytes,
    max_work,
  })
}

///|
#export_name("slackMessageRepliesMatchesOriginal")
pub fn slack_message_replies_matches_original(
  replies : @catalog.SlackMessageReplies,
  page : @catalog.SlackMessagePage,
  index : Int,
) -> Bool {
  @catalog.slack_message_replies_matches_original(replies, page, index)
}

///|
#export_name("slackBeginMessageReplies")
pub fn slack_begin_message_replies(
  replies : @catalog.SlackMessageReplies,
) -> Result[@catalog.SlackMessageRepliesRequest, @catalog.SlackMessagePageIssue] {
  @catalog.begin_slack_message_replies(replies)
}

///|
#export_name("slackMessageRepliesRequestMatches")
pub fn slack_message_replies_request_matches(
  replies : @catalog.SlackMessageReplies,
  request : @catalog.SlackMessageRepliesRequest,
) -> Bool {
  @catalog.slack_message_replies_request_matches(replies, request)
}

///|
#export_name("slackMessageRepliesRequestJson")
pub fn slack_message_replies_request_json(
  request : @catalog.SlackMessageRepliesRequest,
) -> String {
  let cursor : Json = match
    @catalog.slack_message_replies_request_cursor(request) {
    Some(value) => value.to_json()
    None => Json::null()
  }
  let oldest : Json = match
    @catalog.slack_message_replies_request_oldest(request) {
    Some(value) => value.to_json()
    None => Json::null()
  }
  (
    {
      "channel": @catalog.slack_message_replies_request_channel(request).to_json(),
      "ts": @catalog.slack_message_replies_request_ts(request).to_json(),
      "ordinal": @catalog.slack_message_replies_request_ordinal(request).to_json(),
      "cursor": cursor,
      "oldest": oldest,
    } : Json).stringify()
}

///|
#export_name("slackAdmitMessageRepliesPage")
pub fn slack_admit_message_replies_page(
  replies : @catalog.SlackMessageReplies,
  request : @catalog.SlackMessageRepliesRequest,
  bytes : Bytes,
) -> Result[@catalog.SlackMessageRepliesPage, @catalog.SlackMessagePageIssue] {
  @catalog.admit_slack_message_replies_page(replies, request, bytes)
}

///|
#export_name("slackMessageRepliesPageHasNext")
pub fn slack_message_replies_page_has_next(
  page : @catalog.SlackMessageRepliesPage,
) -> Bool {
  @catalog.slack_message_replies_page_has_next(page)
}

///|
#export_name("slackNextMessageRepliesRequest")
pub fn slack_next_message_replies_request(
  replies : @catalog.SlackMessageReplies,
  page : @catalog.SlackMessageRepliesPage,
) -> Result[@catalog.SlackMessageRepliesRequest, @catalog.SlackMessagePageIssue] {
  match @catalog.next_slack_message_replies_request(replies, page) {
    Ok(Some(request)) => Ok(request)
    Ok(None) => Err(@catalog.InvalidPagination)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("slackFinishMessageReplies")
pub fn slack_finish_message_replies(
  replies : @catalog.SlackMessageReplies,
  page : @catalog.SlackMessageRepliesPage,
) -> Result[Unit, @catalog.SlackMessagePageIssue] {
  match @catalog.next_slack_message_replies_request(replies, page) {
    Ok(None) => Ok(())
    Ok(Some(_)) => Err(@catalog.InvalidPagination)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("slackMessageRepliesPageRowCount")
pub fn slack_message_replies_page_row_count(
  page : @catalog.SlackMessageRepliesPage,
) -> Int {
  @catalog.slack_message_replies_page_row_count(page)
}

///|
#export_name("slackMessageRepliesPageRowsWire")
pub fn slack_message_replies_page_rows_wire(
  page : @catalog.SlackMessageRepliesPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.SlackMessagePageIssue] {
  @catalog.slack_message_replies_page_rows_wire(
    page, names, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("slackCloseMessageReplies")
pub fn slack_close_message_replies(
  replies : @catalog.SlackMessageReplies,
) -> Unit {
  @catalog.close_slack_message_replies(replies)
}
