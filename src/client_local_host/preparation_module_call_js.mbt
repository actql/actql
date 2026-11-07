///|
/// Clear synchronous construction occupancy after foreign callback unwind.
/// This finalizer never clears an original, reservation, borrower or resource.
extern "js" fn preparation_module_scope(
  body : () -> Unit,
  finish : () -> Unit,
) -> Unit =
  #|(body,finish) => { try { return body(); } finally { finish(); } }

///|
// The raw JS scope has no generic FFI ABI. Keep the original nominal Result
// inside MoonBit; a foreign throw unwinds the same finish before propagating.
fn[T, E] preparation_module_call(
  body : () -> Result[T, E],
  finish : () -> Unit,
) -> Result[T, E] {
  let result = Ref(None)
  preparation_module_scope(() => result.val = Some(body()), finish)
  result.val.unwrap()
}

///|
#external
pub type QueryBindingForeignFailure

///|
extern "js" fn query_binding_failure_scope(
  body : () -> Unit,
  failure : (QueryBindingForeignFailure) -> Unit,
  finish : () -> Unit,
) -> Unit =
  #|(body,failure,finish) => { try { body(); } catch (cause) { failure(Object.freeze({cause})); } finally { finish(); } }

///|
fn[T] query_binding_protected_call(
  body : () -> Result[T, ClientRequestPreparationIssue],
  finish : () -> Unit,
) -> Result[
  Result[T, ClientRequestPreparationIssue],
  QueryBindingForeignFailure,
] {
  let result = Ref(None)
  query_binding_failure_scope(
    () => result.val = Some(Ok(body())),
    failure => result.val = Some(Err(failure)),
    finish,
  )
  result.val.unwrap()
}
