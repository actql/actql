// Bounded provider DATA only. Request identity is not transport custody,
// a catalog snapshot, permission, physical funding or a conditional-write token.

///|
pub(all) enum CatalogKind {
  Workbooks
  DataSources
  Views
  Flows
} derive(Eq, Debug)

///|
pub(all) enum CatalogIssue {
  InvalidLimits
  InvalidSelection
  CapacityExceeded
  UnexpectedStatus
  InvalidResponse
  ForeignPage
  DuplicateIdentity
} derive(Eq, Debug)

///|
pub(all) struct CatalogResponseLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
}

///|
pub struct CatalogPageRequest {
  kind : CatalogKind
  api_version : String
  site_id : String
  page_number : Int
  path : String
}

///|
// Missing/null optional metadata remains unknown, not a known empty collection,
// zero usage, no extract, last refresh/run time, or permission.
pub(all) struct CatalogRow {
  id : String
  name : String
  project_id : String?
  project_name : String?
  owner_id : String?
  created_at : String?
  updated_at : String?
  tags : Array[String]?
  content_url : String?
  datasource_type : String?
  has_extract : Bool?
  view_count : Int64?
} derive(Eq, Debug)

///|
pub struct CatalogPage {
  request : CatalogPageRequest
  total_available : Int64
  provider_items : Int
  rows : Array[CatalogRow]
  response_sha256 : String
}

///|
fn catalog_names(kind : CatalogKind) -> (String, String) {
  match kind {
    Workbooks => ("workbooks", "workbook")
    DataSources => ("datasources", "datasource")
    Views => ("views", "view")
    Flows => ("flows", "flow")
  }
}

///|
// The documented source profile uses 100 rows per page. API version/site are
// selected by the installed connection; syntactic admission does not authenticate
// a server, identify its actual site or prove API-version support.
pub fn prepare_catalog_page_request(
  kind : CatalogKind,
  api_version : String,
  site_id : String,
  page_number : Int,
  max_path_bytes : Int,
) -> Result[CatalogPageRequest, CatalogIssue] {
  if max_path_bytes <= 0 {
    return Err(InvalidLimits)
  }
  if !version(api_version) || !luid(site_id) || page_number <= 0 {
    return Err(InvalidSelection)
  }
  let (resource, _) = catalog_names(kind)
  let path = "/api/" +
    api_version +
    "/sites/" +
    site_id +
    "/" +
    resource +
    "?pageSize=100&pageNumber=" +
    page_number.to_string() +
    (if kind == Views { "&includeUsageStatistics=true" } else { "" })
  if path.length() > max_path_bytes {
    return Err(CapacityExceeded)
  }
  Ok({ kind, api_version, site_id, page_number, path, })
}

///|
pub fn catalog_page_path(request : CatalogPageRequest) -> String {
  request.path
}

///|
pub fn catalog_page_method(_request : CatalogPageRequest) -> String {
  "GET"
}

///|
fn catalog_issue(issue : JobIssue) -> CatalogIssue {
  match issue {
    InvalidLimits => InvalidLimits
    CapacityExceeded => CapacityExceeded
    _ => InvalidResponse
  }
}

///|
fn catalog_required(
  object : @decode.ObjectView,
  key : String,
) -> Result[@decode.Cursor, CatalogIssue] {
  match @decode.field(object, key) {
    Present(value) => Ok(value)
    Missing | ExplicitNull => Err(InvalidResponse)
  }
}

///|
fn catalog_required_text(
  object : @decode.ObjectView,
  key : String,
) -> Result[String, CatalogIssue] {
  match catalog_required(object, key) {
    Ok(value) => @decode.text(value).map_err(_ => CatalogIssue::InvalidResponse)
    Err(issue) => Err(issue)
  }
}

///|
fn catalog_optional_text(
  object : @decode.ObjectView,
  key : String,
) -> Result[String?, CatalogIssue] {
  match @decode.field(object, key) {
    Missing | ExplicitNull => Ok(None)
    Present(value) =>
      @decode.text(value)
      .map(value => Some(value))
      .map_err(_ => CatalogIssue::InvalidResponse)
  }
}

