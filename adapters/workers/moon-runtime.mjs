// Build-time adaptation of one audited pinned builtin, not a global polyfill.
// The runtime's physical hash seed is supplied by its Host, never used as an
// identity, authorization token or replacement for canonical SHA-256.
import {parse} from 'acorn';
import {createHash} from 'node:crypto';
import {readFileSync, mkdirSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const entropyDeclaration = 'b726a2e5b8f133516e86e50677140d78b3e08831b242c0367dfe0fab13f1fd58';

export function walk(node, visit) {
  if (!node || typeof node !== 'object') return;
  if (typeof node.type === 'string') visit(node);
  for (const [key, value] of Object.entries(node)) {
    if (key === 'start' || key === 'end') continue;
    if (Array.isArray(value)) value.forEach(child => walk(child, visit));
    else if (value && typeof value === 'object') walk(value, visit);
  }
}

export function checkPureRuntime(source) {
  const ast = parse(source, {ecmaVersion:'latest', sourceType:'module'});
  const denied = new Set(['globalThis', 'fetch', 'process', 'require', 'crypto',
    'Date', 'performance', 'setTimeout', 'setInterval', 'WebSocket', 'XMLHttpRequest',
    'eval', 'Function', 'WebAssembly', 'console']);
  walk(ast, node => {
    if (node.type === 'ImportDeclaration' || node.type === 'ImportExpression') {
      throw new Error('GeneratedRuntimeImport');
    }
    if (node.type === 'Identifier' && denied.has(node.name)) throw new Error(`GeneratedRuntimeIO: ${node.name}`);
    if (node.type === 'MemberExpression' && node.object.name === 'Math' &&
        (node.property.name === 'random' || node.property.value === 'random')) {
      throw new Error('GeneratedRuntimeIO: Math.random');
    }
  });
}

export function explicitSeedRuntime(source) {
  const ast = parse(source, {ecmaVersion:'latest', sourceType:'module'});
  const exports = [], edits = [];
  let count = 0;
  for (const node of ast.body) {
    if (node.type === 'ExportNamedDeclaration') {
      if (node.source || node.declaration || node.specifiers.some(x => x.type !== 'ExportSpecifier')) {
        throw new Error('UnknownMoonExport');
      }
      exports.push(...node.specifiers.map(x => `${x.exported.name}: ${x.local.name}`));
      edits.push({start:node.start,end:node.end,text:''});
    } else if (node.type === 'VariableDeclaration' && node.declarations.some(x => x.id.name === '_M0FPB12random__seed')) {
      const digest = createHash('sha256').update(source.slice(node.start,node.end)).digest('hex');
      if (digest !== entropyDeclaration) throw new Error('UnauditedMoonEntropyBuiltin');
      count++;
      edits.push({start:node.start,end:node.end,text:'const _M0FPB12random__seed = () => hostHashSeed;'});
    }
  }
  if (count !== 1 || exports.length === 0) throw new Error('UnexpectedMoonRuntimeShape');
  for (const edit of edits.sort((a,b) => b.start-a.start)) {
    source = source.slice(0,edit.start)+edit.text+source.slice(edit.end);
  }
  checkPureRuntime(source);
  return `// Generated from pinned MoonBit output; explicit physical hash seed.\n` +
    `export function instantiate(hostHashSeed) {\n` +
    `if (!Number.isInteger(hostHashSeed) || hostHashSeed < -2147483648 || hostHashSeed > 2147483647) throw new TypeError('Invalid physical hash seed');\n` +
    source + `\nreturn Object.freeze({${exports.join(',')}});\n}\n`;
}

export function prepareRuntimeModules() {
  const root = fileURLToPath(new URL('../../',import.meta.url));
  const directory = `${root}_build/workers/modules`;
  mkdirSync(directory,{recursive:true});
  for (const [name,pkg] of [['bridge','connectors_workers_bridge'],['fixture','workers_conformance'],
    ['async_bridge','connectors_workers_async_bridge']]) {
    const source = readFileSync(`${root}_build/js/release/build/${pkg}/${pkg}.js`,'utf8');
    writeFileSync(`${directory}/${name}.mjs`,explicitSeedRuntime(source));
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) prepareRuntimeModules();
