///|
test "CLI Checkpoint metadata requires original files and is unavailable in Remote mode" {
  let parsed = command().parse(
    argv=[
      "--mode", "local", "checkpoint-state", "--submission-ref-file", "submission.json",
      "--ref-file", "run.json",
    ],
    env=Map([]),
  )
  assert_true(parsed.subcommand is Some(("checkpoint-state", _)))
  for
    argv in [
      ["checkpoint-state", "--ref-file", "run.json"],
      ["checkpoint-state", "--submission-ref-file", "submission.json"],
    ] {
    assert_true(
      try {
        command().parse(argv=argv[:], env=Map([])) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
  let remote = command().parse(
    argv=[
      "checkpoint-state", "--submission-ref-file", "submission.json", "--ref-file",
      "run.json",
    ],
    env=Map([]),
  )
  let refused = try {
    execute(remote) |> ignore
    false
  } catch {
    ClientStop(message) =>
      message == "operation requires an explicit Local configuration"
  }
  assert_true(refused)
}

///|
test "CLI Checkpoint metadata compiles the original typed Host caller without Work or Store" {
  let caller : (
    @local_host.NativeLocalHostConnection,
    LocalHostSettings,
    @local_crypto.Library,
    String,
    @argparse.Matches,
  ) -> String raise ClientStop = local_checkpoint_metadata_lookup
  caller |> ignore
}
