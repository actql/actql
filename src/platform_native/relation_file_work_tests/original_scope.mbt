///|
// The ordinary package retains the existing provider dependency for every
// Moon driver, including the empty internal one. This type alias preserves
// that original ABI and adds no constructor, FFI entry or scope permission.
pub type OriginalReadScope = @bootstrap.NativeBackedReadScope
