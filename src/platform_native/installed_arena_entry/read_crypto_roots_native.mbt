///|
// Code registration only. Matching regular C emission establishes the private
// callback ABI before linking; no component, profile or scope is initialized.
extern "C" fn register_read_crypto_roots(
  prepare : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaLocalHostResources,
      @control.InstalledArenaOriginalRead,
    ) -> @control.InstalledArenaReadCryptoReply,
  ],
  load : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaLocalHostResources,
      @control.InstalledArenaOriginalRead,
      @control.InstalledArenaCryptoComponent,
      String,
      Int64,
      Int,
    ) -> @control.InstalledArenaReadCryptoReply,
  ],
  open_library : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaLocalHostResources,
      @control.InstalledArenaOriginalRead,
      @control.InstalledArenaCryptoComponent,
    ) -> @control.InstalledArenaReadCryptoReply,
  ],
  close_library : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaLocalHostResources,
      @control.InstalledArenaOriginalRead,
      @control.InstalledArenaCryptoComponent,
      @signature.Library,
    ) -> @control.InstalledArenaReadCryptoReply,
  ],
  close_component : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaLocalHostResources,
      @control.InstalledArenaOriginalRead,
      @control.InstalledArenaCryptoComponent,
    ) -> @control.InstalledArenaReadCryptoReply,
  ],
  hmac : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaLocalHostResources,
      @control.InstalledArenaOriginalRead,
      @control.InstalledArenaCryptoComponent,
      @signature.Library,
      Bytes,
      Bytes,
    ) -> @control.InstalledArenaReadCryptoReply,
  ],
  verify : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaLocalHostResources,
      @control.InstalledArenaOriginalRead,
      @control.InstalledArenaCryptoComponent,
      @signature.Library,
      Bytes,
      Bytes,
      Bytes,
    ) -> @control.InstalledArenaReadCryptoReply,
  ],
  host : FuncRef[
    (@control.InstalledArenaReadCryptoReply) -> @control.InstalledArenaHost,
  ],
  pair : FuncRef[
    (@control.InstalledArenaReadCryptoReply) -> @control.InstalledArenaLocalHostResources,
  ],
  read : FuncRef[
    (@control.InstalledArenaReadCryptoReply) -> @control.InstalledArenaOriginalRead,
  ],
  component : FuncRef[
    (@control.InstalledArenaReadCryptoReply) -> @control.InstalledArenaCryptoComponent?,
  ],
  library : FuncRef[
    (@control.InstalledArenaReadCryptoReply) -> @signature.Library?,
  ],
  operation : FuncRef[(@control.InstalledArenaReadCryptoReply) -> Int],
  origin : FuncRef[(@control.InstalledArenaReadCryptoReply) -> Int],
  family : FuncRef[(@control.InstalledArenaReadCryptoReply) -> Int],
  closed : FuncRef[(@control.InstalledArenaReadCryptoReply) -> Bool],
  length : FuncRef[(@control.InstalledArenaReadCryptoReply) -> Int],
  verified : FuncRef[(@control.InstalledArenaReadCryptoReply) -> Int],
  byte : FuncRef[(@control.InstalledArenaReadCryptoReply, Int) -> Int],
  current : FuncRef[
    (
      @control.InstalledArenaHost,
      @control.InstalledArenaLocalHostResources,
      @control.InstalledArenaOriginalRead,
      @control.InstalledArenaCryptoComponent,
    ) -> Bool,
  ],
) -> Unit = "actql_native_control_register_read_crypto_roots"

///|
fn register_original_read_crypto_roots() -> Unit {
  register_read_crypto_roots(
    fn(host, pair, read) {
      @control.prepare_installed_arena_read_crypto_reply(host, pair, read)
    },
    fn(host, pair, read, component, path, heap, diagnostic) {
      @control.load_installed_arena_read_crypto_reply(
        host, pair, read, component, path, heap, diagnostic,
      )
    },
    fn(host, pair, read, component) {
      @control.open_installed_arena_read_crypto_library_reply(
        host, pair, read, component,
      )
    },
    fn(host, pair, read, component, library) {
      @control.close_installed_arena_read_crypto_library_reply(
        host, pair, read, component, library,
      )
    },
    fn(host, pair, read, component) {
      @control.close_installed_arena_read_crypto_reply(
        host, pair, read, component,
      )
    },
    fn(host, pair, read, component, library, key, data) {
      @control.hmac_installed_arena_read_crypto_reply(
        host, pair, read, component, library, key, data,
      )
    },
    fn(host, pair, read, component, library, key, data, signature) {
      @control.verify_hmac_installed_arena_read_crypto_reply(
        host, pair, read, component, library, key, data, signature,
      )
    },
    fn(reply) { reply.original_host() },
    fn(reply) { reply.original_resources() },
    fn(reply) { reply.original_read() },
    fn(reply) { reply.original_component() },
    fn(reply) { reply.original_library() },
    fn(reply) { reply.operation_tag() },
    fn(reply) { reply.issue_origin() },
    fn(reply) { reply.issue_family() },
    fn(reply) { reply.close_confirmed() },
    fn(reply) { reply.output_length() },
    fn(reply) { reply.verification() },
    fn(reply, index) { reply.output_byte(index) },
    fn(host, pair, read, component) {
      @control.current_installed_arena_read_crypto_original(
        host, pair, read, component,
      )
    },
  )
}
