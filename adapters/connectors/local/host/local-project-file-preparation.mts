// Capture the existing Local Project preparation helpers at the Host entry.
// Only the original Project connection and declaration owners supply runtime values.
import {dirname, resolve} from 'node:path';
import {installedProjectOriginalsForRuntime} from '../../../host-node/installed-project-configuration.mjs';
import {loadInstalledProjectConnections} from '../../../host-node/installed-project-connections.mjs';
import {restoreDeclaration} from './local-file-store-declaration.mjs';
import {prepareLocalCsvTable, projectLocalCsvRelationView, type LocalCsvDeclarationRuntime, type PreparedLocalCsvTable} from './local-csv-table.mjs';

type OriginalCalls = Readonly<{
  clientProjectConnectionsCount(connections: unknown): number;
  clientProjectConnectionsName(connections: unknown, index: number): unknown;
  clientProjectConnectionsConnector(connections: unknown, index: number): unknown;
  clientProjectConnectionsEntryOriginalJson(connections: unknown, index: number): unknown;
  clientProgramRowSourceRestoreRelationDeclaration(connection: string, registration: string, revision: string,
    viewsWire: string, expectedCatalogCid: undefined): unknown;
  clientProgramRowSourceDeclarationJson(original: unknown): string;
}>;
type Runtime = NonNullable<Parameters<typeof loadInstalledProjectConnections>[0]> & Partial<OriginalCalls & LocalCsvDeclarationRuntime>;
type Project = Parameters<typeof loadInstalledProjectConnections>[1];
type ConnectionView = Awaited<ReturnType<typeof loadInstalledProjectConnections>>;
type ConnectionOriginal = ReturnType<ConnectionView['originalsForRuntime']>;
type ProjectOriginal = ReturnType<typeof installedProjectOriginalsForRuntime>;
type ConnectionEntry = Readonly<{connector?: unknown; root?: unknown; version?: unknown; tables?: Record<string, Readonly<{format?: unknown; path?: unknown; columns?: unknown; key?: unknown}> | null>}>;
type Options = Readonly<{assertCurrent?: () => unknown; limits?: unknown; openFile?: unknown}>;
type Helpers = Readonly<{
  fail(code: string): never; canonical(value: unknown): string; cid(value: unknown): string;
  positive(value: number): boolean; text(value: unknown, maximum: number): value is string;
}>;
type FileSource = ReturnType<typeof restoreDeclaration> & Readonly<{
  connection: string; connectorId: string; registration: 'local'; revision: 'local/0.1';
  originalEntryWire: string; rootPath: string; versionMode: 'content' | 'metadata'; limits: LocalLimits;
  tables: readonly PreparedLocalCsvTable[];
  csvTransports: Readonly<Record<string, PreparedLocalCsvTable['transport']>>;
  queryAliases: readonly Readonly<{name: string; resource: string}>[];
}>;
type LocalProjectOriginal = Readonly<{project: ProjectOriginal; connections: ConnectionOriginal; sources: readonly FileSource[]; realizationKey: 'installed-multi-acquired'}>;
type PreparedLocalProject = Readonly<{
  originalsForRuntime(runtime: unknown): LocalProjectOriginal;
  retire(runtime: unknown): void;
}>;

const limitNames = ['maxEntries','maxDepth','maxPathBytes','maxFiles','maxFileBytes','maxReadBytes',
  'maxPages','maxPageBytes','maxPageRows','maxAttempts','maxDurationMs','maxListingBytes'] as const;
type LocalLimits = Readonly<Record<typeof limitNames[number], number>>;

