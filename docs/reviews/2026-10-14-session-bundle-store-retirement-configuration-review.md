# Native Bundle Store checked retirement configuration review

The exact reviewed package is `src/platform_native/runtime_bundle/moon.pkg`.
This review follows the existing
`literal-native-options-with-bound-source-membership` rule.

The reviewed Source is `3394415cce52fd7bda837ded134c2bb383ec4842`, preserving original author
`edb4863dd089decbd49662465dcbf92d26f619ff` and the normally adopted
Site Journal dependency. The manifest SHA256 is
`e18d68c466e76cdc2fd81395df80fdfbdb86e13627c89110339d54503a6650fd`, Git blob
`6e89384bc19a6d2a701f6f4212c0022c138b89d9`, mode `100644`.

The only manifest addition relative to accepted main
`de84b1a69e334743193eb144a56b852fe363707a` is the literal Native predicate
for `store_checked_close_native_wbtest.mbt`. Normal/WB imports, all other
predicates and supported targets are unchanged. This package adds no Native
stub or linker option. The selected configuration remains a JS source-membership
review, not a Native execution or OS-loader assertion.

All accepted filesystem, transfer-journal, HTTP and Site Journal review
references and digests remain. This unit changes only the Bundle Store digest.
Unknown configuration/target/toolchain requests retain the existing refusal
function. Physical same-handle checked retirement, durable holds, reservations,
compiler evidence and OS inputs are separately verified. This registration
issues no cleanup acknowledgement, authority, funding or public Effect witness.
