USE EZLynxWarehouse;
GO

/*To be used for views that exist in EZLynxWarehouse database*/

DECLARE @StageSchema				VARCHAR(128),
        @StageTable					VARCHAR(128),
        @WarehouseDatabase			VARCHAR(128) = 'EZLynxWarehouse',
        @WarehouseViewSchema        VARCHAR(128) = 'DMOrganization',
        @WarehouseView		        VARCHAR(128) = 'Organization',
        @ColumnNameLength			INT,
        @DataTypeLength				INT,
        @DataTypeStartPosition		INT,
        @NullStartPosition			INT,
        @SchemaID					INT,
        @ObjectID					INT;

DECLARE @UnitTest TABLE
(TestOrder  INT,
Description VARCHAR(MAX),
UnitTest    VARCHAR(MAX));

DECLARE @Column TABLE
(name               NVARCHAR(128),
column_id           INT,
ColDef              VARCHAR(MAX),
DataType            VARCHAR(128),
ColumnNameLength    INT,
DataTypeLength      INT,
max_length          INT);

DECLARE @TempColumnDef TABLE   
(ColList    VARCHAR(MAX));

DECLARE @ViewSelectColumnList TABLE
(ColList    VARCHAR(MAX));

DECLARE @ViewSelectColumnVariable TABLE
(ColList    VARCHAR(MAX));

SELECT @SchemaID = schema_id
FROM EZLynxWarehouse.sys.schemas
WHERE name = @WarehouseViewSchema;

SELECT @ObjectID = object_id
FROM EZLynxWarehouse.sys.views
WHERE schema_id = @SchemaID AND name = @WarehouseView;  

SELECT @ColumnNameLength = MAX(LEN(b.name)),
    @DataTypeLength = MAX(LEN(UPPER(c.name) + CASE WHEN c.name IN ('nvarchar','nchar') THEN '(' + REPLACE(CAST(b.max_length/2 AS VARCHAR(30)),'0','MAX') + ')'
                    WHEN c.name IN ('varchar','char','varbinary') THEN '(' + REPLACE(CAST(b.max_length AS VARCHAR(30)),'-1','MAX') + ')'
                    WHEN c.name IN ('decimal','numeric') THEN '(' + CAST(b.precision AS VARCHAR(30)) + ',' + CAST(b.scale AS VARCHAR(30)) + ')' 
                    ELSE '' END))
FROM sys.views v INNER JOIN sys.all_columns ac ON ac.object_id = v.object_id 
	INNER JOIN sys.columns b ON (ac.object_id = b.object_id AND ac.column_id = b.column_id)
    INNER JOIN sys.types c ON b.system_type_id = c.system_type_id
WHERE v.schema_id = SCHEMA_ID(@WarehouseViewSchema) AND v.name = @WarehouseView AND b.is_column_set = 0;

SET @DataTypeStartPosition = (((@ColumnNameLength / 4) + 1) * 4) - 1;
SET @NullStartPosition = ((@DataTypeLength / 4) + 1) * 4;

INSERT INTO @Column
(name, column_id, ColDef, DataType, ColumnNameLength, DataTypeLength, max_length)
SELECT DISTINCT c.name, c.column_id, 
'<datatypespace>' + UPPER(t.name) + CASE WHEN t.name IN ('nvarchar','nchar') THEN '(' + CAST(c.max_length/2 AS VARCHAR(30)) + ')'
                    WHEN t.name IN ('varchar','char','varbinary') THEN '(' + CAST(c.max_length AS VARCHAR(30)) + ')'
                    WHEN t.name IN ('decimal','numeric') THEN '(' + CAST(c.precision AS VARCHAR(30)) + ',' + CAST(c.scale AS VARCHAR(30)) + ')' 
                    ELSE '' END  + '<nullspace>' + 'NULL' ColDef, 
					t.name DataType, 
					LEN(c.name) ColumnNameLength,
