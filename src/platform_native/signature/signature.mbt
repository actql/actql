///|
pub(all) enum NativeSignatureIssue {
  UnsupportedTarget
  InvalidInput
  LibraryLoad(String)
  InvalidPublicKey(String)
  UnsupportedKey(String)
  Verification(String)
} derive(Eq, Debug)
