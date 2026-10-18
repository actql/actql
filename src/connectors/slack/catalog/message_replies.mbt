///|
pub(all) struct SlackMessageRepliesLimits {
  page : SlackMessagePageLimits
  comparison : @admitted.Limits
  max_pages : Int
  max_total_rows : Int
  max_total_bytes : Int
  max_work : Int
}

///|
// This protocol selection retains an actual admitted history page and row. It
// is not a Site original, operation grant, complete Source or physical ACK.
pub struct SlackMessageReplies {
  priv source_page : SlackMessagePage
  priv source_index : Int
  priv source_ts : String
  priv channel : String
  priv target_ts : String
  priv limits : SlackMessageRepliesLimits
  priv mut phase : SlackMessageHistoryPhase
  priv mut pending : SlackMessageRepliesRequest?
  priv pages : Array[SlackMessageRepliesPage]
  priv seen_cursors : Map[String, Bool]
  priv seen_rows : Map[String, Array[@admitted.CheckedValue]]
  priv mut root_ts : String?
  priv mut source_seen : Bool
  priv mut parent_seen : Bool
  priv mut bytes : Int
  priv mut work : Int
}

///|
pub struct SlackMessageRepliesRequest {
  priv replies : SlackMessageReplies
  priv ordinal : Int
  priv cursor : String?
  priv oldest : String?
}

///|
pub struct SlackMessageRepliesPage {
  priv request : SlackMessageRepliesRequest
  priv original : SlackMessagePage
  priv rows : Array[Array[@admitted.CheckedValue]]
}

///|
pub fn prepare_slack_message_replies(
  source_page : SlackMessagePage,
  source_index : Int,
  limits : SlackMessageRepliesLimits,
) -> Result[SlackMessageReplies, SlackMessagePageIssue] {
  let page = limits.page
  if limits.max_pages <= 0 ||
    limits.max_total_rows <= 0 ||
    limits.max_total_bytes <= 0 ||
    limits.max_work <= 0 ||
    limits.comparison.max_nodes <= 0 ||
    limits.comparison.max_depth <= 0 ||
    limits.comparison.max_text_bytes <= 0 ||
    page.max_bytes <= 0 ||
    page.max_nodes <= 0 ||
    page.max_depth <= 0 ||
    page.max_rows <= 0 ||
    page.max_cursor_bytes <= 0 ||
    page.max_value_nodes <= 0 ||
    page.max_value_text_bytes <= 0 {
    return Err(InvalidLimits)
  }
  guard source_page.history_request is Some(source) &&
    source_index >= 0 &&
    source_index < source_page.rows.length() else {
    return Err(InvalidSelection("original history row"))
  }
  let row = source_page.rows[source_index]
  guard row[2].value is @admitted.Text(source_ts) else {
    return Err(InvalidCell("ts"))
  }
  let root_ts = match row[5].value {
    @admitted.Text(thread) => Some(thread)
    _ => None
  }
  let target_ts = match root_ts {
    Some(value) => value
    None => source_ts
  }
  Ok({
    source_page,
    source_index,
    source_ts,
    channel: source.history.channel,
    target_ts,
    limits,
    phase: Ready,
    pending: None,
    pages: [],
    seen_cursors: Map([]),
    seen_rows: Map([]),
    root_ts,
    source_seen: false,
    parent_seen: false,
    bytes: 0,
    work: limits.max_work,
  })
}

///|
pub fn slack_message_replies_matches_original(
  replies : SlackMessageReplies,
  source_page : SlackMessagePage,
  source_index : Int,
) -> Bool {
  physical_equal(replies.source_page, source_page) &&
  replies.source_index == source_index
}

///|
pub fn begin_slack_message_replies(
  replies : SlackMessageReplies,
) -> Result[SlackMessageRepliesRequest, SlackMessagePageIssue] {
  if replies.phase != Ready {
    return Err(ForeignRepliesRequest)
  }
  let request = { replies, ordinal: 0, cursor: None, oldest: None, }
  replies.pending = Some(request)
  replies.phase = Pending
  Ok(request)
}

///|
pub fn slack_message_replies_request_channel(
  request : SlackMessageRepliesRequest,
) -> String {
  request.replies.channel
}

