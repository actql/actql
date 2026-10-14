///|
// Canonicalize the command spelling only. Submitted text, format, parameters,
// original Submission and explicit invocation attempt still pass the same
// existing AQL intake, lookup-first acceptance and execution Owners.
fn local_run_original_operation() -> String {
  "aql"
}

///|
// JSON is the original Owner response, including Unknown/refusal distinctions.
// Human output makes no claim that acceptance or an exit code completed a Run.
fn local_run_reply(child : @argparse.Matches, original : String) -> String {
  if child.flags.get("json").unwrap_or(false) {
    original
  } else {
    "Local run response (original Submission preserved):\n" + original
  }
}
