import {fileURLToPath} from 'node:url';
import ts from 'typescript';

// Shared only by the existing private interface generators. Compile original
// authored input before publishing either runtime or declarations; no ignored
// emit, Source approval, runtime payload or serialized proof is accepted.
export function emitInterfaceTypeScript(root: URL, authored: URL, virtualText?: string): ReadonlyMap<string, string> {
  // Compile the authored source once. Both runtime copies and declarations come
  // from the same strict project options; ignored bootstrap emit is not input.
  const directory = fileURLToPath(root);
  const config = ts.readConfigFile(fileURLToPath(new URL('tsconfig.base.json', root)), ts.sys.readFile);
  const converted = ts.convertCompilerOptionsFromJson(config.config?.compilerOptions ?? {}, directory);
  const options: ts.CompilerOptions = {...converted.options, declaration: true, types: []};
  const source = fileURLToPath(authored);
  const host = ts.createCompilerHost(options);
  if (virtualText !== undefined) {
    const read = host.readFile, exists = host.fileExists, getSource = host.getSourceFile;
    host.readFile = path => path === source ? virtualText : read(path);
    host.fileExists = path => path === source || exists(path);
    host.getSourceFile = (path, languageVersion, onError, shouldCreateNewSourceFile) => path === source
      ? ts.createSourceFile(source, virtualText, languageVersion, true, ts.ScriptKind.TS)
      : getSource(path, languageVersion, onError, shouldCreateNewSourceFile);
  }
  const program = ts.createProgram([source], options, host);
  const outputs = new Map<string, string>();
  const diagnostics = [...(config.error ? [config.error] : []), ...converted.errors,
    ...ts.getPreEmitDiagnostics(program)];
  if (!diagnostics.length) {
    const original = program.getSourceFile(source);
    if (!original) throw new Error('Missing authored original interface');
    const emitted = program.emit(original, (path, text) => {
      if (path.endsWith('.mjs')) outputs.set('.mjs', text);
      if (path.endsWith('.d.mts')) outputs.set('.d.mts', text);
    });
    diagnostics.push(...emitted.diagnostics);
  }
  if (diagnostics.length) throw new Error(ts.formatDiagnostics(diagnostics, {
    getCanonicalFileName: path => path,
    getCurrentDirectory: () => directory,
    getNewLine: () => '\n',
  }));
  if (outputs.size !== 2) throw new Error('Missing original interface emit');
  return outputs;
}
