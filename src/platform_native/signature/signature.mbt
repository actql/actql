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

///|
/// Both ready and partial receivers remain with the same installed owner until
/// explicit component and module retirement. This is not an installed profile.
pub(all) enum NativeCryptoComponentAcquisition {
  ReadyCryptoComponent(OriginalCryptoComponent)
  PendingCryptoComponent(OriginalCryptoComponent, NativeSignatureIssue)
}

///|
/// A partial Library retains its own component borrow and cleanup receiver.
pub(all) enum NativeCryptoLibraryAcquisition {
  ReadyCryptoLibrary(Library)
  PendingCryptoLibrary(Library, NativeSignatureIssue)
}
