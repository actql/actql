///|
fn required(matches : @argparse.Matches, name : String) -> String {
  match matches.values.get(name) {
    Some([value]) if !value.is_empty() => value
    _ => abort("missing or repeated option --" + name)
  }
}

///|
fn required_int(matches : @argparse.Matches, name : String) -> Int {
  @string.from_str(required(matches, name)) catch {
    _ => abort("invalid integer option --" + name)
  }
}

///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "actql-native-https-echo",
    about="Exercise the bounded native mTLS server adapter",
    version="0.1",
    options=[
      @argparse.OptionArg("host", default_values=["127.0.0.1"]),
      @argparse.OptionArg("port", default_values=["0"]),
      @argparse.OptionArg("cert", required=true),
      @argparse.OptionArg("key", required=true),
      @argparse.OptionArg("ca", required=true),
      @argparse.OptionArg("max-request-bytes", default_values=["4096"]),
      @argparse.OptionArg("max-response-bytes", default_values=["4096"]),
    ],
  )
}

///|
fn main {
  let matches = command().parse() catch { error => abort(error.to_string()) }
  let server = @https.open(
    required(matches, "host"),
    required_int(matches, "port"),
    required(matches, "cert"),
    required(matches, "key"),
    required(matches, "ca"),
    required_int(matches, "max-request-bytes"),
    required_int(matches, "max-response-bytes"),
    8,
  ).unwrap()
  println("{\"port\":" + server.port().to_string() + "}")
  let mut running = true
  while running {
    match server.poll(1000) {
      Ok(Some(request)) => {
        let route = request.path()
        if route == "/shutdown" {
          server
          .respond(request, 200, "application/json", b"{\"closed\":true}")
          .unwrap()
          running = false
        } else {
          let body = "{\"method\":\"" +
            request.request_method() +
            "\",\"path\":\"" +
            route +
            "\",\"body_bytes\":" +
            request.body().length().to_string() +
            ",\"peer\":\"" +
            request.peer_fingerprint() +
            "\"}"
          server
          .respond(request, 200, "application/json", @utf8.encode(body))
          .unwrap()
        }
      }
      Ok(None) => ()
      Err(_) => running = false
    }
  }
  if !server.close() {
    abort("native HTTPS server did not close")
  }
}
