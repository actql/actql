# Third-party notices

## ELK.js 0.12.0

The layout Worker includes ELK.js 0.12.0. Copyright (c) Kiel University and
contributors. This distribution uses ELK.js under the Eclipse Public License
2.0; the complete upstream license is in [ELKJS-LICENSE.md](ELKJS-LICENSE.md).
The ActQL wrapper's repository license does not relicense ELK.js.

The ELK.js source is available from its [0.12.0 release](https://github.com/kieler/elkjs/releases/tag/0.12.0)
and [source tree](https://github.com/kieler/elkjs/tree/0.12.0), including its
build instructions and the linked Eclipse Layout Kernel sources. The exact
npm package is [elkjs-0.12.0.tgz](https://registry.npmjs.org/elkjs/-/elkjs-0.12.0.tgz).
ELK.js is bundled without source modifications. ActQL's separate Worker and
position-only adapter are provided with this package's source.

## XYFlow

The Explorer build uses `@xyflow/react` 12.12.0 and `@xyflow/system` 0.0.83
under the MIT License, Copyright (c) 2019–2025 webkid GmbH. Their license
files are included in the
[React npm archive](https://registry.npmjs.org/@xyflow/react/-/react-12.12.0.tgz)
and [System npm archive](https://registry.npmjs.org/@xyflow/system/-/system-0.0.83.tgz).

The required `npm run check:explorer-types` command prepares the local
ESM and UMD copies of the System `nodes.d.ts` declaration for
`exactOptionalPropertyTypes`. It checks the pinned package lock and original
declaration digests, then makes `InternalNodeBase` retain the base node shape
without widening the public `NodeBase` optional properties. The JavaScript
and CSS are unchanged. See [the upstream declaration issue](https://github.com/xyflow/xyflow/issues/6038).
