// Selected compiled binding shapes for the real Catalog test fixtures.
// Compiler objects stay opaque until their original projection is checked.

export interface NotionCatalogBindings {
  notionBindDataSourceReadContracts(declaration: unknown, source: unknown, max_bytes: number,
    max_nodes: number, max_depth: number, max_data_sources: number, max_properties: number,
    max_identity_bytes: number, max_name_bytes: number, contract_nodes: number, contract_depth: number,
    contract_text_bytes: number, max_columns: number, max_work: number): unknown;
  notionBindSelectedReadContracts(selection: unknown, source: unknown, max_bytes: number, max_nodes: number,
    max_depth: number, max_data_sources: number, max_properties: number, max_identity_bytes: number,
    max_name_bytes: number, contract_nodes: number, contract_depth: number, contract_text_bytes: number,
    max_columns: number, max_work: number): unknown;
  notionCaptureDatabaseReadSnapshot(selection: unknown, source: unknown, read_contracts: unknown,
    max_bytes: number, max_nodes: number, max_depth: number): unknown;
  notionDataSourceMatchesDatabase(source: unknown, database: unknown): boolean;
  notionDataSourceMetadataJson(source: unknown, max_bytes: number, max_nodes: number, max_depth: number): unknown;
  notionDataSourceReadMatches(binding: unknown, declaration: unknown, source: unknown): boolean;
  notionDataSourceReadSchemaJson(binding: unknown, max_bytes: number, max_nodes: number, max_depth: number): unknown;
  notionDatabaseMetadataJson(database: unknown, max_bytes: number, max_nodes: number, max_depth: number): unknown;
  notionDatabaseReadDeclarationOriginalJson(declaration: unknown, max_bytes: number): unknown;
  notionDatabaseReadDeclarationsAliasAt(declarations: unknown, index: number): unknown;
  notionDatabaseReadDeclarationsAt(declarations: unknown, index: number): unknown;
  notionDatabaseReadDeclarationsCount(declarations: unknown): unknown;
  notionDatabaseReadDeclarationsMatches(declarations: unknown, index: number, declaration: unknown): boolean;
  notionDatabaseReadDeclarationsSourceCid(declarations: unknown): unknown;
  notionDatabaseReadSnapshotRelationSpecification(snapshot: unknown, resource: string, max_bytes: number,
    max_nodes: number, max_depth: number): unknown;
  notionDatabaseReadSnapshotWire(snapshot: unknown): unknown;
  notionDatabaseReadSnapshotsRelationSpecification(resources: readonly string[], snapshots: readonly unknown[], max_bytes: number,
    max_nodes: number, max_depth: number, max_views: number, max_alias_work: number): unknown;
  notionProjectDataSource(database: unknown, index: number, bytes: Uint8Array, max_bytes: number,
    max_nodes: number, max_depth: number, max_data_sources: number, max_properties: number,
    max_identity_bytes: number, max_name_bytes: number): unknown;
  notionProjectDatabase(bytes: Uint8Array, max_bytes: number, max_nodes: number, max_depth: number,
    max_data_sources: number, max_properties: number, max_identity_bytes: number, max_name_bytes: number): unknown;
  notionProjectQueryPage(source: unknown, bytes: Uint8Array, max_bytes: number, max_nodes: number,
    max_depth: number, max_data_sources: number, max_properties: number, max_identity_bytes: number,
    max_name_bytes: number, max_rows: number, max_cursor_bytes: number): unknown;
  notionProjectSelectedReadSource(selection: unknown, bytes: Uint8Array, max_bytes: number, max_nodes: number,
    max_depth: number, max_data_sources: number, max_properties: number, max_identity_bytes: number,
    max_name_bytes: number): unknown;
  notionProjectUserList(body: Uint8Array, max_bytes: number, max_nodes: number, max_depth: number,
    max_rows: number, max_cursor_bytes: number, max_identity_bytes: number, max_value_nodes: number,
    max_value_text_bytes: number): unknown;
  notionPropertyReadCellJson(binding: unknown, page: unknown, row: number, column: number,
    admission_nodes: number, admission_depth: number, admission_text_bytes: number, max_work: number,
    max_bytes: number, max_nodes: number, max_depth: number): unknown;
  notionPublicConnectionCredentialKind(value: unknown): unknown;
  notionPublicConnectionCredentialReference(value: unknown): unknown;
  notionPublicConnectionDatabases(value: unknown): unknown;
  notionPublicConnectionHasDatabases(value: unknown): unknown;
  notionPublicConnectionOriginalJson(value: unknown, max_bytes: number): unknown;
  notionPublicConnectionSourceCid(value: unknown): unknown;
  notionQueryPageMatchesSource(page: unknown, source: unknown): boolean;
  notionQueryPageMetadataJson(page: unknown, max_bytes: number, max_nodes: number, max_depth: number): unknown;
  notionQueryPageOriginalJson(page: unknown, max_bytes: number): unknown;
  notionQueryPropertyValueJson(page: unknown, row: number, property: number, max_bytes: number): unknown;
  notionReadDatabaseDeclaration(bytes: Uint8Array, max_bytes: number, max_nodes: number, max_depth: number,
    max_data_sources: number, max_properties: number, max_identity_bytes: number, max_name_bytes: number,
    contract_nodes: number, contract_depth: number, contract_text_bytes: number, max_columns: number,
    max_work: number): unknown;
  notionReadDatabaseDeclarationSourceCid(declaration: unknown): string;
  notionReadDatabaseDeclarations(bytes: Uint8Array, max_bytes: number, max_nodes: number, max_depth: number,
    max_data_sources: number, max_properties: number, max_identity_bytes: number, max_name_bytes: number,
    contract_nodes: number, contract_depth: number, contract_text_bytes: number, max_columns: number,
    max_work: number, max_databases: number): unknown;
  notionReadPublicConnection(bytes: Uint8Array, max_bytes: number, max_nodes: number, max_depth: number,
    max_data_sources: number, max_properties: number, max_identity_bytes: number, max_name_bytes: number,
    contract_nodes: number, contract_depth: number, contract_text_bytes: number, max_columns: number,
    max_work: number, max_databases: number, max_reference_bytes: number): unknown;
  notionReadSourceIndex(declaration: unknown, database: unknown): unknown;
  notionSelectReadSource(declaration: unknown, database: unknown, max_work: number): unknown;
  notionSourceSystemReadContracts(binding: unknown, max_bytes: number, max_nodes: number, max_depth: number,
    max_data_sources: number, max_properties: number, max_identity_bytes: number, max_name_bytes: number,
    contract_nodes: number, contract_depth: number, contract_text_bytes: number, max_columns: number,
    max_work: number): unknown;
  notionUserListColumnNames(): string[];
  notionUserListIds(page: unknown): string[];
  notionUserListMetadataJson(page: unknown, max_bytes: number, max_nodes: number, max_depth: number): unknown;
  notionUserListRowsWire(page: unknown, names: readonly string[], max_bytes: number, max_nodes: number,
    max_depth: number): unknown;
  notionUserListSchemaWire(max_bytes: number, max_nodes: number, max_depth: number): unknown;
}