///|
pub fn slack_message_replies_request_ts(
  request : SlackMessageRepliesRequest,
) -> String {
  request.replies.target_ts
}

///|
pub fn slack_message_replies_request_ordinal(
  request : SlackMessageRepliesRequest,
) -> Int {
  request.ordinal
}

///|
pub fn slack_message_replies_request_cursor(
  request : SlackMessageRepliesRequest,
) -> String? {
  request.cursor
}

///|
pub fn slack_message_replies_request_oldest(
  request : SlackMessageRepliesRequest,
) -> String? {
  request.oldest
}

///|
pub fn slack_message_replies_request_matches(
  replies : SlackMessageReplies,
  request : SlackMessageRepliesRequest,
) -> Bool {
  if replies.phase != Pending || !physical_equal(request.replies, replies) {
    return false
  }
  match replies.pending {
    Some(original) => physical_equal(original, request)
    None => false
  }
}

///|
fn replies_spend(replies : SlackMessageReplies, work : Int) -> Bool {
  if work < 0 || work > replies.work {
    return false
  }
  replies.work -= work
  true
}

///|
fn replies_row_equal(
  replies : SlackMessageReplies,
  left : Array[@admitted.CheckedValue],
  right : Array[@admitted.CheckedValue],
) -> Result[Bool, SlackMessagePageIssue] {
  if left.length() != right.length() {
    return Ok(false)
  }
  for index in 0..<left.length() {
    if !replies_spend(replies, 1) {
      return Err(BudgetExceeded)
    }
    let equality = match
      @admitted.start_complete_equality(
        left[index],
        right[index],
        replies.limits.comparison,
      ) {
      Ok(value) => value
      Err(_) => return Err(BudgetExceeded)
    }
    while true {
      if replies.work <= 0 {
        @admitted.cancel_complete_equality(equality)
        return Err(BudgetExceeded)
      }
      match @admitted.advance_complete_equality(equality, 1) {
        EqualityContinue(work~) =>
          if !replies_spend(replies, work) {
            @admitted.cancel_complete_equality(equality)
            return Err(BudgetExceeded)
          }
        EqualityComplete(equal~, work~) => {
          if !replies_spend(replies, work) {
            return Err(BudgetExceeded)
          }
          if !equal {
            return Ok(false)
          }
          break
        }
        EqualityFailed(_, work=_) => return Err(BudgetExceeded)
      }
    }
  }
  Ok(true)
}

///|
pub fn admit_slack_message_replies_page(
  replies : SlackMessageReplies,
  request : SlackMessageRepliesRequest,
  bytes : Bytes,
) -> Result[SlackMessageRepliesPage, SlackMessagePageIssue] {
  if !slack_message_replies_request_matches(replies, request) {
    return Err(ForeignRepliesRequest)
  }
  replies.phase = Failed
  replies.pending = None
  if bytes.length() > replies.limits.max_total_bytes - replies.bytes ||
    !replies_spend(replies, bytes.length()) {
    return Err(BudgetExceeded)
  }
  replies.bytes += bytes.length()
  let original = match
    project_slack_message_page(bytes, replies.channel, replies.limits.page) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let rows = []
  for row in original.rows {
    guard row[0].value is @admitted.Text(id) &&
      row[2].value is @admitted.Text(ts) else {
      return Err(InvalidCell("ts"))
    }
    if !replies_spend(replies, id.length()) ||
      !replies_spend(replies, ts.length()) ||
      !replies_spend(replies, 1) {
      return Err(BudgetExceeded)
    }
    if replies.root_ts is None {
      replies.root_ts = match row[5].value {
        @admitted.Text(root) => Some(root)
        _ => Some(ts)
      }
    }
    let root = replies.root_ts.unwrap()
    if !replies_spend(replies, root.length()) {
      return Err(BudgetExceeded)
    }
    if ts == root {
      match row[5].value {
        @admitted.Text(thread) =>
          if thread != root {
            return Err(InconsistentThread)
          }
        @admitted.Null => ()
        _ => return Err(InconsistentThread)
      }
      replies.parent_seen = true
    } else {
      guard row[5].value is @admitted.Text(thread) && thread == root else {
        return Err(InconsistentThread)
      }
    }
    if ts == replies.source_ts {
      replies.source_seen = true
    }
    match replies.seen_rows.get(id) {
      Some(previous) =>
        match replies_row_equal(replies, previous, row) {
          Ok(true) => ()
          Ok(false) => return Err(InconsistentThread)
          Err(issue) => return Err(issue)
        }
      None => {
        if replies.seen_rows.length() >= replies.limits.max_total_rows {
          return Err(BudgetExceeded)
        }
        replies.seen_rows[id] = row
        rows.push(row)
      }
    }
  }
  let page = { request, original, rows, }
  replies.pages.push(page)
  replies.phase = Page
  Ok(page)
}

