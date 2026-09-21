///|
pub(all) enum NativeProcessImageIssue {
  InvalidLimit
  Open(String)
  Read(String)
  Close(String)
  CapacityExceeded
  EmptyImage
} derive(Eq, Debug)
