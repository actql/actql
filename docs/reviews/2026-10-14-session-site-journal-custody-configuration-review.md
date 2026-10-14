# Native Site Journal custody configuration review

The exact reviewed package is `src/platform_native/remote_journal/moon.pkg`.
This review follows the existing
`literal-native-options-with-bound-source-membership` rule.

The reviewed Source is `813dfbbd867bc83958c1d4d069061a4aabace1f3`, normally adopting accepted main
`de84b1a69e334743193eb144a56b852fe363707a` while retaining author
`845e594b392b59dede9d18b77e1931c564a458db`. The manifest SHA256 is
`c83f1565e76f17043331ef9220ad6e0811f5699a0b537f13e3280aed857c8b9f`, Git blob
`dbac2c94f4fde193d019ae7fb73bd600f4f12c5a`, mode `100644`.

The only manifest addition relative to the accepted main package is the literal
Native predicate for `open_close_custody_native_wbtest.mbt`. Normal and WB imports,
other predicates, Native stub/linker options and supported targets are unchanged.
The selected configuration remains a JS source-membership review, not Native
execution or OS-loader acceptance. Unknown options/paths/digests, wrong targets
and wrong toolchain identity still refuse through the unchanged function.

The earlier filesystem, transfer-journal and HTTP review references and hashes
are retained. This registration changes only the Site Journal digest. No
Runtime Bundle child predicate is adopted here. Physical original-handle
cleanup cases and compiler evidence are recorded separately from configuration
identity. Numeric funding, new authority and public Effect acceptance remain
unadopted.
