///|
priv enum GmailThreadReadPhase {
  Ready
  Pending
  Failed
  Complete
  Closed
} derive(Eq)

///|
priv enum GmailThreadRequestKind {
  List(String?)
  Get(GmailThreadListPage, Int)
}

///|
// This Connector protocol owns nominal list/get sequencing, not Account,
// Credential, RowRun tickets, currentness or physical cleanup. The original
// physical caller consumes each response charge before another exchange.
pub struct GmailThreadRead {
  priv mailbox : String
  priv list_limits : GmailThreadListLimits
  priv thread_limits : GmailThreadLimits
  priv max_pages : Int
  priv max_threads : Int
  priv mut phase : GmailThreadReadPhase
  priv mut pending : GmailThreadRequest?
  priv mut ordinal : Int
  priv mut active_page : GmailThreadListPage?
  priv mut target_index : Int
  priv mut next_token : String?
  priv pages : Array[GmailThreadListPage]
  priv threads : Array[GmailThreadProjection]
  priv seen_tokens : Map[String, Bool]
  priv seen_ids : Map[String, Bool]
}

///|
pub struct GmailThreadRequest {
  priv read : GmailThreadRead
  priv kind : GmailThreadRequestKind
  priv ordinal : Int
}

///|
pub(all) enum GmailThreadReadIssue {
  InvalidLimits
  ForeignRequest
  BudgetExceeded
  InvalidPagination
  DuplicateThread
  InvalidList(GmailThreadListIssue)
  InvalidThread(GmailThreadIssue)
} derive(Eq, Debug)

///|
pub fn prepare_gmail_thread_read(
  mailbox : String,
  list_limits : GmailThreadListLimits,
  thread_limits : GmailThreadLimits,
  max_pages : Int,
  max_threads : Int,
) -> Result[GmailThreadRead, GmailThreadReadIssue] {
  if mailbox.is_empty() ||
    max_pages <= 0 ||
    max_threads < 0 ||
    max_pages > 2147483647 - max_threads ||
    list_limits.max_bytes <= 0 ||
    list_limits.max_nodes <= 0 ||
    list_limits.max_depth <= 0 ||
    list_limits.max_rows < 0 ||
    list_limits.max_rows > 500 ||
    list_limits.max_id_bytes < 0 ||
    list_limits.max_token_bytes < 0 ||
    !gmail_thread_limits_valid(thread_limits) {
    return Err(InvalidLimits)
  }
  Ok({
    mailbox,
    list_limits,
    thread_limits,
    max_pages,
    max_threads,
    phase: Ready,
    pending: None,
    ordinal: 0,
    active_page: None,
    target_index: 0,
    next_token: None,
    pages: [],
    threads: [],
    seen_tokens: Map([]),
    seen_ids: Map([]),
  })
}

///|
pub fn next_gmail_thread_request(
  read : GmailThreadRead,
) -> Result[GmailThreadRequest?, GmailThreadReadIssue] {
  if read.phase != Ready {
    return Err(ForeignRequest)
  }
  let kind = if read.active_page is Some(page) &&
    read.target_index < gmail_thread_list_count(page) {
    Get(page, read.target_index)
  } else {
    if !read.pages.is_empty() && read.next_token is None {
      read.phase = Complete
      return Ok(None)
    }
    if read.pages.length() >= read.max_pages {
      read.phase = Failed
      return Err(BudgetExceeded)
    }
    List(read.next_token)
  }
  let request = { read, kind, ordinal: read.ordinal, }
  read.ordinal += 1
  read.pending = Some(request)
  read.phase = Pending
  Ok(Some(request))
}

///|
pub fn gmail_thread_request_matches(
  read : GmailThreadRead,
  request : GmailThreadRequest,
) -> Bool {
  if read.phase != Pending || !physical_equal(read, request.read) {
    return false
  }
  match read.pending {
    Some(original) => physical_equal(original, request)
    None => false
  }
}

///|
pub fn gmail_thread_request_mailbox(request : GmailThreadRequest) -> String {
  request.read.mailbox
}

///|
pub fn gmail_thread_request_ordinal(request : GmailThreadRequest) -> Int {
  request.ordinal
}

///|
pub fn gmail_thread_request_is_list(request : GmailThreadRequest) -> Bool {
  request.kind is List(_)
}

///|
pub fn gmail_thread_request_page_token(request : GmailThreadRequest) -> String? {
  match request.kind {
    List(token) => token
    Get(_, _) => None
  }
}

///|
pub fn gmail_thread_request_target_id(request : GmailThreadRequest) -> String? {
  match request.kind {
    List(_) => None
    Get(page, index) => gmail_thread_list_id_at(page, index)
  }
}

///|
pub fn accept_gmail_thread_list(
  read : GmailThreadRead,
  request : GmailThreadRequest,
  bytes : Bytes,
) -> Result[GmailThreadListPage, GmailThreadReadIssue] {
  guard gmail_thread_request_matches(read, request) && request.kind is List(_) else {
    return Err(ForeignRequest)
  }
  // Consume before parsing. A malformed response cannot retry this occurrence.
  read.pending = None
  read.phase = Failed
  let page = match project_gmail_thread_list(bytes, read.list_limits) {
    Ok(page) => page
    Err(issue) => return Err(InvalidList(issue))
  }
  let count = gmail_thread_list_count(page)
  if count > read.max_threads - read.seen_ids.length() {
    return Err(BudgetExceeded)
  }
  for index in 0..<count {
    let id = gmail_thread_list_id_at(page, index).unwrap()
    if read.seen_ids.contains(id) {
      return Err(DuplicateThread)
    }
  }
  let next_token = gmail_thread_list_next_page_token(page)
  if next_token is Some(token) {
    if read.seen_tokens.contains(token) {
      return Err(InvalidPagination)
    }
    read.seen_tokens[token] = true
  }
  for index in 0..<count {
    read.seen_ids[gmail_thread_list_id_at(page, index).unwrap()] = true
  }
  read.pages.push(page)
  read.active_page = Some(page)
  read.target_index = 0
  read.next_token = next_token
  read.phase = Ready
  Ok(page)
}

///|
pub fn accept_gmail_thread(
  read : GmailThreadRead,
  request : GmailThreadRequest,
  bytes : Bytes,
) -> Result[GmailThreadProjection, GmailThreadReadIssue] {
  guard gmail_thread_request_matches(read, request) && request.kind is Get(_, _) else {
    return Err(ForeignRequest)
  }
  read.pending = None
  read.phase = Failed
  let thread = match
    project_gmail_thread_for_metadata_request(
      bytes,
      request,
      read.thread_limits,
    ) {
    Ok(thread) => thread
    Err(issue) => return Err(InvalidThread(issue))
  }
  read.threads.push(thread)
  read.target_index += 1
  read.phase = Ready
  Ok(thread)
}

///|
pub fn gmail_thread_projection_matches_request(
  thread : GmailThreadProjection,
  request : GmailThreadRequest,
) -> Bool {
  match request.kind {
    List(_) => false
    Get(page, index) =>
      (
        thread.metadata_request is Some(original) &&
        physical_equal(original, request)
      ) &&
      physical_equal(thread.targets, page) &&
      thread.target_index == index &&
      request.read.threads.any(original => physical_equal(original, thread))
  }
}

///|
pub fn gmail_thread_read_completed(read : GmailThreadRead) -> Bool {
  read.phase == Complete
}

///|
pub fn close_gmail_thread_read(read : GmailThreadRead) -> Unit {
  read.phase = Closed
  read.pending = None
  // Retained original response projections have escaped to callers. Closure
  // prohibits further protocol work and does not assert physical retirement.
}
