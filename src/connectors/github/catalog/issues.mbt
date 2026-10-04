///|
/// Limits on one listing page body.
pub(all) struct PageLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
} derive(Eq, Debug)

///|
/// One Issue row of the `issues` Resource. Nullable provider fields keep
/// their explicit null; a missing required field refuses the page.
pub(all) struct IssueRow {
  number : Int64
  node_id : String
  title : String
  state : String
  body : String?
  author : String?
  comments : Int64
  created_at : String
  updated_at : String
  closed_at : String?
} derive(Eq, Debug)

///|
pub(all) enum IssuePageIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  MissingRequiredField(String)
  NullRequiredField(String)
  InvalidField(String)
} derive(Eq, Debug)

///|
/// One projected listing page. Pull requests are Issues in GitHub's listing;
/// they are excluded here and counted, never returned as Issue rows.
pub(all) struct IssuePage {
  rows : Array[IssueRow]
  excluded_pull_requests : Int
  provider_items : Int
} derive(Eq, Debug)

///|
fn required_field(
  object : @decode.ObjectView,
  name : String,
) -> Result[@decode.Cursor, IssuePageIssue] {
  match @decode.field(object, name) {
    Missing => Err(MissingRequiredField(name))
    ExplicitNull => Err(NullRequiredField(name))
    Present(value) => Ok(value)
  }
}

///|
fn required_text(
  object : @decode.ObjectView,
  name : String,
) -> Result[String, IssuePageIssue] {
  match required_field(object, name) {
    Err(issue) => Err(issue)
    Ok(value) =>
      match @decode.text(value) {
        Ok(text) => Ok(text)
        Err(_) => Err(InvalidField(name))
      }
  }
}

///|
fn required_integer(
  object : @decode.ObjectView,
  name : String,
) -> Result[Int64, IssuePageIssue] {
  match required_field(object, name) {
    Err(issue) => Err(issue)
    Ok(value) =>
      match @decode.safe_integer(value) {
        Ok(number) => Ok(number)
        Err(_) => Err(InvalidField(name))
      }
  }
}

///|
/// A nullable text field: present text, explicit null, or (when the provider
/// omits it) refusal; omission and null are not the same observation.
fn nullable_text(
  object : @decode.ObjectView,
  name : String,
) -> Result[String?, IssuePageIssue] {
  match @decode.field(object, name) {
    Missing => Err(MissingRequiredField(name))
    ExplicitNull => Ok(None)
    Present(value) =>
      match @decode.text(value) {
        Ok(text) => Ok(Some(text))
        Err(_) => Err(InvalidField(name))
      }
  }
}

///|
fn author_login(object : @decode.ObjectView) -> Result[String?, IssuePageIssue] {
  match @decode.field(object, "user") {
    Missing => Err(MissingRequiredField("user"))
    ExplicitNull => Ok(None)
    Present(value) =>
      match @decode.open_object(value) {
        Ok(user) =>
          match required_text(user, "login") {
            Ok(login) => Ok(Some(login))
            Err(issue) => Err(issue)
          }
        Err(_) => Err(InvalidField("user"))
      }
  }
}

///|
fn issue_row(object : @decode.ObjectView) -> Result[IssueRow, IssuePageIssue] {
  let state = match required_text(object, "state") {
    Ok(state) => state
    Err(issue) => return Err(issue)
  }
  if state != "open" && state != "closed" {
    return Err(InvalidField("state"))
  }
  let number = match required_integer(object, "number") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let node_id = match required_text(object, "node_id") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let title = match required_text(object, "title") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let body = match nullable_text(object, "body") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let author = match author_login(object) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let comments = match required_integer(object, "comments") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let created_at = match required_timestamp(object, "created_at") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let updated_at = match required_timestamp(object, "updated_at") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let closed_at = match nullable_timestamp(object, "closed_at") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    number,
    node_id,
    title,
    state,
    body,
    author,
    comments,
    created_at,
    updated_at,
    closed_at,
  })
}

///|
/// GitHub states timestamps as whole-second UTC `YYYY-MM-DDTHH:MM:SSZ`. The
/// ActQL timestamp spelling carries milliseconds, so the exact same instant
/// is `YYYY-MM-DDTHH:MM:SS.000Z`. Any other spelling is not converted.
pub fn canonical_timestamp(text : String) -> String? {
  if text.length() != 20 ||
    text[4] != '-' ||
    text[7] != '-' ||
    text[10] != 'T' ||
    text[13] != ':' ||
    text[16] != ':' ||
    text[19] != 'Z' {
    return None
  }
  for index in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18] {
    let unit = text[index].to_int()
    if unit < 48 || unit > 57 {
      return None
    }
  }
  Some(text.view(start_offset=0, end_offset=19).to_owned() + ".000Z")
}

///|
fn required_timestamp(
  object : @decode.ObjectView,
  name : String,
) -> Result[String, IssuePageIssue] {
  match required_text(object, name) {
    Ok(value) =>
      match canonical_timestamp(value) {
        Some(canonical) => Ok(canonical)
        None => Err(InvalidField(name))
      }
    Err(issue) => Err(issue)
  }
}

///|
fn nullable_timestamp(
  object : @decode.ObjectView,
  name : String,
) -> Result[String?, IssuePageIssue] {
  match nullable_text(object, name) {
    Ok(Some(value)) =>
      match canonical_timestamp(value) {
        Some(canonical) => Ok(Some(canonical))
        None => Err(InvalidField(name))
      }
    Ok(None) => Ok(None)
    Err(issue) => Err(issue)
  }
}

///|
/// Project one 200 listing body into Issue rows. The page is all-or-nothing:
/// any invalid Issue refuses the page.
pub fn project_issue_page(
  body : Bytes,
  limits : PageLimits,
) -> Result[IssuePage, IssuePageIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_rows <= 0 {
    return Err(InvalidLimits)
  }
  if body.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = @source.parse_json_bytes(body, {
    max_input_bytes: limits.max_bytes,
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
  })
  guard parsed is Ok(node) else { return Err(InvalidResponse) }
  let admitted = @decode.admit(node, {
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
    max_string_bytes: limits.max_bytes,
    max_total_string_bytes: limits.max_bytes,
  })
  guard admitted is Ok(root) else { return Err(InvalidResponse) }
  guard @decode.elements(root) is Ok(items) else { return Err(InvalidResponse) }
  if items.length() > limits.max_rows {
    return Err(BudgetExceeded)
  }
  let rows = []
  let mut excluded = 0
  for item in items {
    guard @decode.open_object(item) is Ok(object) else {
      return Err(InvalidResponse)
    }
    match @decode.field(object, "pull_request") {
      Missing =>
        match issue_row(object) {
          Ok(row) => rows.push(row)
          Err(issue) => return Err(issue)
        }
      _ => excluded = excluded + 1
    }
  }
  Ok({ rows, excluded_pull_requests: excluded, provider_items: items.length(), })
}