///|
fn catalog_optional_timestamp(
  object : @decode.ObjectView,
  key : String,
) -> Result[String?, CatalogIssue] {
  match catalog_optional_text(object, key) {
    Err(issue) => Err(issue)
    Ok(None) => Ok(None)
    Ok(Some(text)) => {
      // Tableau documents UTC whole seconds. Add exact zero milliseconds,
      // then let the existing Values Owner validate the calendar and instant.
      let canonical = if text.length() == 20 && text.has_suffix("Z") {
        text[:19].to_owned() + ".000Z"
      } else {
        text
      }
      if @values.timestamp_epoch_milliseconds(canonical) is Some(_) {
        Ok(Some(canonical))
      } else {
        Err(InvalidResponse)
      }
    }
  }
}

///|
// Tableau's documented JSON pagination fields are canonical decimal strings.
// Keep their exact Int64 spelling; do not round a JSON Double into a counter.
fn catalog_counter(value : @decode.Cursor) -> Result[Int64, CatalogIssue] {
  guard @decode.text(value) is Ok(text) &&
    @decode.decimal_int64(value) is Ok(number) &&
    number >= 0L &&
    number.to_string() == text else {
    return Err(InvalidResponse)
  }
  Ok(number)
}

///|
fn catalog_counter_at(
  object : @decode.ObjectView,
  key : String,
) -> Result[Int64, CatalogIssue] {
  match catalog_required(object, key) {
    Ok(value) => catalog_counter(value)
    Err(issue) => Err(issue)
  }
}

///|
fn catalog_optional_identity(
  object : @decode.ObjectView,
  key : String,
) -> Result[(String, String?)?, CatalogIssue] {
  match @decode.field(object, key) {
    Missing | ExplicitNull => Ok(None)
    Present(value) => {
      let nested = match
        @decode.open_object(value).map_err(_ => CatalogIssue::InvalidResponse) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let id = match catalog_required_text(nested, "id") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !luid(id) {
        return Err(InvalidResponse)
      }
      let name = match catalog_optional_text(nested, "name") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      Ok(Some((id, name)))
    }
  }
}

///|
fn catalog_tags(
  object : @decode.ObjectView,
) -> Result[Array[String]?, CatalogIssue] {
  match @decode.field(object, "tags") {
    Missing | ExplicitNull => Ok(None)
    Present(value) => {
      let values = match @decode.elements(value) {
        Ok(values) => values
        Err(_) => {
          let nested = match
            @decode.open_object(value).map_err(_ => {
              CatalogIssue::InvalidResponse
            }) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          match
            @decode.elements(
              match catalog_required(nested, "tag") {
                Ok(value) => value
                Err(issue) => return Err(issue)
              },
            ).map_err(_ => CatalogIssue::InvalidResponse) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
        }
      }
      let tags : Array[String] = []
      for value in values {
        let tag = match
          @decode.open_object(value).map_err(_ => CatalogIssue::InvalidResponse) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        tags.push(
          match catalog_required_text(tag, "label") {
            Ok(value) => value
            Err(issue) => return Err(issue)
          },
        )
      }
      Ok(Some(tags))
    }
  }
}

