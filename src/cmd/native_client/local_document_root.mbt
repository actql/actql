///|
// Submitted documents and immutable references are untrusted bounded input.
// Their location cannot select the private Host installation or its authority.
// Preserve the explicit configuration profile's original default; product
// bootstrap will select the user's working directory independently.
fn local_document_root(
  matches : @argparse.Matches,
  selected_configuration_root : String,
) -> String raise ClientStop {
  optional(matches, "input-root").unwrap_or(selected_configuration_root)
}
