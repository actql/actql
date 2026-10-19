///|
#export_name("slackPrepareMessageHistory")
pub fn slack_prepare_message_history(
  channel : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
  max_pages : Int,
) -> Result[@catalog.SlackMessageHistory, @catalog.SlackMessagePageIssue] {
  @catalog.prepare_slack_message_history(
    channel,
    {
      max_bytes,
      max_nodes,
      max_depth,
      max_rows,
      max_cursor_bytes,
      max_value_nodes,
      max_value_text_bytes,
    },
    max_pages,
  )
}

///|
#export_name("slackPrepareMessageHistoryWindow")
pub fn slack_prepare_message_history_window(
  channel : String,
  oldest : String?,
  latest : String?,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_cursor_bytes : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
  max_pages : Int,
) -> Result[@catalog.SlackMessageHistory, @catalog.SlackMessagePageIssue] {
  @catalog.prepare_slack_message_history_window(
    channel,
    oldest,
    latest,
    {
      max_bytes,
      max_nodes,
      max_depth,
      max_rows,
      max_cursor_bytes,
      max_value_nodes,
      max_value_text_bytes,
    },
    max_pages,
  )
}

///|
#export_name("slackBeginMessageHistory")
pub fn slack_begin_message_history(
  history : @catalog.SlackMessageHistory,
) -> Result[@catalog.SlackMessageHistoryRequest, @catalog.SlackMessagePageIssue] {
  @catalog.begin_slack_message_history(history)
}

///|
#export_name("slackMessageHistoryRequestJson")
pub fn slack_message_history_request_json(
  request : @catalog.SlackMessageHistoryRequest,
) -> String {
  let cursor : Json = match
    @catalog.slack_message_history_request_cursor(request) {
    Some(value) => value.to_json()
    None => Json::null()
  }
  let latest : Json = match
    @catalog.slack_message_history_request_latest(request) {
    Some(value) => value.to_json()
    None => Json::null()
  }
  let value : Json = {
    "channel": @catalog.slack_message_history_request_channel(request).to_json(),
    "ordinal": @catalog.slack_message_history_request_ordinal(request).to_json(),
    "cursor": cursor,
    "latest": latest,
  }
  // An absent lower bound keeps the legacy private request bytes unchanged.
  if @catalog.slack_message_history_request_oldest(request) is Some(oldest) &&
    value is Object(fields) {
    fields["oldest"] = oldest.to_json()
  }
  value.stringify()
}

///|
#export_name("slackMessageHistoryRequestMatches")
pub fn slack_message_history_request_matches(
  history : @catalog.SlackMessageHistory,
  request : @catalog.SlackMessageHistoryRequest,
) -> Bool {
  @catalog.slack_message_history_request_matches(history, request)
}

///|
#export_name("slackAdmitMessageHistoryPage")
pub fn slack_admit_message_history_page(
  history : @catalog.SlackMessageHistory,
  request : @catalog.SlackMessageHistoryRequest,
  bytes : Bytes,
) -> Result[@catalog.SlackMessagePage, @catalog.SlackMessagePageIssue] {
  @catalog.admit_slack_message_history_page(history, request, bytes)
}

///|
#export_name("slackMessageHistoryPageHasNext")
pub fn slack_message_history_page_has_next(
  page : @catalog.SlackMessagePage,
) -> Bool {
  page.next_cursor is Some(_) || page.has_more
}

///|
#export_name("slackNextMessageHistoryRequest")
pub fn slack_next_message_history_request(
  history : @catalog.SlackMessageHistory,
  page : @catalog.SlackMessagePage,
) -> Result[@catalog.SlackMessageHistoryRequest, @catalog.SlackMessagePageIssue] {
  match @catalog.next_slack_message_history_request(history, page) {
    Ok(Some(request)) => Ok(request)
    Ok(None) => Err(@catalog.InvalidPagination)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("slackFinishMessageHistory")
pub fn slack_finish_message_history(
  history : @catalog.SlackMessageHistory,
  page : @catalog.SlackMessagePage,
) -> Result[Unit, @catalog.SlackMessagePageIssue] {
  match @catalog.next_slack_message_history_request(history, page) {
    Ok(None) => Ok(())
    Ok(Some(_)) => Err(@catalog.InvalidPagination)
    Err(issue) => Err(issue)
  }
}

///|
#export_name("slackCloseMessageHistory")
pub fn slack_close_message_history(
  history : @catalog.SlackMessageHistory,
) -> Unit {
  @catalog.close_slack_message_history(history)
}

///|
#export_name("slackMessagePageRowCount")
pub fn slack_message_page_row_count(page : @catalog.SlackMessagePage) -> Int {
  @catalog.slack_message_page_row_count(page)
}

///|
#export_name("slackMessagePageRowsWire")
pub fn slack_message_page_rows_wire(
  page : @catalog.SlackMessagePage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.SlackMessagePageIssue] {
  @catalog.slack_message_page_rows_wire(
    page, names, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("slackMessageColumnNames")
pub fn slack_message_column_names() -> Array[String] {
  @catalog.slack_message_column_names()
}

///|
#export_name("slackMessageSchemaWire")
pub fn slack_message_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.SlackMessagePageIssue] {
  @catalog.slack_message_schema_wire(max_bytes, max_nodes, max_depth)
}