export interface CommonCatalogBindings {
  clientProgramCheckEnvironment(body: string, evidence_bundle_cid: string, text_time: boolean, veca: boolean,
    rela: boolean, sga: boolean, tea: boolean, calendar: boolean, text_rank: boolean): unknown;
  clientProgramPreparationIssueCode(outcome: unknown): string | undefined;
  clientProgramPreparationReady(outcome: unknown): unknown;
  clientProgramPrepareSourceWithParameters(document: string, format: string, environment: unknown,
    publication: string, declarations: string | undefined, parameters: string | undefined): unknown;
  clientProgramRowSourceDeclarationJson(declaration: unknown): string;
  clientProgramRowSourceRestoreRelationDeclaration(connector_id: string, connector_registration: string,
    connector_version: string, views_json: string, expected_catalog_cid: string | undefined): unknown;
}

type BoundsAfterOriginal<Args extends readonly unknown[]> =
  Args extends readonly [unknown, ...infer Bounds] ? Bounds : never;
export type NotionMetadataBounds = BoundsAfterOriginal<Parameters<NotionCatalogBindings['notionProjectDatabase']>>;
export type NotionDeclarationBounds = BoundsAfterOriginal<Parameters<NotionCatalogBindings['notionReadDatabaseDeclaration']>>;
export type NotionDeclarationPrefix = NotionDeclarationBounds extends [...infer Prefix, number] ? Prefix : never;
export type NotionUserBounds = BoundsAfterOriginal<Parameters<NotionCatalogBindings['notionProjectUserList']>>;
export type CatalogDeclaredSource =
  Parameters<typeof import('../../../host-node/installed-row-source.mjs').rowSourceCheckEnvironment>[1] &
  Readonly<{views:readonly Readonly<{resource:string;source_ref:string;view_cid:string;carrier_schema_cid:string}>[]}>;
