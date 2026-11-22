///|
/// The outer Issue or PullRequest listing owns one history per original read.
/// Nested connections retain their own cursors. The existing request ceiling
/// bounds the outer history, including a final accepted page that cannot send.
pub struct GraphqlOuterCursorHistory {
  seen : Map[String, Bool]
}

///|
pub fn prepare_graphql_outer_cursor_history() -> GraphqlOuterCursorHistory {
  { seen: Default::default(), }
}

///|
/// The cursor belongs to an accepted provider page. Compare its exact Text;
/// accepting it twice would revisit a page already in the original prefix.
pub fn record_graphql_outer_cursor(
  history : GraphqlOuterCursorHistory,
  cursor : String,
) -> Bool {
  if history.seen.contains(cursor) {
    return false
  }
  history.seen[cursor] = true
  true
}
