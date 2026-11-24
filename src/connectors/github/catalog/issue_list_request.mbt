///|
/// Refuse the first locator before the Site asks for read authority.
pub(all) enum IssueListStartIssue {
  InvalidRepository
  InvalidPageSize
} derive(Eq, Debug)

///|
/// The original plain owner/repository names are in the same domain as
/// GraphQL publication. The Site sends this locator through its own grant.
pub fn issue_list_start(
  owner : String,
  repository : String,
  page_size : Int,
) -> Result[NextPage, IssueListStartIssue] {
  if page_size < 1 || page_size > 100 {
    return Err(InvalidPageSize)
  }
  if !repository_access_valid(owner, repository) {
    return Err(InvalidRepository)
  }
  Ok({
    path: "/repos/\{owner}/\{repository}/issues",
    query: [("per_page", page_size.to_string())],
    page: 1,
  })
}

///|
/// The Site supplies only original Text values for these named filters. The
/// common exchange encodes each once; the Catalog never decodes caller text.
pub fn issue_list_filter_allowed(name : String) -> Bool {
  match name {
    "state" | "since" | "labels" | "sort" | "direction" => true
    _ => false
  }
}