///|
pub fn next_slack_message_replies_request(
  replies : SlackMessageReplies,
  page : SlackMessageRepliesPage,
) -> Result[SlackMessageRepliesRequest?, SlackMessagePageIssue] {
  guard replies.phase == Page &&
    replies.pages.last() is Some(original) &&
    physical_equal(original, page) &&
    physical_equal(page.request.replies, replies) else {
    return Err(ForeignRepliesRequest)
  }
  replies.phase = Failed
  if page.original.history_limited {
    return Err(HistoryUnavailable)
  }
  if page.original.next_cursor is None && !page.original.has_more {
    if !replies.parent_seen || !replies.source_seen {
      return Err(InconsistentThread)
    }
    replies.phase = Complete
    return Ok(None)
  }
  let previous = page.request
  if previous.ordinal >= replies.limits.max_pages - 1 {
    return Err(BudgetExceeded)
  }
  let cursor = page.original.next_cursor
  let oldest = match cursor {
    Some(value) => {
      if !replies_spend(replies, value.length()) || !replies_spend(replies, 1) {
        return Err(BudgetExceeded)
      }
      if replies.seen_cursors.contains(value) {
        return Err(InvalidPagination)
      }
      replies.seen_cursors[value] = true
      previous.oldest
    }
    None => {
      // Replies are ascending. Advance the documented exclusive lower bound,
      // preserving the exact token rather than ordering mixed-fraction text.
      if page.rows.is_empty() {
        return Err(InvalidPagination)
      }
      let mut preceding = previous.oldest
      for row in page.rows {
        guard row[2].value is @admitted.Text(ts) &&
          message_epoch_timestamp(ts) is Some(instant) else {
          return Err(InvalidPagination)
        }
        if !replies_spend(replies, ts.length()) || !replies_spend(replies, 1) {
          return Err(BudgetExceeded)
        }
        if preceding is Some(before) {
          guard message_epoch_timestamp(before) is Some(before_instant) &&
            @admitted.compare_timestamp_text(instant, before_instant) == Some(1) else {
            return Err(InvalidPagination)
          }
        }
        preceding = Some(ts)
      }
      preceding
    }
  }
  let request = { replies, ordinal: previous.ordinal + 1, cursor, oldest, }
  replies.pending = Some(request)
  replies.phase = Pending
  Ok(Some(request))
}

///|
pub fn slack_message_replies_page_row_count(
  page : SlackMessageRepliesPage,
) -> Int {
  page.rows.length()
}

///|
pub fn slack_message_replies_page_has_next(
  page : SlackMessageRepliesPage,
) -> Bool {
  page.original.next_cursor is Some(_) || page.original.has_more
}

///|
pub fn slack_message_replies_page_rows_wire(
  page : SlackMessageRepliesPage,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, SlackMessagePageIssue] {
  message_rows_wire(page.rows, names, max_bytes, max_nodes, max_depth)
}

///|
pub fn slack_message_replies_page_response_sha256(
  page : SlackMessageRepliesPage,
) -> String {
  page.original.response_sha256
}

///|
pub fn slack_message_replies_retained_page_count(
  replies : SlackMessageReplies,
) -> Int {
  replies.pages.length()
}

///|
pub fn close_slack_message_replies(replies : SlackMessageReplies) -> Unit {
  // Keep original history/response/request/row aliases; closing this protocol
  // neither closes transport nor retires escaped references or returns a loan.
  replies.phase = Closed
}
