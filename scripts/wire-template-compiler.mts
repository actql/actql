import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import ts from 'typescript';

const configuration = fileURLToPath(new URL('../tsconfig.tooling.json', import.meta.url));
const marker = '/* @wire-bindings */';
const structural = fileURLToPath(new URL('./templates/structural-wire-validator.mts', import.meta.url));

const diagnosticHost: ts.FormatDiagnosticsHost = {
  getCanonicalFileName: name => name,
  getCurrentDirectory: ts.sys.getCurrentDirectory,
  getNewLine: () => '\n',
};

export function compileWireTemplate(
  name: string,
  bindings: string,
  header: string,
  predicates?: ReadonlyArray<Readonly<{name: string; type: string; schema: string}>>,
) {
  const template = fileURLToPath(new URL(`./templates/${name}.mts`, import.meta.url));
  const pieces = readFileSync(template, 'utf8').split(marker);
  if (pieces.length !== 2) throw new Error(`InvalidWireTemplate:${name}`);
  const [shared, standaloneExport, ...rest] = readFileSync(structural, 'utf8').split('/* @wire-validator-export */');
  if (standaloneExport === undefined || rest.length) throw new Error('InvalidStructuralWireTemplate');
  let materialized = pieces.join(shared + '\n' + bindings);
  if (predicates !== undefined) {
    const parts = materialized.split('/* @wire-predicates */');
    if (parts.length !== 2) throw new Error(`MissingWirePredicates:${name}`);
    const functions = predicates.map(({name, type, schema}) =>
      `export function ${name}(value: unknown): value is ${type} {\n` +
      `  return valid(value, schemas[${JSON.stringify(schema)}]);\n}\n`);
    materialized = parts.join(functions.join('\n'));
  }

  const diagnostics: ts.Diagnostic[] = [];
  const config = ts.getParsedCommandLineOfConfigFile(configuration, {}, {...ts.sys,
    onUnRecoverableConfigFileDiagnostic: value => diagnostics.push(value)});
  if (config === undefined || diagnostics.length || config.errors.length) {
    throw new Error(`InvalidWireCompilerOptions: ${ts.formatDiagnostics(diagnostics.concat(config?.errors ?? []), diagnosticHost)}`);
  }
  const options: ts.CompilerOptions = {...config.options, types: [], declaration: true, noEmitOnError: true};
  const host = ts.createCompilerHost(options);
  const getSource = host.getSourceFile;
  host.getSourceFile = (path, target, onError, forceNew) => path === template
    ? ts.createSourceFile(template, materialized, target, true)
    : getSource(path, target, onError, forceNew);
  const program = ts.createProgram([template], options, host);
  const entry = program.getSourceFile(template);
  if (entry === undefined) throw new Error(`MissingWireTemplate:${name}`);
  const outputs = new Map<string, string>();
  const result = program.emit(entry, (path, content) => outputs.set(path, content));
  if (result.emitSkipped || result.diagnostics.length) {
    throw new Error(`InvalidWireTemplate:${name}\n${ts.formatDiagnostics(result.diagnostics, diagnosticHost)}`);
  }
  const module = outputs.get(template.replace(/\.mts$/u, '.mjs'));
  const declarations = outputs.get(template.replace(/\.mts$/u, '.d.mts'));
  if (outputs.size !== 2 || module === undefined || declarations === undefined) {
    throw new Error(`IncompleteWireTemplateEmit:${name}`);
  }
  return {module: header + module, types: header + declarations};
}
