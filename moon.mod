name = "actql/actql"

version = "0.0.1"

license = "Apache-2.0"

source = "src"

preferred_target = "js"

supported_targets = "+js+wasm+native"

// The pinned test linker chooses CJS before applying module flags. Keep the
// existing Node imports and import.meta boundary in one ESM artifact.

options(
  "link-flags": [ "-js-format", "esm" ],
)
