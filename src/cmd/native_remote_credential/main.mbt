///|
fn option(matches : @argparse.Matches, name : String) -> Result[String, String] {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => Ok(value)
    _ => Err("missing or repeated option --" + name)
  }
}

///|
fn parse_int(value : String, name : String) -> Result[Int, String] {
  let parsed : Int = @string.from_str(value) catch {
    _ => return Err("invalid integer option --" + name)
  }
  Ok(parsed)
}

///|
fn parse_int64(value : String, name : String) -> Result[Int64, String] {
  let parsed : Int64 = @string.from_str(value) catch {
    _ => return Err("invalid integer option --" + name)
  }
  Ok(parsed)
}

///|
fn read_text(
  root : String,
  name : String,
  max_bytes : Int64,
  trim_newline : Bool,
) -> Result[String, String] {
  @bounded_files.read_bounded_text_file(root, name, max_bytes, trim_newline~).map_err(_ => {
      "failed to read " + name
    },
  )
}

///|
priv suberror CommandStop {
  CommandStop(String)
}

///|
fn[T] checked(value : Result[T, String]) -> T raise CommandStop {
  match value {
    Ok(result) => result
    Err(issue) => raise CommandStop(issue)
  }
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "actql-native-remote-credential",
    about="Use or reconcile one signed remote credential grant",
    version="0.1",
    subcommand_required=true,
    options=[
      @argparse.OptionArg("sqlite-library", required=true, global=true),
      @argparse.OptionArg("crypto-library", required=true, global=true),
      @argparse.OptionArg("http-library", required=true, global=true),
      @argparse.OptionArg("journal", required=true, global=true),
      @argparse.OptionArg("input-root", required=true, global=true),
      @argparse.OptionArg("grant-body-file", required=true, global=true),
      @argparse.OptionArg("signature-file", required=true, global=true),
      @argparse.OptionArg("public-key-file", required=true, global=true),
      @argparse.OptionArg("grant-cid", required=true, global=true),
      @argparse.OptionArg("key-id", required=true, global=true),
      @argparse.OptionArg("issuer-authority", required=true, global=true),
      @argparse.OptionArg("ca", required=true, global=true),
      @argparse.OptionArg("cert", required=true, global=true),
      @argparse.OptionArg("key", required=true, global=true),
      @argparse.OptionArg("secret-file", required=true, global=true),
      @argparse.OptionArg("resource-origin", required=true, global=true),
      @argparse.OptionArg("resource-path", required=true, global=true),
      @argparse.OptionArg("operation", required=true, global=true),
      @argparse.OptionArg("principal", required=true, global=true),
      @argparse.OptionArg("tenant", required=true, global=true),
      @argparse.OptionArg("environment", required=true, global=true),
      @argparse.OptionArg("site-key", required=true, global=true),
      @argparse.OptionArg("site-generation", required=true, global=true),
      @argparse.OptionArg("runtime-bundle-cid", required=true, global=true),
      @argparse.OptionArg("connector-registration", required=true, global=true),
      @argparse.OptionArg("connector-revision", required=true, global=true),
      @argparse.OptionArg("run-invocation-cid", required=true, global=true),
      @argparse.OptionArg("task-attempt", required=true, global=true),
      @argparse.OptionArg("dispatch-request-cid", required=true, global=true),
      @argparse.OptionArg("use-id", required=true, global=true),
      @argparse.OptionArg(
        "max-record-bytes",
        default_values=["65536"],
        global=true,
      ),
      @argparse.OptionArg(
        "max-response-bytes",
        default_values=["1048576"],
        global=true,
      ),
    ],
    subcommands=[
      @argparse.Command("call", options=[
        @argparse.OptionArg("trusted-now-unix-ms", required=true),
      ]),
      @argparse.Command("query"),
      @argparse.Command("revoke", options=[
        @argparse.OptionArg("confirmation", required=true),
      ]),
    ],
  )
}