export function bindLocalProjectFilePreparation({fail: refuse,canonical,cid,positive,text: isText}: Helpers) {
  const fail: Helpers['fail'] = refuse;
  const text: Helpers['text'] = isText;
  function ownLimits(input: unknown): LocalLimits {
    const fields: Record<string, PropertyDescriptor> = input !== null && typeof input === 'object' ? Object.getOwnPropertyDescriptors(input) : {};
    if (Reflect.ownKeys(fields).length !== limitNames.length ||
        limitNames.some(name => !Object.hasOwn(fields[name] ?? {}, 'value'))) fail('LocalFilesLimitsUnavailable');
    const value = Object.freeze(Object.fromEntries(limitNames.map(name => [name, fields[name].value]))) as LocalLimits;
    if (limitNames.filter(name => name !== 'maxFileBytes').some(name => !positive(value[name])) ||
        !Number.isSafeInteger(value.maxFileBytes) || value.maxFileBytes < 0 ||
        value.maxEntries > 100000 || value.maxDepth > 128 || value.maxPathBytes > 4096 ||
        value.maxFiles > value.maxEntries || value.maxReadBytes < value.maxFileBytes ||
        value.maxAttempts < value.maxPages || value.maxPageRows > value.maxFiles) fail('LocalFilesLimitsUnavailable');
    return value;
  }
  // Same original Project/connection declaration, before Root acquisition.
  // Prepare only the shipped file/content and declared CSV read views here.
  return async function prepareInstalledProjectLocalFiles(moon: Runtime | null | undefined, project: Project | undefined,
    {assertCurrent, limits, openFile}: Options = {}): Promise<PreparedLocalProject | undefined> {
    if (project === undefined) return undefined;
    if (typeof assertCurrent !== 'function') fail('InvalidLocalFilesPreparation');
    const projectOriginal = installedProjectOriginalsForRuntime(project,moon);
    const ports = Object.freeze(Object.fromEntries((['clientProjectConnectionsCount',
      'clientProjectConnectionsName','clientProjectConnectionsConnector','clientProjectConnectionsEntryOriginalJson',
      'clientProgramRowSourceRestoreRelationDeclaration','clientProgramRowSourceDeclarationJson'] as const).map(name=>{
      const method=moon?.[name];if(typeof method!=='function')fail('LocalFilesRuntimeUnavailable');return[name,method];
    })) as Partial<OriginalCalls>);
    let retired = false, connections: ConnectionView | undefined, original: ConnectionOriginal | undefined,
      bundle: LocalProjectOriginal | undefined, view: PreparedLocalProject | undefined;
    const call = <Name extends keyof OriginalCalls>(name: Name,...args: Parameters<OriginalCalls[Name]>) =>
      Reflect.apply(ports[name] as (...args: Parameters<OriginalCalls[Name]>) => ReturnType<OriginalCalls[Name]>,moon,args);
    const current = () => {
      if(retired)fail('LocalFilesPreparationRetired');
      assertCurrent();
      if(installedProjectOriginalsForRuntime(project,moon)!==projectOriginal) fail('ForeignLocalFilesPreparation');
    };
    current();
    connections=await loadInstalledProjectConnections(moon,project,
      {assertCurrent:current,...(openFile===undefined?{}:{openFile})});
    original=connections.originalsForRuntime(moon);
    current();
    const selected=original.connections;
    if(selected===undefined)return undefined;
    const count=call('clientProjectConnectionsCount',selected);
    if(!Number.isSafeInteger(count)||count<0||count>128)fail('LocalFilesConnectionCountUnavailable');
    const sources: FileSource[]=[];
    let selectedLimits: LocalLimits | undefined;
    for(let index=0;index<count;index++){
      if(call('clientProjectConnectionsConnector',selected,index)!=='local')continue;
      selectedLimits??=ownLimits(limits);
      const connection=call('clientProjectConnectionsName',selected,index);
      const wire=call('clientProjectConnectionsEntryOriginalJson',selected,index);
      if(!text(connection,128)||typeof wire!=='string')fail('InvalidLocalFilesConnection');
      const entry=JSON.parse(wire) as ConnectionEntry | null;
      if(entry?.connector!=='local'||!text(entry.root,4096))fail('InvalidLocalFilesConnection');
      if(entry.version!==undefined&&entry.version!=='content')fail('LocalFilesVersionUnavailable');
      const rootPath=resolve(dirname(original.path!),entry.root);
      if(!text(rootPath,4096))fail('InvalidLocalFilesConnection');
      const versionMode=entry.version==='content'?'content':'metadata';
      const tables: PreparedLocalCsvTable[]=[];
      for(const [resource,table] of Object.entries(entry.tables??{})){
        if(table?.format!=='csv'&&(table?.format!==undefined||typeof table?.path!=='string'||!table.path.endsWith('.csv')))continue;
        if(!text(resource,128)||['files','contents'].includes(resource))fail('InvalidLocalCsvResource');
        tables.push(prepareLocalCsvTable(resource,table!,selectedLimits));
      }
      const csvViews=tables.map(table=>projectLocalCsvRelationView(moon!,table));
      const declared=restoreDeclaration(call,connection,rootPath,versionMode,selectedLimits,canonical,cid,csvViews);
      const {views}=JSON.parse(declared.wire) as {views: readonly {source_ref: string; resource: string}[]};
      const csvTransports=Object.freeze(Object.fromEntries(views.flatMap(view=>{
        const table=tables.find(table=>table.resource===view.resource);
        return table===undefined?[]:[[view.source_ref,table.transport] as const];
      })));
      sources.push(Object.freeze({connection,connectorId:connection,registration:'local',revision:'local/0.1',
        originalEntryWire:wire,rootPath,versionMode,limits:selectedLimits,tables:Object.freeze(tables),csvTransports,
        queryAliases:Object.freeze([{name:connection,resource:'files'},
          {name:connection+'.files',resource:'files'},{name:connection+'.contents',resource:'contents'},
          ...tables.map(table=>({name:connection+'.'+table.resource,resource:table.resource}))]
          .map(value=>Object.freeze(value))),...declared}));
      current();
    }
    if(sources.length===0)return undefined;
    bundle=Object.freeze({project:projectOriginal,connections:original,sources:Object.freeze(sources),realizationKey:'installed-multi-acquired'});
    const same = (runtime: unknown,receiver: unknown) => {if(runtime!==moon||receiver!==view)fail('ForeignLocalFilesPreparation');};
    view=Object.freeze({originalsForRuntime(runtime: unknown){same(runtime,this);current();
      if(connections!.originalsForRuntime(moon)!==original)fail('ForeignLocalFilesPreparation');return bundle!;},
      retire(runtime: unknown){same(runtime,this);if(retired)return;retired=true;
        // Managed-reference retirement only; Root/Run/reader cleanup stays with
        // its actual physical and Resource owners before this parent retires.
        bundle=connections=original=undefined;
      }});
    return view;
  };
}
