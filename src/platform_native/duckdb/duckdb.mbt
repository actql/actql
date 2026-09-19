///|
pub(all) enum NativeDuckDBIssue {
  UnsupportedTarget
  LibraryLoad(String)
  DatabaseOpen(String)
  Query(String)
}
