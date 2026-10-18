///|
pub(all) enum NativeSignatureIssue {
  UnsupportedTarget
  InvalidInput
  LibraryLoad(String)
  InvalidPublicKey(String)
  InvalidPrivateKey(String)
  UnsupportedKey(String)
  Verification(String)
  Signing(String)
  CleanupPending
  CloseUnconfirmed(String)
} derive(Eq, Debug)
