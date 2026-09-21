///|
priv suberror CommandStop {
  CommandStop(String)
}

///|
fn[T] stop(message : String) -> T raise CommandStop {
  raise CommandStop(message)
}

///|
fn required(
  matches : @argparse.Matches,
  name : String,
) -> String raise CommandStop {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => value
    _ => stop("missing or repeated option --" + name)
  }
}

///|
fn files() -> @application.NativeRemoteApplicationFiles {
  {
    program: "program.json",
    environment: "environment.json",
    environment_cid: "environment.cid",
    parameters: "parameters.json",
    registry: "registry.json",
    values: "values.json",
    fragment: "fragment.json",
    query: "query.json",
    evidence: "evidence.json",
    two_receipt: "two-receipt.json",
  }
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "actql-native-remote-application-inspect",
    about="Inspect one checked native Remote application package",
    version="0.1",
    options=[
      @argparse.OptionArg("application-root", required=true),
      @argparse.OptionArg("database-schema", default_values=["main"]),
      @argparse.OptionArg("table", default_values=["records"]),
      @argparse.OptionArg("max-file-bytes", default_values=["1048576"]),
    ],
  )
}

///|
fn execute_checked(matches : @argparse.Matches) -> Unit raise CommandStop {
  let max_file_bytes : Int64 = @string.from_str(
    required(matches, "max-file-bytes"),
  ) catch {
    _ => stop("invalid integer option --max-file-bytes")
  }
  if max_file_bytes < 1L {
    stop("invalid application limits")
  }
  let app = match
    @application.load_native_remote_application(
      required(matches, "application-root"),
      files(),
      max_file_bytes,
      required(matches, "database-schema"),
      required(matches, "table"),
    ) {
    Ok(value) => value
    Err(_) => stop("application admission failed")
  }
  println(
    "{\"program_definition_cid\":\"" +
    @application.native_remote_application_program_definition_cid(app) +
    "\",\"task_count\":" +
    @application.native_remote_application_task_count(app).to_string() +
    "}",
  )
}

///|
fn main {
  let matches = command().parse() catch { error => abort(error.to_string()) }
  execute_checked(matches) catch {
    CommandStop(issue) =>
      abort("actql-native-remote-application-inspect: " + issue)
  }
}
