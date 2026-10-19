///|
#export_name("gmailPrepareThreadRead")
pub fn gmail_prepare_thread_read(
  mailbox : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_page_rows : Int,
  max_id_bytes : Int,
  max_token_bytes : Int,
  max_messages : Int,
  max_labels : Int,
  max_headers : Int,
  max_header_units : Int,
  max_comment_depth : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
  max_pages : Int,
  max_threads : Int,
) -> Result[@catalog.GmailThreadRead, @catalog.GmailThreadReadIssue] {
  @catalog.prepare_gmail_thread_read(
    mailbox,
    {
      max_bytes,
      max_nodes,
      max_depth,
      max_rows: max_page_rows,
      max_id_bytes,
      max_token_bytes,
    },
    {
      max_bytes,
      max_nodes,
      max_depth,
      max_messages,
      max_labels,
      max_headers,
      max_header_units,
      max_comment_depth,
      max_value_nodes,
      max_value_text_bytes,
    },
    max_pages,
    max_threads,
  )
}

///|
#export_name("gmailNextThreadRequest")
pub fn gmail_next_thread_request(
  read : @catalog.GmailThreadRead,
) -> Result[Array[@catalog.GmailThreadRequest], @catalog.GmailThreadReadIssue] {
  match @catalog.next_gmail_thread_request(read) {
    Ok(Some(request)) => Ok([request])
    Ok(None) => Ok([])
    Err(issue) => Err(issue)
  }
}

///|
#export_name("gmailThreadRequestJson")
pub fn gmail_thread_request_json(
  request : @catalog.GmailThreadRequest,
) -> String {
  let token : Json = match @catalog.gmail_thread_request_page_token(request) {
    Some(value) => value.to_json()
    None => Json::null()
  }
  let id : Json = match @catalog.gmail_thread_request_target_id(request) {
    Some(value) => value.to_json()
    None => Json::null()
  }
  (
    {
      "mailbox": @catalog.gmail_thread_request_mailbox(request).to_json(),
      "ordinal": @catalog.gmail_thread_request_ordinal(request).to_json(),
      "isList": @catalog.gmail_thread_request_is_list(request).to_json(),
      "pageToken": token,
      "threadId": id,
    } : Json).stringify()
}

///|
#export_name("gmailThreadRequestMatches")
pub fn gmail_thread_request_matches(
  read : @catalog.GmailThreadRead,
  request : @catalog.GmailThreadRequest,
) -> Bool {
  @catalog.gmail_thread_request_matches(read, request)
}

///|
#export_name("gmailAcceptThreadList")
pub fn gmail_accept_thread_list(
  read : @catalog.GmailThreadRead,
  request : @catalog.GmailThreadRequest,
  bytes : Bytes,
) -> Result[@catalog.GmailThreadListPage, @catalog.GmailThreadReadIssue] {
  @catalog.accept_gmail_thread_list(read, request, bytes)
}

///|
#export_name("gmailAcceptThread")
pub fn gmail_accept_thread(
  read : @catalog.GmailThreadRead,
  request : @catalog.GmailThreadRequest,
  bytes : Bytes,
) -> Result[@catalog.GmailThreadProjection, @catalog.GmailThreadReadIssue] {
  @catalog.accept_gmail_thread(read, request, bytes)
}

///|
#export_name("gmailThreadProjectionMatchesRequest")
pub fn gmail_thread_projection_matches_request(
  thread : @catalog.GmailThreadProjection,
  request : @catalog.GmailThreadRequest,
) -> Bool {
  @catalog.gmail_thread_projection_matches_request(thread, request)
}

///|
#export_name("gmailThreadReadCompleted")
pub fn gmail_thread_read_completed(read : @catalog.GmailThreadRead) -> Bool {
  @catalog.gmail_thread_read_completed(read)
}

///|
#export_name("gmailCloseThreadRead")
pub fn gmail_close_thread_read(read : @catalog.GmailThreadRead) -> Unit {
  @catalog.close_gmail_thread_read(read)
}

///|
#export_name("gmailThreadRowsWire")
pub fn gmail_thread_rows_wire(
  thread : @catalog.GmailThreadProjection,
  names : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.GmailThreadIssue] {
  @catalog.gmail_thread_rows_wire(
    thread, names, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("gmailThreadSchemaWire")
pub fn gmail_thread_schema_wire(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @catalog.GmailThreadIssue] {
  @catalog.gmail_thread_schema_wire(max_bytes, max_nodes, max_depth)
}

///|
#export_name("gmailThreadColumnNames")
pub fn gmail_thread_column_names() -> Array[String] {
  @catalog.gmail_thread_column_names()
}

///|
#export_name("gmailThreadRelationFactsWire")
pub fn gmail_thread_relation_facts_wire() -> String {
  @catalog.gmail_thread_facts_wire()
}