///|
fn catalog_row(
  kind : CatalogKind,
  value : @decode.Cursor,
) -> Result[CatalogRow, CatalogIssue] {
  let object = match
    @decode.open_object(value).map_err(_ => CatalogIssue::InvalidResponse) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let id = match catalog_required_text(object, "id") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let name = match catalog_required_text(object, "name") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !luid(id) {
    return Err(InvalidResponse)
  }
  let project = match catalog_optional_identity(object, "project") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let owner = match catalog_optional_identity(object, "owner") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let created_at = match catalog_optional_timestamp(object, "createdAt") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let updated_at = match catalog_optional_timestamp(object, "updatedAt") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let tags = match catalog_tags(object) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let content_url = match catalog_optional_text(object, "contentUrl") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let datasource_type = if kind == DataSources {
    match catalog_optional_text(object, "type") {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  } else {
    None
  }
  let has_extract = if kind == DataSources {
    match @decode.field(object, "hasExtracts") {
      Missing | ExplicitNull => None
      Present(value) =>
        match @decode.boolean(value) {
          Ok(value) => Some(value)
          Err(_) =>
            match @decode.text(value) {
              Ok("true") => Some(true)
              Ok("false") => Some(false)
              _ => return Err(InvalidResponse)
            }
        }
    }
  } else {
    None
  }
  let view_count = if kind == Views {
    match @decode.field(object, "usage") {
      Missing | ExplicitNull => None
      Present(value) => {
        let usage = match
          @decode.open_object(value).map_err(_ => CatalogIssue::InvalidResponse) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        Some(
          match catalog_counter_at(usage, "totalViewCount") {
            Ok(value) => value
            Err(issue) => return Err(issue)
          },
        )
      }
    }
  } else {
    None
  }
  Ok({
    id,
    name,
    project_id: project.map(value => value.0),
    project_name: match project {
      Some(value) => value.1
      None => None
    },
    owner_id: owner.map(value => value.0),
    created_at,
    updated_at,
    tags,
    content_url,
    datasource_type,
    has_extract,
    view_count,
  })
}

///|
// Only a complete application/json response to this exact request may enter.
// The provider omits the site in the body: the transport must independently
// enforce the original endpoint, TLS, credentials, redirects and current scope.
pub fn admit_catalog_page(
  request : CatalogPageRequest,
  http_status : Int,
  bytes : Bytes,
  limits : CatalogResponseLimits,
) -> Result[CatalogPage, CatalogIssue] {
  if limits.max_rows <= 0 || limits.max_rows > 100 {
    return Err(InvalidLimits)
  }
  if http_status != 200 {
    return Err(UnexpectedStatus)
  }
  let object = match
    provider_response_object(bytes, {
      max_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }).map_err(catalog_issue) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let pagination = match
    object_at(object, "pagination").map_err(catalog_issue) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let number = match catalog_counter_at(pagination, "pageNumber") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let size = match catalog_counter_at(pagination, "pageSize") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let total = match catalog_counter_at(pagination, "totalAvailable") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if number != request.page_number.to_int64() || size != 100L {
    return Err(ForeignPage)
  }
  let (plural, singular) = catalog_names(request.kind)
  let selected = match catalog_required(object, plural) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Tableau's documented JSON examples use both a direct collection array
  // and the named collection wrapper. Missing/null is never an empty page.
  let values = match @decode.elements(selected) {
    Ok(values) => values
    Err(_) => {
      let wrapper = match
        @decode.open_object(selected).map_err(_ => CatalogIssue::InvalidResponse) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        @decode.elements(
          match catalog_required(wrapper, singular) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          },
        ).map_err(_ => CatalogIssue::InvalidResponse) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    }
  }
  if values.length() > limits.max_rows {
    return Err(CapacityExceeded)
  }
  let offset = (request.page_number.to_int64() - 1L) * 100L
  if total < offset || (request.page_number > 1 && total == offset) {
    return Err(InvalidResponse)
  }
  let expected = if total - offset > 100L { 100L } else { total - offset }
  if values.length().to_int64() != expected {
    return Err(InvalidResponse)
  }
  let rows : Array[CatalogRow] = []
  for value in values {
    let row = match catalog_row(request.kind, value) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    for prior in rows {
      if prior.id == row.id {
        return Err(DuplicateIdentity)
      }
    }
    rows.push(row)
  }
  Ok({
    request,
    total_available: total,
    provider_items: values.length(),
    rows,
    response_sha256: @sha.hex(bytes),
  })
}

///|
pub fn catalog_page_rows(page : CatalogPage) -> Array[CatalogRow] {
  page.rows
}

///|
pub fn catalog_page_total_available(page : CatalogPage) -> Int64 {
  page.total_available
}

///|
pub fn catalog_page_response_sha256(page : CatalogPage) -> String {
  page.response_sha256
}

///|
// DATA continuation only, not a stable snapshot or permission to fetch again.
pub fn next_catalog_page(
  page : CatalogPage,
  max_path_bytes : Int,
) -> Result[CatalogPageRequest?, CatalogIssue] {
  let consumed = (page.request.page_number.to_int64() - 1L) * 100L +
    page.provider_items.to_int64()
  if consumed >= page.total_available {
    return Ok(None)
  }
  if page.request.page_number == 2147483647 {
    return Err(CapacityExceeded)
  }
  prepare_catalog_page_request(
    page.request.kind,
    page.request.api_version,
    page.request.site_id,
    page.request.page_number + 1,
    max_path_bytes,
  ).map(value => Some(value))
}
