///|
pub(all) enum NativeSignatureIssue {
  UnsupportedTarget
  InvalidInput
  LibraryLoad(String)
  InvalidPublicKey(String)
  UnsupportedKey(String)
  Verification(String)
} derive(Eq, Debug)

///|
pub struct Sha256Hasher {
  library : Library
  state : Sha256State
}
