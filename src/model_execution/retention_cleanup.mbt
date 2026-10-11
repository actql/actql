///|
// Call only at the existing owner's confirmed retirement point. Non-JS
// clear() changes length but leaves old values in the backing allocation.
// Shrinking the now-empty array retires that backing without copying values.
// This does not discharge historical proofs or an independent borrowed use.
fn[T] retire_model_owned_array(values : Array[T]) -> Unit {
  values.clear()
  values.shrink_to_fit()
}