LEN(UPPER(t.name) + CASE WHEN t.name IN ('nvarchar','nchar') THEN '(' + REPLACE(CAST(c.max_length/2 AS VARCHAR(30)),'0','MAX') + ')'
                    WHEN t.name IN ('varchar','char','varbinary') THEN '(' + REPLACE(CAST(c.max_length AS VARCHAR(30)),'-1','MAX') + ')'
                    WHEN t.name IN ('decimal','numeric') THEN '(' + CAST(c.precision AS VARCHAR(30)) + ',' + CAST(c.scale AS VARCHAR(30)) + ')' 
                    ELSE '' END) DataTypeLength,
					c.max_length
FROM sys.views v INNER JOIN sys.all_columns ac ON ac.object_id = v.object_id 
INNER JOIN sys.columns c ON (ac.object_id = c.object_id AND ac.column_id = c.column_id)
INNER JOIN sys.types t ON t.system_type_id = c.system_type_id 
WHERE v.schema_id = SCHEMA_ID(@WarehouseViewSchema) AND v.name = @WarehouseView AND t.name NOT IN ('sysname','geography','geometry','Private');

WITH FormattedColDefCTE
AS
(SELECT name, column_id, REPLACE(REPLACE(ColDef,'<datatypespace>',REPLICATE(' ', @DataTypeStartPosition - ColumnNameLength)),'<nullspace>',REPLICATE(' ', @NullStartPosition - DataTypeLength)) ColDef, 
    DataType, ColumnNameLength
FROM @Column)
INSERT INTO @TempColumnDef  --Used for Create #Actual and #Expected
(ColList)
SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ',' + CHAR(10) + name + ' ' + ColDef
                               FROM FormattedColDefCTE
                               ORDER BY column_id
                               FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList;

INSERT INTO @ViewSelectColumnList
(ColList)
SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList;

INSERT INTO @ViewSelectColumnVariable
(ColList)
SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
                                                   WHEN name = 'Deleted' THEN '0'
                                                   WHEN DataType = 'uniqueidentifier' THEN '@GUID' 
                                                   WHEN DataType IN ('char','varchar','nchar','nvarchar') THEN '@Char'
                                                   WHEN DataType IN ('tinyint','smallint','int','bigint') THEN '@Int' 
                                                   WHEN DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') THEN '@Datetime'
                                                   WHEN DataType IN ('decimal','numeric','float','real') THEN '@Decimal' 
                                                   WHEN DataType IN ('date') THEN '@Date'
                                                   WHEN DataType IN ('time') THEN '@Time'
                                                   WHEN DataType IN ('bit') THEN '@Bit'
                                                   WHEN DataType IN ('money','smallmoney') THEN '@Money'
                                                   WHEN DataType IN ('varbinary') THEN '@Bit'
												   WHEN DataType IN ('hierarchyid') THEN 'NULL'
                                                END
            FROM @Column
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList;


/************************************************************************************************************************************************************************************/
--Populate All Columns
WITH ViewSourcesCTE1  --to get source tables and what database they are in
AS
(SELECT DISTINCT
  SCHEMA_NAME(v.schema_id) ViewSchema,
  v.name ViewName,
  DatabaseName = (CASE WHEN d.referenced_database_name IS NULL THEN 'EZLynxWarehouse' WHEN d.referenced_database_name IS NOT NULL THEN d.referenced_database_name END), 
  d.referenced_schema_name SourceSchema,
  d.referenced_entity_name SourceTable
FROM sys.views AS v
INNER JOIN sys.schemas AS s
ON v.[schema_id] = s.[schema_id]
INNER JOIN sys.sql_expression_dependencies AS d
ON v.[object_id] = d.referencing_id
WHERE s.name = @WarehouseViewSchema
AND v.name = @WarehouseView),

