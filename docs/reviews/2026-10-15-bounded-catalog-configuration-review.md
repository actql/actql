# Bounded catalog package configuration review

The sole package-option change introduced by `202aed1b7f33bb825d8b5c3e9c313a80f04d6f7f` from its actual parent `c0834dc952fc3ffc11908b782331c0eeddb17dad` adds the Native-only `bounded_catalog_current_native_wbtest.mbt` selector. Imports, other selectors, linker settings and the selected toolchain are unchanged.

The exact manifest digest changes from `3261be3fb00a789680d76f5304bf1bff98d3db4e7d904d45fd50a05205c955fe` to `4a6441d96a441ac67adf1f38d806ae59bf4936217faf2b8269310f2e500aac00`. Update the existing finite JS configuration review rather than admitting an arbitrary package language. Every direct source member and dependency remains an input. Tests preserve the original manifest and reject its old digest, changed imports or selectors, unknown options, foreign paths, targets and toolchains.

This configuration review does not execute Native code or establish a new physical funding profile. The source-qualified real SQLite two-case run and Native Host caller compilation remain the PR's original evidence. Installed Cloud Effect acceptance is unfinished.

The previously registered pin `e18d68c466e76cdc2fd81395df80fdfbdb86e13627c89110339d54503a6650fd` already differs from the actual parent manifest. Keep that prior pin refused as well; the actual introduction comparison uses its genuine parent bytes, not a guessed preimage.
