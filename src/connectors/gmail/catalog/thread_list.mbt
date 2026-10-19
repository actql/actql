///|
pub(all) struct GmailThreadListLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
  max_id_bytes : Int
  max_token_bytes : Int
}

///|
pub(all) enum GmailThreadListIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  DuplicateThread
} derive(Eq, Debug)

///|
// List observations select dependent get targets. They contain no messages
// and cannot issue a logical thread row, complete scan, grant or response ACK.
pub struct GmailThreadListPage {
  response_sha256 : String
  priv ids : Array[String]
  priv next_page_token : String?
}

///|
fn gmail_thread_list_text(
  value : @decode.Cursor,
  max_bytes : Int,
) -> Result[String, GmailThreadListIssue] {
  guard @decode.text(value) is Ok(text) else { return Err(InvalidResponse) }
  // The UTF-16 length is a lower bound, not an encoded-byte measurement.
  if text.length() > max_bytes || @utf8.encode(text).length() > max_bytes {
    return Err(BudgetExceeded)
  }
  Ok(text)
}

///|
pub fn project_gmail_thread_list(
  bytes : Bytes,
  limits : GmailThreadListLimits,
) -> Result[GmailThreadListPage, GmailThreadListIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_rows < 0 ||
    limits.max_id_bytes < 0 ||
    limits.max_token_bytes < 0 {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let cursor = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidResponse)
  }
  guard @decode.closed_object(cursor, [
      "threads", "nextPageToken", "resultSizeEstimate",
    ])
    is Ok(root) else {
    return Err(InvalidResponse)
  }
  let next_page_token = match @decode.field(root, "nextPageToken") {
    Missing => None
    ExplicitNull => return Err(InvalidResponse)
    Present(value) => {
      let text = match gmail_thread_list_text(value, limits.max_token_bytes) {
        Ok(text) => text
        Err(issue) => return Err(issue)
      }
      // Google pagination ends on an absent or empty token, not a short page.
      if text.is_empty() {
        None
      } else {
        Some(text)
      }
    }
  }
  match @decode.field(root, "resultSizeEstimate") {
    Missing => ()
    ExplicitNull => return Err(InvalidResponse)
    Present(value) => {
      guard @decode.safe_integer(value) is Ok(estimate) &&
        estimate >= 0L &&
        estimate <= 4_294_967_295L else {
        return Err(InvalidResponse)
      }
      // An estimate is never a message count, row limit or completeness proof.
    }
  }
  let ids : Array[String] = []
  match @decode.field(root, "threads") {
    Missing => ()
    ExplicitNull => return Err(InvalidResponse)
    Present(list) => {
      guard @decode.array_length(list) is Some(count) else {
        return Err(InvalidResponse)
      }
      if count > limits.max_rows {
        return Err(BudgetExceeded)
      }
      // The documented threads.list maximum is independent of caller bounds.
      if count > 500 {
        return Err(InvalidResponse)
      }
      let seen : Map[String, Bool] = Map([])
      for index in 0..<count {
        guard @decode.closed_object(@decode.element_at(list, index).unwrap(), [
            "id", "snippet", "historyId",
          ])
          is Ok(row) &&
          @decode.field(row, "id") is Present(value) else {
          return Err(InvalidResponse)
        }
        let id = match gmail_thread_list_text(value, limits.max_id_bytes) {
          Ok(id) => id
          Err(issue) => return Err(issue)
        }
        if id.is_empty() {
          return Err(InvalidResponse)
        }
        if seen.contains(id) {
          return Err(DuplicateThread)
        }
        for name in ["snippet", "historyId"] {
          match @decode.field(row, name) {
            Missing => ()
            ExplicitNull => return Err(InvalidResponse)
            Present(value) => {
              guard @decode.text(value) is Ok(_) else {
                return Err(InvalidResponse)
              }
            }
          }
        }
        seen[id] = true
        ids.push(id)
      }
    }
  }
  Ok({ response_sha256: @sha.hex(bytes), ids, next_page_token, })
}

///|
pub fn gmail_thread_list_count(page : GmailThreadListPage) -> Int {
  page.ids.length()
}

///|
pub fn gmail_thread_list_id_at(
  page : GmailThreadListPage,
  index : Int,
) -> String? {
  if index < 0 || index >= page.ids.length() {
    None
  } else {
    Some(page.ids[index])
  }
}

///|
pub fn gmail_thread_list_next_page_token(page : GmailThreadListPage) -> String? {
  page.next_page_token
}