SourceTableListStageCTE
AS
(SELECT DISTINCT 
    'EXEC ' + 'Stage.tSQLt.FakeTableTemporal @SchemaName = ''' + s1.name + ''', @TableName = ''' + t1.name + ''', @Identity = 0, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' SourceTableFakes, 
    a.DatabaseName, s1.name SourceSchema, t1.name SourceTable, t1.object_id SourceObjectID 
FROM ViewSourcesCTE1 a INNER JOIN Stage.sys.tables t1 ON a.SourceTable = t1.name 
    INNER JOIN Stage.sys.schemas s1 ON t1.schema_id = s1.schema_id
WHERE a.DatabaseName = 'Stage'
AND a.SourceSchema = s1.name),
SourceTableListEZLynxWarehouseCTE
AS
(SELECT DISTINCT 
    'EXEC ' + 'EZLynxWarehouse.tSQLt.FakeTableTemporal @SchemaName = ''' + s1.name + ''', @TableName = ''' + t1.name + ''', @Identity = 0, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' SourceTableFakes, 
    a.DatabaseName, s1.name SourceSchema, t1.name SourceTable, t1.object_id SourceObjectID 
FROM ViewSourcesCTE1 a INNER JOIN EZLynxWarehouse.sys.tables t1 ON a.SourceTable = t1.name AND a.SourceSchema = SCHEMA_NAME(t1.schema_id)
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON a.SourceSchema = s1.name
WHERE a.DatabaseName = 'EZLynxWarehouse'),
ALLSourceTableListCTE
AS 
(SELECT SourceTableFakes, DatabaseName, SourceSchema, SourceTable, SourceObjectID
FROM SourceTableListStageCTE
UNION ALL
SELECT SourceTableFakes, DatabaseName, SourceSchema, SourceTable, SourceObjectID
FROM SourceTableListEZLynxWarehouseCTE),
SourceFakesCTE
(SourceTableFakes)
AS 
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + SourceTableFakes
            FROM ALLSourceTableListCTE
            ORDER BY SourceSchema, SourceTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
SourceColStageCTE
(DatabaseName, SourceSchema, SourceTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.DatabaseName, fkl.SourceSchema, fkl.SourceTable, b.name, b.column_id, c.name DataType
FROM SourceTableListStageCTE fkl INNER JOIN Stage.sys.tables a ON fkl.SourceObjectID = a.object_id
    INNER JOIN Stage.sys.columns b ON a.object_id = b.object_id
    INNER JOIN Stage.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name NOT IN ('sysname','geography','geometry','Private') AND b.is_column_set = 0
AND fkl.DatabaseName = 'Stage' AND b.is_computed = 0),
SourceColEZLynxWarehouseCTE
(DatabaseName, SourceSchema, SourceTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.DatabaseName, fkl.SourceSchema, fkl.SourceTable, b.name, b.column_id, c.name DataType
FROM SourceTableListEZLynxWarehouseCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.SourceObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name NOT IN ('sysname','geography','geometry','Private') AND b.is_column_set = 0
AND fkl.DatabaseName = 'EZLynxWarehouse' AND b.is_computed = 0),
AllColumnCTE
AS 
(SELECT *
FROM SourceColStageCTE
UNION ALL
SELECT *
FROM SourceColEZLynxWarehouseCTE),
SourceInsertColumnListALLCTE
AS
(SELECT DISTINCT fkc2.DatabaseName, fkc2.SourceSchema, fkc2.SourceTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM AllColumnCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.SourceSchema = fkc2.SourceSchema AND fkc1.SourceTable = fkc2.SourceTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM AllColumnCTE fkc2),
SourceInsertValueAllCTE
AS
(SELECT DISTINCT fkc4.DatabaseName, fkc4.SourceSchema, fkc4.SourceTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN fkc3.name = 'ServerExecutionID' THEN '@ServerExecutionID' 
                                                   WHEN name = 'Deleted' THEN '0'
                                                   WHEN fkc3.DataType = 'uniqueidentifier' THEN '@GUID' 
                                                   WHEN fkc3.DataType IN ('char','varchar','nchar','nvarchar') THEN '@Char'
                                                   WHEN fkc3.DataType IN ('tinyint','smallint','int','bigint') THEN '@Int' 
                                                   WHEN fkc3.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') THEN '@Datetime'
                                                   WHEN fkc3.DataType IN ('decimal','numeric','float','real') THEN '@Decimal' 
                                                   WHEN fkc3.DataType IN ('date') THEN '@Date'
                                                   WHEN fkc3.DataType IN ('time') THEN '@Time'
                                                   WHEN fkc3.DataType IN ('bit') THEN '@Bit'
                                                   WHEN fkc3.DataType IN ('money','smallmoney') THEN '@Money'
                                                   WHEN fkc3.DataType IN ('varbinary') THEN '@Bit'
												   WHEN fkc3.DataType IN ('hierarchyid') THEN 'NULL'
                                                END
                            FROM AllColumnCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.SourceSchema = fkc4.SourceSchema AND fkc3.SourceTable = fkc4.SourceTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM AllColumnCTE fkc4),
SourceTableInsertStatmentsCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT  + ' INSERT INTO ' + fkil.DatabaseName + '.' + fkil.SourceSchema + '.' + fkil.SourceTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM SourceInsertColumnListALLCTE fkil INNER JOIN SourceInsertValueAllCTE fkiv ON fkil.SourceSchema = fkiv.SourceSchema AND fkil.SourceTable = fkiv.SourceTable AND fkil.DatabaseName = fkiv.DatabaseName
            ORDER BY fkil.DatabaseName, fkil.SourceSchema, fkil.SourceTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)

INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 1, 'Insert to Main Unit Test', 'USE [EZLynxWarehouse]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @WarehouseViewSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @WarehouseViewSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @WarehouseViewSchema + 'Test].[test View' + @WarehouseView + 
'_PopulateAllColumns]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0;' + CHAR(10) + CHAR(13) + 'CREATE TABLE #Expected' + CHAR(10) + '(' + b.ColList + CHAR(10) + ');' + 
CHAR(10) + CHAR(13) + 'CREATE TABLE #Actual' + CHAR(10) + '(' + b.ColList + CHAR(10) + ');' + CHAR(10) + CHAR(13) + 
'--Assemble' + CHAR(10) + 

CASE WHEN E.SourceTableFakes IS NOT NULL THEN REPLACE(E.SourceTableFakes,';',';' + CHAR(10)) ELSE '' END + CHAR(10) + CHAR(13) +

CASE WHEN f.InsertStatement IS NOT NULL THEN REPLACE(f.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + CHAR(10) + CHAR(13) + 
'INSERT INTO #Expected' + CHAR(10) + '(' + c.ColList + ')' + CHAR(10) + 'VALUES (' + d.ColList + ');' + CHAR(10) + CHAR(13) +
'INSERT INTO #Actual' + CHAR(10) + '(' + c.ColList + ')' + CHAR(10) + 'SELECT ' + c.ColList + CHAR(10) +
'FROM ' + @WarehouseViewSchema + '.' + @WarehouseView + ';' + CHAR(10) + CHAR(13) +
'--Assert' + CHAR(10) + 'EXEC tSQLt.AssertEqualsTable #Expected, #Actual;' + CHAR(10) + 'GO'
FROM sys.views a CROSS JOIN @TempColumnDef b  
	CROSS JOIN @ViewSelectColumnList c
	CROSS JOIN @ViewSelectColumnVariable d
	CROSS JOIN SourceFakesCTE e 
	CROSS JOIN SourceTableInsertStatmentsCTE f
WHERE a.schema_id = SCHEMA_ID(@WarehouseViewSchema) AND name = @WarehouseView;



SELECT Description, UnitTest 
FROM @UnitTest
ORDER BY TestOrder, Description;

