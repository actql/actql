# Rust source interface reader

This private tool reads actual Rust syntax with the pinned `syn` parser. The
selected library entry comes from Cargo metadata. Out-of-line modules follow
Rust source module paths; test-only modules are excluded. Missing, ambiguous,
outside-root and unexpanded item-macro sources refuse instead of inventing an
interface. Source files are bounded and product modules are never executed.

The output uses the existing interface Owner coverage shape. Function argument
roles and full type signatures, struct/enum fields and import syntax come from
the parsed source, not a second handwritten ABI list. Types and syntax facts
remain source-only: actual Cargo compilation, generated binding freshness and
actual compiled Wasm validation supply separate evidence.
