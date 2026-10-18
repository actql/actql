///|
// Trusted installer control record, not a public constructor, Host, domain or
// capacity grant. The enclosing initial Crypto original retains this descriptor
// separately until actual Library/context/mapping retirement has acknowledged.
type InitialCryptoBacking

///|
extern "C" fn initial_crypto_backing_open(
  bytes : Int64,
) -> InitialCryptoBacking = "actql_initial_crypto_backing_open"

///|
#borrow(original)
extern "C" fn InitialCryptoBacking::current(
  original : InitialCryptoBacking,
) -> Bool = "actql_initial_crypto_backing_current"

///|
#borrow(original)
extern "C" fn InitialCryptoBacking::descriptor(
  original : InitialCryptoBacking,
) -> Int = "actql_initial_crypto_backing_descriptor"

///|
#borrow(original)
extern "C" fn InitialCryptoBacking::close_checked(
  original : InitialCryptoBacking,
) -> Bool = "actql_initial_crypto_backing_close"

///|
#borrow(original)
extern "C" fn InitialCryptoBacking::acquisition_issue(
  original : InitialCryptoBacking,
) -> Int = "actql_initial_crypto_backing_acquisition_issue"
