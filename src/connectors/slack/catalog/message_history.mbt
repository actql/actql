///|
priv enum SlackMessageHistoryPhase {
  Ready
  Pending
  Page
  Complete
  Failed
  Closed
} derive(Eq)

///|
// A bounded Catalog protocol original. Its construction, request parameters
// and terminal state do not issue an Account use, physical observation,
// complete Source capture, custody acknowledgement or Resource capacity.
pub struct SlackMessageHistory {
  priv channel : String
  priv limits : SlackMessagePageLimits
  priv max_pages : Int
  priv mut phase : SlackMessageHistoryPhase
  priv mut pending : SlackMessageHistoryRequest?
  priv mut last_page : SlackMessagePage?
  priv seen_cursors : Map[String, Bool]
  priv seen_ids : Map[String, Bool]
}

///|
// Only this original history control issues this pending occurrence. A
// similarly shaped request/selection or equal channel String cannot consume it.
pub struct SlackMessageHistoryRequest {
  priv history : SlackMessageHistory
  priv ordinal : Int
  priv cursor : String?
  priv latest : String?
}

///|
pub fn prepare_slack_message_history(
  channel : String,
  limits : SlackMessagePageLimits,
  max_pages : Int,
) -> Result[SlackMessageHistory, SlackMessagePageIssue] {
  if max_pages <= 0 ||
    limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_rows <= 0 ||
    limits.max_cursor_bytes <= 0 ||
    limits.max_value_nodes <= 0 ||
    limits.max_value_text_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if channel.is_empty() ||
    @scalar.admit_utf8_length(channel, limits.max_value_text_bytes) is Err(_) {
    return Err(InvalidCell("channel"))
  }
  Ok({
    channel,
    limits,
    max_pages,
    phase: Ready,
    pending: None,
    last_page: None,
    seen_cursors: Map([]),
    seen_ids: Map([]),
  })
}

///|
pub fn begin_slack_message_history(
  history : SlackMessageHistory,
) -> Result[SlackMessageHistoryRequest, SlackMessagePageIssue] {
  if history.phase != Ready {
    return Err(ForeignHistoryRequest)
  }
  let request = { history, ordinal: 0, cursor: None, latest: None, }
  history.pending = Some(request)
  history.phase = Pending
  Ok(request)
}

///|
pub fn slack_message_history_request_channel(
  request : SlackMessageHistoryRequest,
) -> String {
  request.history.channel
}

///|
pub fn slack_message_history_request_ordinal(
  request : SlackMessageHistoryRequest,
) -> Int {
  request.ordinal
}

///|
pub fn slack_message_history_request_cursor(
  request : SlackMessageHistoryRequest,
) -> String? {
  request.cursor
}

///|
pub fn slack_message_history_request_latest(
  request : SlackMessageHistoryRequest,
) -> String? {
  request.latest
}

///|
pub fn slack_message_history_request_matches(
  history : SlackMessageHistory,
  request : SlackMessageHistoryRequest,
) -> Bool {
  history.phase == Pending && physical_equal(history, request.history) &&
    match history.pending { Some(original) => physical_equal(original, request); None => false }
}

///|
pub fn admit_slack_message_history_page(
  history : SlackMessageHistory,
  request : SlackMessageHistoryRequest,
  bytes : Bytes,
) -> Result[SlackMessagePage, SlackMessagePageIssue] {
  if !slack_message_history_request_matches(history, request) {
    return Err(ForeignHistoryRequest)
  }
  // Consume before decoding; malformed/partial input cannot replay an original
  // pending occurrence. Physical response/charge/Unknown custody stays outside.
  history.phase = Failed
  history.pending = None
  let page = match
    project_message_page(bytes, history.channel, history.limits, Some(request)) {
    Ok(page) => page
    Err(issue) => return Err(issue)
  }
  history.last_page = Some(page)
  for id in slack_message_page_ids(page) {
    if history.seen_ids.contains(id) {
      return Err(DuplicateMessage)
    }
    history.seen_ids[id] = true
  }
  history.phase = Page
  Ok(page)
}

///|
fn message_page_last_timestamp(page : SlackMessagePage) -> String? {
  if page.rows.is_empty() {
    return None
  }
  match page.rows[page.rows.length() - 1][2].value {
    @admitted.Text(text) => Some(text)
    _ => None
  }
}

///|
pub fn next_slack_message_history_request(
  history : SlackMessageHistory,
  page : SlackMessagePage,
) -> Result[SlackMessageHistoryRequest?, SlackMessagePageIssue] {
  guard history.phase == Page &&
    history.last_page is Some(original) &&
    physical_equal(original, page) &&
    page.history_request is Some(previous) &&
    physical_equal(previous.history, history) else {
    return Err(ForeignHistoryRequest)
  }
  history.phase = Failed
  // A retention-limited observation is valid DATA but cannot silently establish
  // complete history. The caller still owns its raw response and actual charge.
  if page.history_limited {
    return Err(HistoryUnavailable)
  }
  if page.next_cursor is None && !page.has_more {
    history.phase = Complete
    return Ok(None)
  }
  if previous.ordinal >= history.max_pages - 1 {
    return Err(BudgetExceeded)
  }
  let cursor = page.next_cursor
  let latest = match cursor {
    Some(cursor) => {
      if history.seen_cursors.contains(cursor) {
        return Err(InvalidPagination)
      }
      history.seen_cursors[cursor] = true
      previous.latest
    }
    None => {
      // Time pagination excludes the exact last token on the next request.
      // Prove strict instant progress; variable-fraction String order is wrong.
      guard message_page_last_timestamp(page) is Some(last) &&
        message_epoch_timestamp(last) is Some(last_instant) else {
        return Err(InvalidPagination)
      }
      let mut preceding = previous.latest
      for row in page.rows {
        guard row[2].value is @admitted.Text(ts) &&
          message_epoch_timestamp(ts) is Some(instant) else {
          return Err(InvalidPagination)
        }
        if preceding is Some(before) {
          guard message_epoch_timestamp(before) is Some(before_instant) &&
            @admitted.compare_timestamp_text(instant, before_instant) ==
            Some(-1) else {
            return Err(InvalidPagination)
          }
        }
        preceding = Some(ts)
      }
      if previous.latest is Some(before) {
        guard message_epoch_timestamp(before) is Some(before_instant) &&
          @admitted.compare_timestamp_text(last_instant, before_instant) ==
          Some(-1) else {
          return Err(InvalidPagination)
        }
      }
      Some(last)
    }
  }
  let request = { history, ordinal: previous.ordinal + 1, cursor, latest, }
  history.pending = Some(request)
  history.phase = Pending
  Ok(Some(request))
}

///|
pub fn close_slack_message_history(history : SlackMessageHistory) -> Unit {
  // Stop admission while retaining outstanding originals. This is not transport
  // closure, a reservation return, escaped-alias retirement or a physical ACK.
  history.phase = Closed
}