///|
fn execute_checked(matches : @argparse.Matches) -> String raise CommandStop {
  let sqlite_path = checked(option(matches, "sqlite-library"))
  let crypto_path = checked(option(matches, "crypto-library"))
  let http_path = checked(option(matches, "http-library"))
  let journal = checked(option(matches, "journal"))
  let input_root = checked(option(matches, "input-root"))
  let max_record_bytes = checked(
    parse_int64(
      checked(option(matches, "max-record-bytes")),
      "max-record-bytes",
    ),
  )
  let max_response_bytes = checked(
    parse_int64(
      checked(option(matches, "max-response-bytes")),
      "max-response-bytes",
    ),
  )
  if max_record_bytes < 1L || max_response_bytes < 1L {
    raise CommandStop("invalid credential resource limits")
  }
  let grant_body = checked(
    read_text(
      input_root,
      checked(option(matches, "grant-body-file")),
      max_record_bytes,
      false,
    ),
  )
  let signature = checked(
    read_text(
      input_root,
      checked(option(matches, "signature-file")),
      4096L,
      true,
    ),
  )
  let public_key = checked(
    read_text(
      input_root,
      checked(option(matches, "public-key-file")),
      16384L,
      false,
    ),
  )
  let key_id = checked(option(matches, "key-id"))
  let issuer_authority = checked(option(matches, "issuer-authority"))
  let envelope = match
    @credential.admit_credential_signature_envelope(
      "actql-remote-credential-grant-signature/0.1",
      key_id,
      checked(option(matches, "grant-cid")),
      grant_body,
      signature,
    ) {
    Ok(value) => value
    Err(_) => raise CommandStop("credential signature envelope rejected")
  }
  let signature_library = match @signature.load_library(crypto_path) {
    Ok(value) => value
    Err(_) => raise CommandStop("crypto library load failed")
  }
  let grant = match
    @resource.admit_signed_native_credential_grant(
      signature_library,
      envelope,
      [
        {
          issuer_authority,
          key_id,
          public_key_pem: public_key,
          admit_new_grants: true,
        },
      ],
    ) {
    Ok(value) => value
    Err(_) => raise CommandStop("credential grant rejected")
  }
  let sqlite_library = match @sqlite.load_library(sqlite_path) {
    Ok(value) => value
    Err(_) => raise CommandStop("SQLite library load failed")
  }
  let database = match sqlite_library.open_database(journal, max_record_bytes) {
    Ok(value) => value
    Err(_) => raise CommandStop("credential journal open failed")
  }
  let http_library = match @http.load_library(http_path) {
    Ok(value) => value
    Err(_) => {
      database.close()
      raise CommandStop("HTTP library load failed")
    }
  }
  let client = match
    http_library.create_client(
      checked(option(matches, "ca")),
      checked(option(matches, "cert")),
      checked(option(matches, "key")),
      max_response_bytes,
      2000,
      30000,
    ) {
    Ok(value) => value
    Err(_) => {
      database.close()
      raise CommandStop("HTTP client creation failed")
    }
  }
  let origin = checked(option(matches, "resource-origin"))
  let operation = checked(option(matches, "operation"))
  let service = match
    @resource.install_native_credential_resource_service(
      database,
      client,
      [
        {
          resource_origin: origin,
          operation,
          path: checked(option(matches, "resource-path")),
          secret_path: checked(option(matches, "secret-file")),
        },
      ],
      _ => true,
    ) {
    Ok(value) => value
    Err(_) => {
      ignore(client.close())
      database.close()
      raise CommandStop("credential service installation failed")
    }
  }
  let scope : @resource.NativeCredentialScope = {
    principal: checked(option(matches, "principal")),
    tenant: checked(option(matches, "tenant")),
    environment: checked(option(matches, "environment")),
    site_key: checked(option(matches, "site-key")),
    site_generation: checked(
      parse_int(checked(option(matches, "site-generation")), "site-generation"),
    ),
    runtime_bundle_cid: checked(option(matches, "runtime-bundle-cid")),
    connector_registration: checked(option(matches, "connector-registration")),
    connector_revision: checked(option(matches, "connector-revision")),
    resource_origin: origin,
    operation,
    run_invocation_cid: checked(option(matches, "run-invocation-cid")),
    task_attempt: checked(
      parse_int(checked(option(matches, "task-attempt")), "task-attempt"),
    ),
    dispatch_request_cid: checked(option(matches, "dispatch-request-cid")),
  }
  let use_id = checked(option(matches, "use-id"))
  let result : Result[String, String] = match matches.subcommand {
    Some(("call", child)) => {
      let trusted_now = checked(
        parse_int64(
          checked(option(child, "trusted-now-unix-ms")),
          "trusted-now-unix-ms",
        ),
      )
      match
        @resource.call_native_credential_resource(
          service, grant, use_id, trusted_now, scope,
        ) {
        Ok(response) =>
          Ok(
            "{\"outcome\":\"succeeded\",\"status\":" +
            response.status.to_string() +
            ",\"use_cid\":\"" +
            response.use_cid +
            "\"}",
          )
        Err(_) => Err("credential resource call failed")
      }
    }
    Some(("query", _)) =>
      match
        @resource.query_native_credential_use(service, grant, use_id, scope) {
        Ok(status) =>
          Ok(
            "{\"outcome\":\"" +
            status.outcome +
            "\",\"status\":" +
            status.status.map(value => value.to_string()).unwrap_or("null") +
            ",\"use_cid\":\"" +
            status.use_cid +
            "\"}",
          )
        Err(_) => Err("credential resource query failed")
      }
    Some(("revoke", child)) =>
      if checked(option(child, "confirmation")) != "revoke-signed-grant" {
        Err("credential revocation confirmation rejected")
      } else {
        match @resource.revoke_native_credential_grant(service, grant) {
          Ok(_) => Ok("{\"revoked\":true}")
          Err(_) => Err("credential grant revocation failed")
        }
      }
    Some((name, _)) => Err("unsupported operation " + name)
    None => Err("missing credential operation")
  }
  let client_closed = client.close()
  database.close()
  if !client_closed {
    match result {
      Ok(_) => raise CommandStop("credential HTTP client close failed")
      Err(issue) =>
        raise CommandStop(issue + "; credential HTTP client close failed")
    }
  }
  checked(result)
}

///|
fn execute(matches : @argparse.Matches) -> Result[String, String] {
  Ok(execute_checked(matches)) catch {
    CommandStop(issue) => Err(issue)
  }
}

///|
fn main {
  let matches = command().parse() catch { error => abort(error.to_string()) }
  match execute(matches) {
    Ok(value) => println(value)
    Err(issue) => abort("actql-native-remote-credential: " + issue)
  }
}
