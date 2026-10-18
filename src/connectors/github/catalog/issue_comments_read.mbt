///|
/// Bounded decoder sequencing for the original repository's comment Source.
/// This state is not a credential use, observation charge or physical ACK.
pub struct IssueCommentsRead {
  repository : GraphqlRepository
  limits : PageLimits
  max_pages : Int
  max_subjects : Int
  mut pages : Int
  mut rows : Int
  subjects : Array[IssueCommentSubject]
  row_ids : Array[Int64]
  mut subject_index : Int
  mut native_type : String
  mut enumeration_after : String?
  enumeration_cursors : Array[String]
  mut enumeration_more : Bool
  mut comment_after : String?
  comment_cursors : Array[String]
  mut pending : IssueCommentsReadRequest?
  mut page : GraphqlIssueCommentPage?
  mut complete : Bool
  mut closed : Bool
}

///|
priv enum IssueCommentsReadRequest {
  Subjects(Int)
  Comments(Int)
}

///|
pub fn begin_issue_comments_read(
  repository : GraphqlRepository,
  limits : PageLimits,
  max_pages : Int,
  max_subjects : Int,
) -> Result[IssueCommentsRead, GraphqlResponseIssue] {
  if !valid_subject_id(repository.node_id) ||
    repository.database_id <= 0L ||
    repository.name_with_owner.is_empty() ||
    max_pages < 1 ||
    max_subjects < 1 ||
    limits.max_rows < 1 ||
    limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 {
    return Err(InvalidResponse)
  }
  Ok({
    repository,
    limits,
    max_pages,
    max_subjects,
    pages: 0,
    rows: 0,
    subjects: [],
    row_ids: [],
    subject_index: 0,
    native_type: "Issue",
    enumeration_after: None,
    enumeration_cursors: [],
    enumeration_more: true,
    comment_after: None,
    comment_cursors: [],
    pending: None,
    page: None,
    complete: false,
    closed: false,
  })
}

///|
fn IssueCommentsRead::refuse(
  self : IssueCommentsRead,
  issue : GraphqlResponseIssue,
) -> Result[T, GraphqlResponseIssue] {
  self.closed = true
  self.pending = None
  Err(issue)
}

///|
/// Produce exactly the next fixed request. A pending reply cannot be replaced
/// by another request, and an incomplete/failed reply is never retried here.
pub fn issue_comments_read_next_request(
  read : IssueCommentsRead,
  first : Int,
) -> Result[String?, GraphqlResponseIssue] {
  if read.closed || read.pending is Some(_) || read.page is Some(_) {
    return read.refuse(InvalidResponse)
  }
  if read.complete {
    return Ok(None)
  }
  if first < 1 || first > 100 {
    return read.refuse(InvalidResponse)
  }
  if read.pages >= read.max_pages {
    return read.refuse(BudgetExceeded)
  }
  if read.subject_index < read.subjects.length() {
    match
      issue_comments_request(
        read.subjects[read.subject_index],
        first,
        read.comment_after,
      ) {
      Ok(body) => {
        read.pending = Some(Comments(first))
        Ok(Some(body))
      }
      Err(_) => read.refuse(InvalidResponse)
    }
  } else {
    match
      issue_comment_subjects_request(
        read.repository.node_id,
        read.native_type,
        first,
        read.enumeration_after,
      ) {
      Ok(body) => {
        read.pending = Some(Subjects(first))
        Ok(Some(body))
      }
      Err(_) => read.refuse(InvalidResponse)
    }
  }
}

///|
fn issue_comments_advance_subjects(read : IssueCommentsRead) -> Unit {
  if read.subject_index < read.subjects.length() || read.enumeration_more {
    return
  }
  if read.native_type == "Issue" {
    read.native_type = "PullRequest"
    read.enumeration_after = None
    read.enumeration_cursors.clear()
    read.enumeration_more = true
  } else {
    read.complete = true
  }
}

///|
/// Admit the exact pending response. All pages, including enumeration and
/// empty subjects, share one finite request ceiling. The Site must charge
/// the real received body before invoking this decoder.
pub fn issue_comments_read_accept(
  read : IssueCommentsRead,
  body : Bytes,
) -> Result[Unit, GraphqlResponseIssue] {
  if read.closed || read.complete || read.page is Some(_) {
    return read.refuse(InvalidResponse)
  }
  let pending = match read.pending {
    Some(value) => value
    None => return read.refuse(InvalidResponse)
  }
  read.pending = None
  read.pages += 1
  match pending {
    Subjects(first) => {
      let page = match
        project_issue_comment_subjects_response(
          body,
          read.limits,
          read.repository,
          read.native_type,
        ) {
        Ok(value) => value
        Err(issue) => return read.refuse(issue)
      }
      if page.subjects.length() > first ||
        page.subjects.length() > read.max_subjects - read.subjects.length() {
        return read.refuse(BudgetExceeded)
      }
      for subject in page.subjects {
        if read.subjects.any(previous => {
            previous.node_id == subject.node_id ||
            (
              previous.native_type == subject.native_type &&
              previous.number == subject.number
            )
          }) {
          return read.refuse(ForeignSubject)
        }
        read.subjects.push(subject)
      }
      read.enumeration_more = page.has_next_page
      if page.has_next_page {
        let next = page.end_cursor.unwrap()
        if read.enumeration_cursors.contains(next) {
          return read.refuse(MissingCursor)
        }
        read.enumeration_cursors.push(next)
        read.enumeration_after = Some(next)
      }
      issue_comments_advance_subjects(read)
      Ok(())
    }
    Comments(first) => {
      let subject = read.subjects[read.subject_index]
      let page = match
        project_issue_comments_response(body, read.limits, subject) {
        Ok(value) => value
        Err(issue) => return read.refuse(issue)
      }
      if page.rows.length() > first ||
        page.rows.length() > read.limits.max_rows - read.rows {
        return read.refuse(BudgetExceeded)
      }
      for row in page.rows {
        if read.row_ids.contains(row.id) {
          return read.refuse(Row(InvalidField("fullDatabaseId")))
        }
        read.row_ids.push(row.id)
      }
      read.rows += page.rows.length()
      if page.has_next_page {
        let next = page.end_cursor.unwrap()
        if read.comment_cursors.contains(next) {
          return read.refuse(MissingCursor)
        }
        read.comment_cursors.push(next)
        read.comment_after = Some(next)
      } else {
        read.subject_index += 1
        read.comment_after = None
        read.comment_cursors.clear()
        issue_comments_advance_subjects(read)
      }
      read.page = Some(page)
      Ok(())
    }
  }
}

///|
/// Transfer only the completed logical page alias. This is not consumption
/// of a RowRun charge, retirement of raw responses or transport cleanup ACK.
/// Original Site/RowRun owners still fence and consume their actual ticket.
pub fn issue_comments_read_take_page(
  read : IssueCommentsRead,
) -> Result[GraphqlIssueCommentPage?, GraphqlResponseIssue] {
  if read.closed {
    return Err(InvalidResponse)
  }
  let page = read.page
  read.page = None
  Ok(page)
}

///|
pub fn issue_comments_read_close(read : IssueCommentsRead) -> Unit {
  read.closed = true
  read.pending = None
  read.page = None
}
