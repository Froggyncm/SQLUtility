DECLARE @StageSchema            VARCHAR(128) = 'Policy',
        @StageTable             VARCHAR(128) = 'AL3XMLData',
        @WarehouseDatabase      VARCHAR(128) = 'EZLynxWarehouse',
        @WarehouseSchema        VARCHAR(128) = 'Policy',
        @WarehouseTable         VARCHAR(128) = 'AL3XMLData',
        @ColumnNameLength       INT,
        @DataTypeLength         INT,
        @DataTypeStartPosition  INT,
        @NullStartPosition      INT,
        @SchemaID               INT,
        @ObjectID               INT;

DECLARE @UnitTest TABLE
(TestOrder  INT,
Description VARCHAR(MAX),
UnitTest    VARCHAR(MAX));

DECLARE @Column TABLE
(name               NVARCHAR(128),
column_id           INT,
KeyColumn           VARCHAR(10),
ColDef              VARCHAR(MAX),
DataType            VARCHAR(128),
ColumnNameLength    INT,
DataTypeLength      INT,
max_length          INT);

DECLARE @TempColumnDef TABLE
(ColList    VARCHAR(MAX));

DECLARE @ReprocessTempColumnDef TABLE
(ColList    VARCHAR(MAX));

DECLARE @SourceSelectColumnList TABLE
(ColList    VARCHAR(MAX));

DECLARE @KeyColumn TABLE
(ColList    VARCHAR(MAX));

SELECT @SchemaID = schema_id
FROM EZLynxWarehouse.sys.schemas
WHERE name = @WarehouseSchema;

SELECT @ObjectID = object_id
FROM EZLynxWarehouse.sys.tables
WHERE schema_id = @SchemaID AND name = @WarehouseTable;  

SELECT @ColumnNameLength = MAX(LEN(b.name)),
    @DataTypeLength = MAX(LEN(UPPER(c.name) + CASE WHEN c.name IN ('nvarchar','nchar') THEN '(' + REPLACE(CAST(b.max_length/2 AS VARCHAR(30)),'0','MAX') + ')'
                    WHEN c.name IN ('varchar','char','varbinary') THEN '(' + REPLACE(CAST(b.max_length AS VARCHAR(30)),'-1','MAX') + ')'
                    WHEN c.name IN ('decimal','numeric') THEN '(' + CAST(b.precision AS VARCHAR(30)) + ',' + CAST(b.scale AS VARCHAR(30)) + ')' 
                    ELSE '' END))
FROM sys.tables a INNER JOIN sys.columns b ON a.object_id = b.object_id
    INNER JOIN sys.types c ON b.system_type_id = c.system_type_id
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND a.name = @StageTable AND b.is_column_set = 0 AND b.name <> 'RowHash';

SET @DataTypeStartPosition = (((@ColumnNameLength / 4) + 1) * 4) - 1;
SET @NullStartPosition = ((@DataTypeLength / 4) + 1) * 4;

INSERT INTO @Column
(name, column_id, KeyColumn, ColDef, DataType, ColumnNameLength, DataTypeLength, max_length)
SELECT DISTINCT b.name, b.column_id, CASE WHEN b.column_id = e.column_id THEN 'Yes' ELSE 'No' END KeyColumn, 
'<datatypespace>' + UPPER(c.name) + CASE WHEN c.name IN ('nvarchar','nchar') THEN '(' + REPLACE(CAST(b.max_length/2 AS VARCHAR(30)),'0','MAX') + ')'
                    WHEN c.name IN ('varchar','char','varbinary') THEN '(' + REPLACE(CAST(b.max_length AS VARCHAR(30)),'-1','MAX') + ')'
                    WHEN c.name IN ('decimal','numeric') THEN '(' + CAST(b.precision AS VARCHAR(30)) + ',' + CAST(b.scale AS VARCHAR(30)) + ')' 
                    ELSE '' END  + '<nullspace>' + CASE WHEN b.is_nullable = 1 THEN 'NULL' ELSE 'NOT NULL' END ColDef, c.name DataType, LEN(b.name) ColumnNameLength,
LEN(UPPER(c.name) + CASE WHEN c.name IN ('nvarchar','nchar') THEN '(' + REPLACE(CAST(b.max_length/2 AS VARCHAR(30)),'0','MAX') + ')'
                    WHEN c.name IN ('varchar','char','varbinary') THEN '(' + REPLACE(CAST(b.max_length AS VARCHAR(30)),'-1','MAX') + ')'
                    WHEN c.name IN ('decimal','numeric') THEN '(' + CAST(b.precision AS VARCHAR(30)) + ',' + CAST(b.scale AS VARCHAR(30)) + ')' 
                    ELSE '' END) DataTypeLength, b.max_length
FROM sys.tables a INNER JOIN sys.columns b ON a.object_id = b.object_id
    INNER JOIN sys.types c ON b.system_type_id = c.system_type_id 
    LEFT OUTER JOIN sys.indexes d ON b.object_id = d.object_id
    LEFT OUTER JOIN sys.index_columns e ON d.object_id = e.object_id AND d.index_id = e.index_id AND e.column_id = b.column_id
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND a.name = @StageTable AND d.is_primary_key = 1 AND c.name <> 'sysname' AND b.is_column_set = 0;

WITH FormattedColDefCTE
AS
(SELECT name, column_id, REPLACE(REPLACE(ColDef,'<datatypespace>',REPLICATE(' ', @DataTypeStartPosition - ColumnNameLength)),'<nullspace>',REPLICATE(' ', @NullStartPosition - DataTypeLength)) ColDef, 
    DataType, ColumnNameLength
FROM @Column)
INSERT INTO @TempColumnDef
(ColList)
SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ',' + CHAR(10) + name + ' ' + ColDef
                               FROM FormattedColDefCTE
                               WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                               ORDER BY column_id
                               FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList;

WITH FormattedColDefCTE
AS
(SELECT name, column_id, REPLACE(REPLACE(ColDef,'<datatypespace>',REPLICATE(' ', @DataTypeStartPosition - ColumnNameLength)),'<nullspace>',REPLICATE(' ', @NullStartPosition - DataTypeLength)) ColDef, 
    DataType, ColumnNameLength
FROM @Column)
INSERT INTO @ReprocessTempColumnDef
(ColList)
SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ',' + CHAR(10) + name + ' ' + ColDef
                               FROM FormattedColDefCTE
                               WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime','DWLoadDate','ServerExecutionID')
                               ORDER BY column_id
                               FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList;

INSERT INTO @SourceSelectColumnList
(ColList)
SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
                               FROM @Column
                               ORDER BY column_id
                               FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList;

INSERT INTO @KeyColumn
(ColList)
SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ' AND ' + name + ' = ' + 
                                    CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID'
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
                                    END
                                FROM @Column
                                WHERE KeyColumn = 'Yes'
                                ORDER BY column_id
                                FOR XML PATH ('')),1,4,''))) AS VARCHAR(MAX)) ColList;

/************************************************************************************************************************************************************************************/
--Insert into current
WITH InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 1, 'Insert to Main Unit Test', 'USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + 
'_Insert]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0;' + CHAR(10) + CHAR(13) + 'CREATE TABLE #Expected' + CHAR(10) + '(' + b.ColList + CHAR(10) + ');' + 
CHAR(10) + CHAR(13) + 'CREATE TABLE #Actual' + CHAR(10) + '(' + b.ColList + CHAR(10) + ');' + CHAR(10) + CHAR(13) + '--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'INSERT INTO #Expected' + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
'--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''No'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
'INSERT INTO #Actual' + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) +
'SELECT ' + f.ColList + CHAR(10) + 'FROM ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @StageTable + ';' + CHAR(10) + CHAR(13) + 
'--Assert' + CHAR(10) + 'EXEC tSQLt.AssertEqualsTable #Expected, #Actual;' + CHAR(10) + 'GO'
FROM sys.tables a CROSS JOIN @TempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Insert empty history
WITH InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 2, 'Insert - History Empty unit test','USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + 
'_InsertHistoryEmpty]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0;' + CHAR(10) + CHAR(13) + '--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''No'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
'--Assert' + CHAR(10) + 'EXEC ' + @WarehouseDatabase + '.tSQLt.AssertEmptyTable ''' + @WarehouseSchema + '.' + @WarehouseTable + 'History'';' + CHAR(10) + 'GO'
FROM sys.tables a CROSS JOIN @TempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Insert empty exception
WITH InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 3, 'Insert - Exception Empty unit test','USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + 
'_InsertExceptionEmpty]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0;' + CHAR(10) + CHAR(13) + '--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''No'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
'--Assert' + CHAR(10) + 'EXEC ' + @WarehouseDatabase + '.tSQLt.AssertEmptyTable ''zException' + @StageSchema + '.' + @StageTable + ''';' + CHAR(10) + 'GO'
FROM sys.tables a CROSS JOIN @TempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Foreign key violation unit test stack

DECLARE @FKTestObjectID BIGINT,
        @FKTestMissingValue VARCHAR(MAX);

DECLARE curFKTest CURSOR FOR 
    SELECT DISTINCT t2.object_id, 'Missing' + s2.name + t2.name + c2.name
    FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
        INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
        INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
        INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
        INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
    WHERE fk.parent_object_id = @ObjectID FOR READ ONLY;

OPEN curFKTest;
FETCH curFKTest INTO @FKTestObjectID, @FKTestMissingValue;

WHILE @@FETCH_STATUS = 0
BEGIN;
/************************************************************************************************************************************************************************************/
    WITH InsertColumnListCTE
    AS
    (SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
                FROM @Column
                WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                ORDER BY column_id
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
    InsertValueListCTE
    AS
    (SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                    END
                FROM @Column
                WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                ORDER BY column_id
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
    FKListCTE
    AS
    (SELECT DISTINCT 
        'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
        s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
    FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
        INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
        INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
        INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
        INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
    WHERE fk.parent_object_id = @ObjectID),
    FKFakesCTE
    AS
    (SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
                FROM FKListCTE
                ORDER BY ParentSchema, ParentTable
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
    FKColCTE
    (ParentSchema, ParentTable, name, column_id, DataType)
    AS
    (SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
    FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
        INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
        INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
    WHERE c.name <> 'sysname' AND b.is_column_set = 0 AND fkl.ParentObjectID <> @FKTestObjectID),
    FKInsertColumnListCTE
    AS
    (SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
        CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                                FROM FKColCTE fkc1
                                WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                                ORDER BY fkc1.column_id
                                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
    FROM FKColCTE fkc2),
    FKInsertValueListCTE
    AS
    (SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                    END
                                FROM FKColCTE fkc3
                                WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                                ORDER BY fkc3.column_id
                                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
    FROM FKColCTE fkc4),
    FKTableInsertStatementCTE
    AS
    (SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
                FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
                ORDER BY fkil.ParentSchema, fkil.ParentTable
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
    INSERT INTO @UnitTest
    (TestOrder, Description, UnitTest)
    SELECT 4, @FKTestMissingValue + 'Not written to warehouse', 'USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
    'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
    'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + 
    '_' + @FKTestMissingValue + 'WarehouseEmpty]' + CHAR(10) +
    'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
    '        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
    CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
    '        @ServerExecutionID  BIGINT = 0;' + CHAR(10) + CHAR(13) + '--Assemble' + CHAR(10) + 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
    CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
    'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
    'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
    CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
    '--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''No'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
    '--Assert' + CHAR(10) + 'EXEC ' + @WarehouseDatabase + '.tSQLt.AssertEmptyTable ''' + @WarehouseSchema + '.' + @WarehouseTable + ''';' + CHAR(10) + 'GO'
    FROM sys.tables a CROSS JOIN @TempColumnDef b
        CROSS JOIN @SourceSelectColumnList c
        CROSS JOIN @KeyColumn d
        CROSS JOIN InsertColumnListCTE f
        CROSS JOIN InsertValueListCTE g
        CROSS JOIN FKFakesCTE fkf
        CROSS JOIN FKTableInsertStatementCTE fkis
    WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
    WITH InsertColumnListCTE
    AS
    (SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
                FROM @Column
                WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                ORDER BY column_id
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
    InsertValueListCTE
    AS
    (SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                    END
                FROM @Column
                WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                ORDER BY column_id
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
    FKListCTE
    AS
    (SELECT DISTINCT 
        'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
        s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
    FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
        INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
        INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
        INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
        INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
    WHERE fk.parent_object_id = @ObjectID),
    FKFakesCTE
    AS
    (SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
                FROM FKListCTE
                ORDER BY ParentSchema, ParentTable
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
    FKColCTE
    (ParentSchema, ParentTable, name, column_id, DataType)
    AS
    (SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
    FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
        INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
        INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
    WHERE c.name <> 'sysname' AND b.is_column_set = 0 AND fkl.ParentObjectID <> @FKTestObjectID),
    FKInsertColumnListCTE
    AS
    (SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
        CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                                FROM FKColCTE fkc1
                                WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                                ORDER BY fkc1.column_id
                                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
    FROM FKColCTE fkc2),
    FKInsertValueListCTE
    AS
    (SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                    END
                                FROM FKColCTE fkc3
                                WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                                ORDER BY fkc3.column_id
                                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
    FROM FKColCTE fkc4),
    FKTableInsertStatementCTE
    AS
    (SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
                FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
                ORDER BY fkil.ParentSchema, fkil.ParentTable
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
    INSERT INTO @UnitTest
    (TestOrder, Description, UnitTest)
    SELECT 5, @FKTestMissingValue + 'Not written to history', 'USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
    'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
    'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + 
    '_' + @FKTestMissingValue + 'HistoryEmpty]' + CHAR(10) +
    'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
    '        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
    CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
    '        @ServerExecutionID  BIGINT = 0;' + CHAR(10) + CHAR(13) + '--Assemble' + CHAR(10) + 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
    CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
    'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
    'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
    CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
    '--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''No'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
    '--Assert' + CHAR(10) + 'EXEC ' + @WarehouseDatabase + '.tSQLt.AssertEmptyTable ''' + @WarehouseSchema + '.' + @WarehouseTable + 'History'';' + CHAR(10) + 'GO'
    FROM sys.tables a CROSS JOIN @TempColumnDef b
        CROSS JOIN @SourceSelectColumnList c
        CROSS JOIN @KeyColumn d
        CROSS JOIN InsertColumnListCTE f
        CROSS JOIN InsertValueListCTE g
        CROSS JOIN FKFakesCTE fkf
        CROSS JOIN FKTableInsertStatementCTE fkis
    WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
    WITH InsertColumnListCTE
    AS
    (SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
                FROM @Column
                WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                ORDER BY column_id
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
    InsertValueListCTE
    AS
    (SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                    END
                FROM @Column
                WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                ORDER BY column_id
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
    FKListCTE
    AS
    (SELECT DISTINCT 
        'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
        s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
    FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
        INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
        INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
        INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
        INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
    WHERE fk.parent_object_id = @ObjectID),
    FKFakesCTE
    AS
    (SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
                FROM FKListCTE
                ORDER BY ParentSchema, ParentTable
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
    FKColCTE
    (ParentSchema, ParentTable, name, column_id, DataType)
    AS
    (SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
    FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
        INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
        INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
    WHERE c.name <> 'sysname' AND b.is_column_set = 0 AND fkl.ParentObjectID <> @FKTestObjectID),
    FKInsertColumnListCTE
    AS
    (SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
        CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                                FROM FKColCTE fkc1
                                WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                                ORDER BY fkc1.column_id
                                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
    FROM FKColCTE fkc2),
    FKInsertValueListCTE
    AS
    (SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                    END
                                FROM FKColCTE fkc3
                                WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                                ORDER BY fkc3.column_id
                                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
    FROM FKColCTE fkc4),
    FKTableInsertStatementCTE
    AS
    (SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
                FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
                ORDER BY fkil.ParentSchema, fkil.ParentTable
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
    INSERT INTO @UnitTest
    (TestOrder, Description, UnitTest)
    SELECT 6, @FKTestMissingValue + 'Written to exception', 'USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
    'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
    'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + 
    '_' + @FKTestMissingValue + 'ExceptionExists]' + CHAR(10) +
    'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
    '        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
    CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
    '        @ServerExecutionID  BIGINT = 0;' + CHAR(10) + CHAR(13) + 'CREATE TABLE #Expected' + CHAR(10) + '(' + b.ColList + CHAR(10) + ');' + 
    CHAR(10) + CHAR(13) + 'CREATE TABLE #Actual' + CHAR(10) + '(' + b.ColList + CHAR(10) + ');' + CHAR(10) + CHAR(13) + '--Assemble' + CHAR(10) + 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
    CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
    'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
    'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
    CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
    'INSERT INTO #Expected' + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
    '--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''No'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
    'INSERT INTO #Actual' + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) +
    'SELECT ' + f.ColList + CHAR(10) + 'FROM ' + @WarehouseDatabase + '.zException' + @StageSchema + '.' + @StageTable + ';' + CHAR(10) + CHAR(13) + 
    '--Assert' + CHAR(10) + 'EXEC tSQLt.AssertEqualsTable #Expected, #Actual;' + CHAR(10) + 'GO'
    FROM sys.tables a CROSS JOIN @TempColumnDef b
        CROSS JOIN @SourceSelectColumnList c
        CROSS JOIN @KeyColumn d
        CROSS JOIN InsertColumnListCTE f
        CROSS JOIN InsertValueListCTE g
        CROSS JOIN FKFakesCTE fkf
        CROSS JOIN FKTableInsertStatementCTE fkis
    WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

    FETCH curFKTest INTO @FKTestObjectID, @FKTestMissingValue;
END;

CLOSE curFKTest;
DEALLOCATE curFKTest;

/************************************************************************************************************************************************************************************/
--Update row - New version in current unit test
WITH FirstNon@KeyColumn
AS
(SELECT TOP 1 name
FROM @Column
WHERE KeyColumn = 'No' AND name NOT IN ('Created', 'CreatedBy', 'Deleted', 'LastModified', 'LastModifiedBy', 'ServerExecutionID', 'DWLoadDate', 'RowHash', 'VersionStartTime', 'VersionEndTime')
ORDER BY column_id),
StageValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN col.name = 'Deleted' THEN '0'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NULL THEN '@GUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NULL THEN '@Char'
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NULL THEN '@Int' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NULL THEN '@Datetime'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NULL THEN '@Decimal' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NULL  THEN '@Date'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NULL  THEN '@Time'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NULL  THEN '@Bit'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NULL  THEN '@Money'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NOT NULL THEN '@UpdateGUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NOT NULL THEN '''B'''
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NOT NULL THEN '2' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Datetime)'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NOT NULL THEN '2.0' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Date)'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NOT NULL THEN 'DATEADD(hh,1,@Time)'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NOT NULL THEN '0'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NOT NULL THEN '2.00'
                                                    WHEN col.DataType IN ('varbinary') THEN '@Bit'
                                                END
            FROM @Column col LEFT OUTER JOIN FirstNon@KeyColumn fcol ON col.name = fcol.name
            WHERE col.name <> 'RowHash'
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 13, 'Update row - New version in current unit test','USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + '_UpdateRow]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0,' + CHAR(10) + '        @UpdateGUID         UNIQUEIDENTIFIER = NEWID();' + CHAR(10) + CHAR(13) + 
'CREATE TABLE #Expected' + CHAR(10) + '(' + b.ColList + ');' + CHAR(10) + CHAR(13) + 
'CREATE TABLE #Actual' + CHAR(10) + '(' + b.ColList + ');' + CHAR(10) + CHAR(13) +
'--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @WarehouseTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + i.ColList + ');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'INSERT INTO #Expected' + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + i.ColList + ');' + CHAR(10) + CHAR(13) + 
'EXEC ' + @StageSchema + '.Merge' + @StageTable + ' @ProcessExceptions = ''No'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) +
'INSERT INTO #Actual' + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) +
'SELECT ' + f.ColList + CHAR(10) + 'FROM ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @WarehouseTable + ';' + 
CHAR(10) + CHAR(13) + '--Assert' + CHAR(10) + 'EXEC tSQLt.AssertEqualsTable #Expected, #Actual;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(10)
FROM sys.tables a CROSS JOIN @TempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN StageValueListCTE i
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Update row - Prior version in history unit test
WITH FirstNon@KeyColumn
AS
(SELECT TOP 1 name
FROM @Column
WHERE KeyColumn = 'No' AND name NOT IN ('Created', 'CreatedBy', 'Deleted', 'LastModified', 'LastModifiedBy', 'ServerExecutionID', 'DWLoadDate', 'RowHash', 'VersionStartTime', 'VersionEndTime')
ORDER BY column_id),
StageValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN col.name = 'Deleted' THEN '0'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NULL THEN '@GUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NULL THEN '@Char'
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NULL THEN '@Int' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NULL THEN '@Datetime'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NULL THEN '@Decimal' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NULL  THEN '@Date'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NULL  THEN '@Time'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NULL  THEN '@Bit'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NULL  THEN '@Money'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NOT NULL THEN '@UpdateGUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NOT NULL THEN '''B'''
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NOT NULL THEN '2' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Datetime)'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NOT NULL THEN '2.0' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Date)'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NOT NULL THEN 'DATEADD(hh,1,@Time)'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NOT NULL THEN '0'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NOT NULL THEN '2.00'
                                                    WHEN col.DataType IN ('varbinary') THEN '@Bit'
                                                END
            FROM @Column col LEFT OUTER JOIN FirstNon@KeyColumn fcol ON col.name = fcol.name
            WHERE col.name <> 'RowHash'
            ORDER BY col.column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 14, 'Update row - Prior version in history unit test','USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + '_UpdateRowPriorVersionInHistory]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0,' + CHAR(10) + '        @UpdateGUID         UNIQUEIDENTIFIER = NEWID();' + CHAR(10) + CHAR(13) + 
'CREATE TABLE #Expected' + CHAR(10) + '(' + b.ColList + ');' + CHAR(10) + CHAR(13) + 
'CREATE TABLE #Actual' + CHAR(10) + '(' + b.ColList + ');' + CHAR(10) + CHAR(13) +
'--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @WarehouseTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + i.ColList + ');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'INSERT INTO #Expected' + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
'EXEC ' + @StageSchema + '.Merge' + @StageTable + ' @ProcessExceptions = ''No'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) +
'INSERT INTO #Actual' + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) +
'SELECT ' + f.ColList + CHAR(10) + 'FROM ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @WarehouseTable + 'History;' + 
CHAR(10) + CHAR(13) + '--Assert' + CHAR(10) + 'EXEC tSQLt.AssertEqualsTable #Expected, #Actual;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(10)
FROM sys.tables a CROSS JOIN @TempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN StageValueListCTE i
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Update row - Exception empty unit test
WITH FirstNon@KeyColumn
AS
(SELECT TOP 1 name
FROM @Column
WHERE KeyColumn = 'No' AND name NOT IN ('Created', 'CreatedBy', 'Deleted', 'LastModified', 'LastModifiedBy', 'ServerExecutionID', 'DWLoadDate', 'RowHash', 'VersionStartTime', 'VersionEndTime')
ORDER BY column_id),
StageValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN col.name = 'Deleted' THEN '0'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NULL THEN '@GUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NULL THEN '@Char'
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NULL THEN '@Int' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NULL THEN '@Datetime'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NULL THEN '@Decimal' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NULL  THEN '@Date'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NULL  THEN '@Time'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NULL  THEN '@Bit'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NULL  THEN '@Money'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NOT NULL THEN '@UpdateGUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NOT NULL THEN '''B'''
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NOT NULL THEN '2' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Datetime)'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NOT NULL THEN '2.0' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Date)'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NOT NULL THEN 'DATEADD(hh,1,@Time)'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NOT NULL THEN '0'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NOT NULL THEN '2.00'
                                                    WHEN col.DataType IN ('varbinary') THEN '@Bit'
                                                END
            FROM @Column col LEFT OUTER JOIN FirstNon@KeyColumn fcol ON col.name = fcol.name
            WHERE col.name <> 'RowHash'
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 15, 'Update row - Exception table empty unit test','USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + '_UpdateRowExceptionEmpty]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0,' + CHAR(10) + '        @UpdateGUID         UNIQUEIDENTIFIER = NEWID();' + CHAR(10) + CHAR(13) + 
'--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @WarehouseTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + i.ColList + ');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'EXEC ' + @StageSchema + '.Merge' + @StageTable + ' @ProcessExceptions = ''No'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) +
'--Assert' + CHAR(10) + 'EXEC ' + @WarehouseDatabase + '.tSQLt.AssertEmptyTable ''zException' + @StageSchema + '.' + @StageTable + ''';' + CHAR(10) + 'GO' + CHAR(10) + CHAR(10)
FROM sys.tables a CROSS JOIN @TempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN StageValueListCTE i
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Update row - Nonversioned data, no change to current unit test
WITH FirstNonVersionedColumnCTE
AS
(SELECT TOP 1 name
FROM @Column
WHERE KeyColumn = 'No' AND name IN ('Created', 'CreatedBy', 'Deleted', 'LastModified', 'LastModifiedBy', 'ServerExecutionID', 'DWLoadDate', 'RowHash', 'VersionStartTime', 'VersionEndTime')
ORDER BY column_id),
StageValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN col.name = 'Deleted' THEN '0'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NULL THEN '@GUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NULL THEN '@Char'
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NULL THEN '@Int' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NULL THEN '@Datetime'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NULL THEN '@Decimal' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NULL  THEN '@Date'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NULL  THEN '@Time'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NULL  THEN '@Bit'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NULL  THEN '@Money'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NOT NULL THEN '@UpdateGUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NOT NULL THEN '''B'''
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NOT NULL THEN '2' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Datetime)'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NOT NULL THEN '2.0' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Date)'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NOT NULL THEN 'DATEADD(hh,1,@Time)'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NOT NULL THEN '0'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NOT NULL THEN '2.00'
                                                    WHEN col.DataType IN ('varbinary') THEN '@Bit'
                                                END
            FROM @Column col LEFT OUTER JOIN FirstNonVersionedColumnCTE fcol ON col.name = fcol.name
            WHERE col.name <> 'RowHash'
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 16, 'Update row - Nonversioned data, no change to current unit test','USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + '_UpdateRowNonVersionedDataCurrentNotChanged]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0,' + CHAR(10) + '        @UpdateGUID         UNIQUEIDENTIFIER = NEWID();' + CHAR(10) + CHAR(13) + 
'CREATE TABLE #Expected' + CHAR(10) + '(' + b.ColList + ');' + CHAR(10) + CHAR(13) + 
'CREATE TABLE #Actual' + CHAR(10) + '(' + b.ColList + ');' + CHAR(10) + CHAR(13) +
'--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @WarehouseTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + i.ColList + ');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'INSERT INTO #Expected' + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
'EXEC ' + @StageSchema + '.Merge' + @StageTable + ' @ProcessExceptions = ''No'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) +
'INSERT INTO #Actual' + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) +
'SELECT ' + f.ColList + CHAR(10) + 'FROM ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @WarehouseTable + ';' + 
CHAR(10) + CHAR(13) + '--Assert' + CHAR(10) + 'EXEC tSQLt.AssertEqualsTable #Expected, #Actual;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(10)
FROM sys.tables a CROSS JOIN @TempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN StageValueListCTE i
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Update row - Nonversioned data, empty history unit test
WITH FirstNonVersionedColumnCTE
AS
(SELECT TOP 1 name
FROM @Column
WHERE KeyColumn = 'No' AND name IN ('Created', 'CreatedBy', 'Deleted', 'LastModified', 'LastModifiedBy', 'ServerExecutionID', 'DWLoadDate', 'RowHash', 'VersionStartTime', 'VersionEndTime')
ORDER BY column_id),
StageValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN col.name = 'Deleted' THEN '0'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NULL THEN '@GUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NULL THEN '@Char'
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NULL THEN '@Int' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NULL THEN '@Datetime'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NULL THEN '@Decimal' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NULL  THEN '@Date'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NULL  THEN '@Time'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NULL  THEN '@Bit'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NULL  THEN '@Money'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NOT NULL THEN '@UpdateGUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NOT NULL THEN '''B'''
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NOT NULL THEN '2' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Datetime)'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NOT NULL THEN '2.0' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Date)'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NOT NULL THEN 'DATEADD(hh,1,@Time)'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NOT NULL THEN '0'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NOT NULL THEN '2.00'
                                                    WHEN col.DataType IN ('varbinary') THEN '@Bit'
                                                END
            FROM @Column col LEFT OUTER JOIN FirstNonVersionedColumnCTE fcol ON col.name = fcol.name
            WHERE col.name <> 'RowHash'
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 17, 'Update row - Nonversioned data, empty history unit test','USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + '_UpdateRowNonversionedDataHistoryEmpty]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0,' + CHAR(10) + '        @UpdateGUID         UNIQUEIDENTIFIER = NEWID();' + CHAR(10) + CHAR(13) + 
'--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @WarehouseTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + i.ColList + ');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'EXEC ' + @StageSchema + '.Merge' + @StageTable + ' @ProcessExceptions = ''No'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) +
'--Assert' + CHAR(10) + 'EXEC ' + @WarehouseDatabase + '.tSQLt.AssertEmptyTable ''' + @WarehouseSchema + '.' + @WarehouseTable + 'History'';' + CHAR(10) + 'GO' + CHAR(10) + CHAR(10)
FROM sys.tables a CROSS JOIN @TempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN StageValueListCTE i
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Update row - Nonversioned, exception empty unit test
WITH FirstNonVersionedColumnCTE
AS
(SELECT TOP 1 name
FROM @Column
WHERE KeyColumn = 'No' AND name IN ('Created', 'CreatedBy', 'Deleted', 'LastModified', 'LastModifiedBy', 'ServerExecutionID', 'DWLoadDate', 'RowHash', 'VersionStartTime', 'VersionEndTime')
ORDER BY column_id),
StageValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN col.name = 'Deleted' THEN '0'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NULL THEN '@GUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NULL THEN '@Char'
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NULL THEN '@Int' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NULL THEN '@Datetime'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NULL THEN '@Decimal' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NULL  THEN '@Date'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NULL  THEN '@Time'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NULL  THEN '@Bit'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NULL  THEN '@Money'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NOT NULL THEN '@UpdateGUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NOT NULL THEN '''B'''
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NOT NULL THEN '2' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Datetime)'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NOT NULL THEN '2.0' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Date)'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NOT NULL THEN 'DATEADD(hh,1,@Time)'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NOT NULL THEN '0'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NOT NULL THEN '2.00'
                                                    WHEN col.DataType IN ('varbinary') THEN '@Bit'
                                                END
            FROM @Column col LEFT OUTER JOIN FirstNonVersionedColumnCTE fcol ON col.name = fcol.name
            WHERE col.name <> 'RowHash'
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 18, 'Update row - Nonversioned, exception empty unit test','USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + '_UpdateRowNonversionedDataExceptionEmpty]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0,' + CHAR(10) + '        @UpdateGUID         UNIQUEIDENTIFIER = NEWID();' + CHAR(10) + CHAR(13) + 
'--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @WarehouseTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + g.ColList + ');' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + i.ColList + ');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'EXEC ' + @StageSchema + '.Merge' + @StageTable + ' @ProcessExceptions = ''No'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) +
'--Assert' + CHAR(10) + 'EXEC ' + @WarehouseDatabase + '.tSQLt.AssertEmptyTable ''zException' + @StageSchema + '.' + @StageTable + ''';' + CHAR(10) + 'GO' + CHAR(10) + CHAR(10)
FROM sys.tables a CROSS JOIN @TempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN StageValueListCTE i
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Exception branch unit tests
--Inserted into warehouse
WITH InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 19, 'Exception Reprocess, Insert to Current Unit Test', 'USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + 
'_ReprocessExceptionRowAddedToWarehouse]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0;' + CHAR(10) + CHAR(13) + 'CREATE TABLE #Expected' + CHAR(10) + '(' + b.ColList + CHAR(10) + ');' + 
CHAR(10) + CHAR(13) + 'CREATE TABLE #Actual' + CHAR(10) + '(' + b.ColList + CHAR(10) + ');' + CHAR(10) + CHAR(13) + '--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.zException' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ', ErrorDescription)' + CHAR(10) + 'VALUES (' + g.ColList + ',''Orphan SomeColumn'');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'INSERT INTO #Expected' + CHAR(10) + '(' + REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + ')' + CHAR(10) + 'VALUES (' + REPLACE(g.ColList,', @ServerExecutionID, @Datetime','') + ');' + CHAR(10) + CHAR(13) + 
'--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''Yes'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
'INSERT INTO #Actual' + CHAR(10) + '(' +  REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + ')' + CHAR(10) +
'SELECT ' + REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + CHAR(10) + 'FROM ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @StageTable + ';' + CHAR(10) + CHAR(13) + 
'--Assert' + CHAR(10) + 'EXEC tSQLt.AssertEqualsTable #Expected, #Actual;' + CHAR(10) + 'GO'
FROM sys.tables a CROSS JOIN @ReprocessTempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Removed from exception table
WITH InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 20, 'Exception Reprocess, Removed from exception Unit Test', 'USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + 
'_ReprocessExceptionRowExceptionEmpty]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0;' + CHAR(10) + CHAR(13) + '--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.zException' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ', ErrorDescription)' + CHAR(10) + 'VALUES (' + g.ColList + ',''Orphan SomeColumn'');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''Yes'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
'--Assert' + CHAR(10) + 'EXEC ' + @WarehouseDatabase + '.tSQLt.AssertEmptyTable ''zException' + @StageSchema + '.' + @StageTable + ''';' + CHAR(10) + 'GO'
FROM sys.tables a CROSS JOIN @ReprocessTempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Loaded in DWLoadDate order
WITH FirstNon@KeyColumn
AS
(SELECT TOP 1 name
FROM @Column
WHERE KeyColumn = 'No' AND name NOT IN ('Created', 'CreatedBy', 'Deleted', 'LastModified', 'LastModifiedBy', 'ServerExecutionID', 'DWLoadDate', 'RowHash', 'VersionStartTime', 'VersionEndTime')
ORDER BY column_id),
StageValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN col.name = 'Deleted' THEN '0'
                                                    WHEN col.name = 'DWLoadDate' THEN 'DATEADD(dd,1,@Datetime)'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NULL THEN '@GUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NULL THEN '@Char'
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NULL THEN '@Int' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NULL THEN '@Datetime'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NULL THEN '@Decimal' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NULL  THEN '@Date'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NULL  THEN '@Time'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NULL  THEN '@Bit'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NULL  THEN '@Money'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NOT NULL THEN '@UpdateGUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NOT NULL THEN '''B'''
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NOT NULL THEN '2' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Datetime)'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NOT NULL THEN '2.0' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Date)'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NOT NULL THEN 'DATEADD(hh,1,@Time)'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NOT NULL THEN '0'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NOT NULL THEN '2.00'
                                                    WHEN col.DataType IN ('varbinary') THEN '@Bit'
                                                END
            FROM @Column col LEFT OUTER JOIN FirstNon@KeyColumn fcol ON col.name = fcol.name
            WHERE col.name <> 'RowHash'
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 21, 'Exception Reprocess, multiple loaded in date order newest in current unit test','USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + '_ReprocessExceptionMultipleLoadedNewestInCurrent]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0,' + CHAR(10) + '        @UpdateGUID         UNIQUEIDENTIFIER = NEWID();' + CHAR(10) + CHAR(13) + 
'CREATE TABLE #Expected' + CHAR(10) + '(' + b.ColList + ');' + CHAR(10) + CHAR(13) + 
'CREATE TABLE #Actual' + CHAR(10) + '(' + b.ColList + ');' + CHAR(10) + CHAR(13) +
'--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.zException' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ', ErrorDescription)' + CHAR(10) + 'VALUES (' + g.ColList + ',''Orphan SomeColumn'');' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.zException' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ', ErrorDescription)' + CHAR(10) + 'VALUES (' + i.ColList + ',''Orphan SomeColumn'');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'INSERT INTO #Expected' + CHAR(10) + '(' + REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + ')' + CHAR(10) + 'VALUES (' + REPLACE(i.ColList,', @Int, DATEADD(dd,1,@Datetime)','') + ');' + CHAR(10) + CHAR(13) + 
'--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''Yes'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
'INSERT INTO #Actual' + CHAR(10) + '(' +  REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + ')' + CHAR(10) +
'SELECT ' + REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + CHAR(10) + 'FROM ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @StageTable + ';' + CHAR(10) + CHAR(13) + 
'--Assert' + CHAR(10) + 'EXEC tSQLt.AssertEqualsTable #Expected, #Actual;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(10)
FROM sys.tables a CROSS JOIN @ReprocessTempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN StageValueListCTE i
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Oldest in history
WITH FirstNon@KeyColumn
AS
(SELECT TOP 1 name
FROM @Column
WHERE KeyColumn = 'No' AND name NOT IN ('Created', 'CreatedBy', 'Deleted', 'LastModified', 'LastModifiedBy', 'ServerExecutionID', 'DWLoadDate', 'RowHash', 'VersionStartTime', 'VersionEndTime')
ORDER BY column_id),
StageValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN col.name = 'Deleted' THEN '0'
                                                    WHEN col.name = 'DWLoadDate' THEN 'DATEADD(dd,1,@Datetime)'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NULL THEN '@GUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NULL THEN '@Char'
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NULL THEN '@Int' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NULL THEN '@Datetime'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NULL THEN '@Decimal' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NULL  THEN '@Date'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NULL  THEN '@Time'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NULL  THEN '@Bit'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NULL  THEN '@Money'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NOT NULL THEN '@UpdateGUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NOT NULL THEN '''B'''
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NOT NULL THEN '2' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Datetime)'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NOT NULL THEN '2.0' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Date)'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NOT NULL THEN 'DATEADD(hh,1,@Time)'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NOT NULL THEN '0'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NOT NULL THEN '2.00'
                                                    WHEN col.DataType IN ('varbinary') THEN '@Bit'
                                                END
            FROM @Column col LEFT OUTER JOIN FirstNon@KeyColumn fcol ON col.name = fcol.name
            WHERE col.name <> 'RowHash'
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 22, 'Exception Reprocess, multiple loaded in date order oldest in history unit test','USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + '_ReprocessExceptionMultipleLoadedOldestInHistory]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0,' + CHAR(10) + '        @UpdateGUID         UNIQUEIDENTIFIER = NEWID();' + CHAR(10) + CHAR(13) + 
'CREATE TABLE #Expected' + CHAR(10) + '(' + b.ColList + ');' + CHAR(10) + CHAR(13) + 
'CREATE TABLE #Actual' + CHAR(10) + '(' + b.ColList + ');' + CHAR(10) + CHAR(13) +
'--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.zException' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ', ErrorDescription)' + CHAR(10) + 'VALUES (' + g.ColList + ',''Orphan SomeColumn'');' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.zException' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ', ErrorDescription)' + CHAR(10) + 'VALUES (' + i.ColList + ',''Orphan SomeColumn'');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'INSERT INTO #Expected' + CHAR(10) + '(' + REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + ')' + CHAR(10) + 'VALUES (' + REPLACE(g.ColList,', @ServerExecutionID, @Datetime','') + ');' + CHAR(10) + CHAR(13) + 
'--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''Yes'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
'INSERT INTO #Actual' + CHAR(10) + '(' +  REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + ')' + CHAR(10) +
'SELECT ' + REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + CHAR(10) + 'FROM ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @StageTable + 'History;' + CHAR(10) + CHAR(13) + 
'--Assert' + CHAR(10) + 'EXEC tSQLt.AssertEqualsTable #Expected, #Actual;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(10)
FROM sys.tables a CROSS JOIN @ReprocessTempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN StageValueListCTE i
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Exception processing - pulls from exception and not stage
WITH FirstNon@KeyColumn
AS
(SELECT TOP 1 name
FROM @Column
WHERE KeyColumn = 'No' AND name NOT IN ('Created', 'CreatedBy', 'Deleted', 'LastModified', 'LastModifiedBy', 'ServerExecutionID', 'DWLoadDate', 'RowHash', 'VersionStartTime', 'VersionEndTime')
ORDER BY column_id),
StageValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN col.name = 'Deleted' THEN '0'
                                                    WHEN col.name = 'DWLoadDate' THEN 'DATEADD(dd,1,@Datetime)'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NULL THEN '@GUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NULL THEN '@Char'
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NULL THEN '@Int' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NULL THEN '@Datetime'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NULL THEN '@Decimal' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NULL  THEN '@Date'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NULL  THEN '@Time'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NULL  THEN '@Bit'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NULL  THEN '@Money'
                                                    WHEN col.DataType = 'uniqueidentifier' AND fcol.name IS NOT NULL THEN '@UpdateGUID' 
                                                    WHEN col.DataType IN ('char','varchar','nchar','nvarchar') AND fcol.name IS NOT NULL THEN '''B'''
                                                    WHEN col.DataType IN ('tinyint','smallint','int','bigint') AND fcol.name IS NOT NULL THEN '2' 
                                                    WHEN col.DataType IN ('datetime','smalldatetime','datetime2','datetimeoffset') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Datetime)'
                                                    WHEN col.DataType IN ('decimal','numeric','float','real') AND fcol.name IS NOT NULL THEN '2.0' 
                                                    WHEN col.DataType IN ('date') AND fcol.name IS NOT NULL THEN 'DATEADD(dd,1,@Date)'
                                                    WHEN col.DataType IN ('time') AND fcol.name IS NOT NULL THEN 'DATEADD(hh,1,@Time)'
                                                    WHEN col.DataType IN ('bit') AND fcol.name IS NOT NULL THEN '0'
                                                    WHEN col.DataType IN ('money','smallmoney') AND fcol.name IS NOT NULL THEN '2.00'
                                                    WHEN col.DataType IN ('varbinary') THEN '@Bit'
                                                END
            FROM @Column col LEFT OUTER JOIN FirstNon@KeyColumn fcol ON col.name = fcol.name
            WHERE col.name <> 'RowHash'
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertValueListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                END
            FROM @Column
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
    s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID),
FKFakesCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
            FROM FKListCTE
            ORDER BY ParentSchema, ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
FKColCTE
(ParentSchema, ParentTable, name, column_id, DataType)
AS
(SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
    INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
    INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
WHERE c.name <> 'sysname' AND b.is_column_set = 0),
FKInsertColumnListCTE
AS
(SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
    CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                            FROM FKColCTE fkc1
                            WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                            ORDER BY fkc1.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc2),
FKInsertValueListCTE
AS
(SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                END
                            FROM FKColCTE fkc3
                            WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                            ORDER BY fkc3.column_id
                            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
FROM FKColCTE fkc4),
FKTableInsertStatementCTE
AS
(SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
            FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
            ORDER BY fkil.ParentSchema, fkil.ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
INSERT INTO @UnitTest
(TestOrder, Description, UnitTest)
SELECT 23, 'Exception Reprocess, Loaded from exception and not stage','USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + '_ReprocessExceptionLoadedFromExceptionAndNotStage]' + CHAR(10) +
'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
'        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
'        @ServerExecutionID  BIGINT = 0,' + CHAR(10) + '        @UpdateGUID         UNIQUEIDENTIFIER = NEWID();' + CHAR(10) + CHAR(13) + 
'CREATE TABLE #Expected' + CHAR(10) + '(' + b.ColList + ');' + CHAR(10) + CHAR(13) + 
'CREATE TABLE #Actual' + CHAR(10) + '(' + b.ColList + ');' + CHAR(10) + CHAR(13) +
'--Assemble' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @WarehouseDatabase + '.zException' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ', ErrorDescription)' + CHAR(10) + 'VALUES (' + g.ColList + ',''Orphan SomeColumn'');' + CHAR(10) + CHAR(13) + 
'INSERT INTO ' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ')' + CHAR(10) + 'VALUES (' + i.ColList + ');' + CHAR(10) + CHAR(13) + 
CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
'INSERT INTO #Expected' + CHAR(10) + '(' + REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + ')' + CHAR(10) + 'VALUES (' + REPLACE(g.ColList,', @ServerExecutionID, @Datetime','') + ');' + CHAR(10) + CHAR(13) + 
'--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''Yes'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
'INSERT INTO #Actual' + CHAR(10) + '(' +  REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + ')' + CHAR(10) +
'SELECT ' + REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + CHAR(10) + 'FROM ' + @WarehouseDatabase + '.' + @WarehouseSchema + '.' + @WarehouseTable + ';' + CHAR(10) + CHAR(13) + 
CHAR(10) + CHAR(13) + '--Assert' + CHAR(10) + 'EXEC tSQLt.AssertEqualsTable #Expected, #Actual;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(10)
FROM sys.tables a CROSS JOIN @ReprocessTempColumnDef b
    CROSS JOIN @SourceSelectColumnList c
    CROSS JOIN @KeyColumn d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertValueListCTE g
    CROSS JOIN StageValueListCTE i
    CROSS JOIN FKFakesCTE fkf
    CROSS JOIN FKTableInsertStatementCTE fkis
WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Still an exception
SET @FKTestObjectID = NULL;

SELECT @FKTestObjectID = t2.object_id
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
WHERE fk.parent_object_id = @ObjectID;

IF @FKTestObjectID IS NOT NULL
BEGIN;
/************************************************************************************************************************************************************************************/
--Still an exception, not loaded to warehouse
    WITH InsertColumnListCTE
    AS
    (SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
                FROM @Column
                WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                ORDER BY column_id
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
    InsertValueListCTE
    AS
    (SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                    END
                FROM @Column
                WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                ORDER BY column_id
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
    FKListCTE
    AS
    (SELECT DISTINCT 
        'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
        s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
    FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
        INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
        INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
        INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
        INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
    WHERE fk.parent_object_id = @ObjectID),
    FKFakesCTE
    AS
    (SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
                FROM FKListCTE
                ORDER BY ParentSchema, ParentTable
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
    FKColCTE
    (ParentSchema, ParentTable, name, column_id, DataType)
    AS
    (SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
    FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
        INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
        INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
    WHERE c.name <> 'sysname' AND b.is_column_set = 0 AND fkl.ParentObjectID <> @FKTestObjectID),
    FKInsertColumnListCTE
    AS
    (SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
        CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                                FROM FKColCTE fkc1
                                WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                                ORDER BY fkc1.column_id
                                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
    FROM FKColCTE fkc2),
    FKInsertValueListCTE
    AS
    (SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                    END
                                FROM FKColCTE fkc3
                                WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                                ORDER BY fkc3.column_id
                                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
    FROM FKColCTE fkc4),
    FKTableInsertStatementCTE
    AS
    (SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
                FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
                ORDER BY fkil.ParentSchema, fkil.ParentTable
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
    INSERT INTO @UnitTest
    (TestOrder, Description, UnitTest)
    SELECT 24, 'Exception Reprocess, Still an exception, not written to warehouse', 'USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
    'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
    'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + 
    '_ReprocessExceptionStillExceptionWarehouseEmpty]' + CHAR(10) +
    'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
    '        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
    CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
    '        @ServerExecutionID  BIGINT = 0;' + CHAR(10) + CHAR(13) + '--Assemble' + CHAR(10) + 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
    CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
    'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
    'INSERT INTO ' + @WarehouseDatabase + '.zException' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ', ErrorDescription)' + CHAR(10) + 'VALUES (' + g.ColList + ',''Orphan SomeColumn'');' + CHAR(10) + CHAR(13) + 
    CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
    '--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''Yes'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
    '--Assert' + CHAR(10) + 'EXEC ' + @WarehouseDatabase + '.tSQLt.AssertEmptyTable ''' + @WarehouseSchema + '.' + @WarehouseTable + ''';' + CHAR(10) + 'GO'
    FROM sys.tables a CROSS JOIN @ReprocessTempColumnDef b
        CROSS JOIN @SourceSelectColumnList c
        CROSS JOIN @KeyColumn d
        CROSS JOIN InsertColumnListCTE f
        CROSS JOIN InsertValueListCTE g
        CROSS JOIN FKFakesCTE fkf
        CROSS JOIN FKTableInsertStatementCTE fkis
    WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Still an exception, not loaded to history
    WITH InsertColumnListCTE
    AS
    (SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
                FROM @Column
                WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                ORDER BY column_id
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
    InsertValueListCTE
    AS
    (SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                    END
                FROM @Column
                WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                ORDER BY column_id
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
    FKListCTE
    AS
    (SELECT DISTINCT 
        'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
        s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
    FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
        INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
        INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
        INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
        INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
    WHERE fk.parent_object_id = @ObjectID),
    FKFakesCTE
    AS
    (SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
                FROM FKListCTE
                ORDER BY ParentSchema, ParentTable
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
    FKColCTE
    (ParentSchema, ParentTable, name, column_id, DataType)
    AS
    (SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
    FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
        INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
        INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
    WHERE c.name <> 'sysname' AND b.is_column_set = 0 AND fkl.ParentObjectID <> @FKTestObjectID),
    FKInsertColumnListCTE
    AS
    (SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
        CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                                FROM FKColCTE fkc1
                                WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                                ORDER BY fkc1.column_id
                                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
    FROM FKColCTE fkc2),
    FKInsertValueListCTE
    AS
    (SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                    END
                                FROM FKColCTE fkc3
                                WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                                ORDER BY fkc3.column_id
                                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
    FROM FKColCTE fkc4),
    FKTableInsertStatementCTE
    AS
    (SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
                FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
                ORDER BY fkil.ParentSchema, fkil.ParentTable
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
    INSERT INTO @UnitTest
    (TestOrder, Description, UnitTest)
    SELECT 25, 'Exception Reprocess, Still an exception, not written to history', 'USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
    'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
    'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + 
    '_ReprocessExceptionStillExceptionHistoryEmpty]' + CHAR(10) +
    'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
    '        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
    CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
    '        @ServerExecutionID  BIGINT = 0;' + CHAR(10) + CHAR(13) + '--Assemble' + CHAR(10) + 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
    CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
    'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
    'INSERT INTO ' + @WarehouseDatabase + '.zException' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ', ErrorDescription)' + CHAR(10) + 'VALUES (' + g.ColList + ',''Orphan SomeColumn'');' + CHAR(10) + CHAR(13) + 
    CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
    '--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''Yes'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
    '--Assert' + CHAR(10) + 'EXEC ' + @WarehouseDatabase + '.tSQLt.AssertEmptyTable ''' + @WarehouseSchema + '.' + @WarehouseTable + 'History'';' + CHAR(10) + 'GO'
    FROM sys.tables a CROSS JOIN @ReprocessTempColumnDef b
        CROSS JOIN @SourceSelectColumnList c
        CROSS JOIN @KeyColumn d
        CROSS JOIN InsertColumnListCTE f
        CROSS JOIN InsertValueListCTE g
        CROSS JOIN FKFakesCTE fkf
        CROSS JOIN FKTableInsertStatementCTE fkis
    WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;

/************************************************************************************************************************************************************************************/
--Still an exception, not removed from exception
    WITH InsertColumnListCTE
    AS
    (SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
                FROM @Column
                WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                ORDER BY column_id
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
    InsertValueListCTE
    AS
    (SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + CASE WHEN name = 'ServerExecutionID' THEN '@ServerExecutionID' 
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
                                                    END
                FROM @Column
                WHERE name NOT IN ('RowHash','VersionStartTime','VersionEndTime')
                ORDER BY column_id
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
    FKListCTE
    AS
    (SELECT DISTINCT 
        'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal @SchemaName = ''' + s2.name + ''', @TableName = ''' + t2.name + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' ParentTableFakes, 
        s2.name ParentSchema, t2.name ParentTable, t2.object_id ParentObjectID 
    FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
        INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
        INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
        INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
        INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
        INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
    WHERE fk.parent_object_id = @ObjectID),
    FKFakesCTE
    AS
    (SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + ParentTableFakes
                FROM FKListCTE
                ORDER BY ParentSchema, ParentTable
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') FKFakes),
    FKColCTE
    (ParentSchema, ParentTable, name, column_id, DataType)
    AS
    (SELECT DISTINCT fkl.ParentSchema, fkl.ParentTable, b.name, b.column_id, c.name DataType
    FROM FKListCTE fkl INNER JOIN EZLynxWarehouse.sys.tables a ON fkl.ParentObjectID = a.object_id
        INNER JOIN EZLynxWarehouse.sys.columns b ON a.object_id = b.object_id
        INNER JOIN EZLynxWarehouse.sys.types c ON b.system_type_id = c.system_type_id 
    WHERE c.name <> 'sysname' AND b.is_column_set = 0 AND fkl.ParentObjectID <> @FKTestObjectID),
    FKInsertColumnListCTE
    AS
    (SELECT DISTINCT fkc2.ParentSchema, fkc2.ParentTable,
        CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + fkc1.name
                                FROM FKColCTE fkc1
                                WHERE fkc1.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc1.ParentSchema = fkc2.ParentSchema AND fkc1.ParentTable = fkc2.ParentTable
                                ORDER BY fkc1.column_id
                                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
    FROM FKColCTE fkc2),
    FKInsertValueListCTE
    AS
    (SELECT DISTINCT fkc4.ParentSchema, fkc4.ParentTable,
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
                                                    END
                                FROM FKColCTE fkc3
                                WHERE fkc3.name NOT IN ('RowHash','VersionStartTime','VersionEndTime') AND fkc3.ParentSchema = fkc4.ParentSchema AND fkc3.ParentTable = fkc4.ParentTable
                                ORDER BY fkc3.column_id
                                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList
    FROM FKColCTE fkc4),
    FKTableInsertStatementCTE
    AS
    (SELECT REPLACE(CAST(LTRIM(RTRIM(STUFF((SELECT ';' + 'INSERT INTO ' + @WarehouseDatabase + '.' + fkil.ParentSchema + '.' + fkil.ParentTable + CHAR(10) + '(' + fkil.ColList + ')' + CHAR(10) + 'VALUES (' + fkiv.ColList + ');'
                FROM FKInsertColumnListCTE fkil INNER JOIN FKInsertValueListCTE fkiv ON fkil.ParentSchema = fkiv.ParentSchema AND fkil.ParentTable = fkiv.ParentTable
                ORDER BY fkil.ParentSchema, fkil.ParentTable
                FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)),';;',';') AS InsertStatement)
    INSERT INTO @UnitTest
    (TestOrder, Description, UnitTest)
    SELECT 26, 'Exception Reprocess, Still an exception, row still exists in exception', 'USE [Stage]' + CHAR(10) + 'GO' + CHAR(10) + 'SET ANSI_NULLS ON' + CHAR(10) + 'GO' + CHAR(10) + 'SET QUOTED_IDENTIFIER ON' + CHAR(10) + 'GO' + CHAR(10) + 
    'IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = ''z' + @StageSchema + 'Test'')' + CHAR(10) + 'BEGIN' + CHAR(10) + '    EXEC sp_executesql N''CREATE SCHEMA z' + @StageSchema + 
    'Test AUTHORIZATION dbo'';' + CHAR(10) + 'END;' + CHAR(10) + 'GO' + CHAR(10) + CHAR(13) + 'CREATE PROCEDURE [z' + @StageSchema + 'Test].[test Merge' + @StageTable + 
    '_ReprocessExceptionStillExceptionRowStillExistsInException]' + CHAR(10) +
    'AS' + CHAR(10) + 'DECLARE @GUID               UNIQUEIDENTIFIER = NEWID(),' + CHAR(10) + '        @Char               CHAR(1) = ''A'','  + CHAR(10) + '        @Int                INT = 1,' + CHAR(10) + 
    '        @Datetime           DATETIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Decimal            DECIMAL(18,10) = 1.0,' + CHAR(10) + '        @Date               DATE = CURRENT_TIMESTAMP,' + 
    CHAR(10) + '        @Time               TIME = CURRENT_TIMESTAMP,' + CHAR(10) + '        @Bit                BIT = 1,' + CHAR(10) + '        @Money              MONEY = 1.00,' + CHAR(10) + 
    '        @ServerExecutionID  BIGINT = 0;' + CHAR(10) + CHAR(13) + 'CREATE TABLE #Expected' + CHAR(10) + '(' + b.ColList + CHAR(10) + ');' + 
    CHAR(10) + CHAR(13) + 'CREATE TABLE #Actual' + CHAR(10) + '(' + b.ColList + CHAR(10) + ');' + CHAR(10) + CHAR(13) + '--Assemble' + CHAR(10) + 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @WarehouseSchema + ''', @TableName = ''' + @WarehouseTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
    'EXEC ' + @WarehouseDatabase + '.tSQLt.FakeTableTemporal ' + '@SchemaName = ''zException' + @StageSchema + ''', @TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + 
    CASE WHEN fkf.FKFakes IS NOT NULL THEN REPLACE(fkf.FKFakes,';',';' + CHAR(10)) ELSE '' END + 
    'EXEC tSQLt.FakeTableTemporal ' + '@SchemaName = ''' + @StageSchema + ''',@TableName = ''' + @StageTable + ''', @Identity = 1, @ComputedColumns = 1, @Defaults = 1, @PreserveNullability = 1, @PreservePrimaryKey = 1, @PreserveTemporal = 1;' + CHAR(10) + CHAR(13) + 
    'INSERT INTO ' + @WarehouseDatabase + '.zException' + @StageSchema + '.' + @StageTable + CHAR(10) + '(' + f.ColList + ', ErrorDescription)' + CHAR(10) + 'VALUES (' + g.ColList + ',''Orphan SomeColumn'');' + CHAR(10) + CHAR(13) + 
    CASE WHEN fkis.InsertStatement IS NOT NULL THEN REPLACE(fkis.InsertStatement,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
    'INSERT INTO #Expected' + CHAR(10) + '(' + REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + ')' + CHAR(10) + 'VALUES (' + REPLACE(g.ColList,', @ServerExecutionID, @Datetime','') + ');' + CHAR(10) + CHAR(13) + 
    '--Act' + CHAR(10) + 'EXEC ' + @StageSchema + '.Merge' +  @StageTable + ' @ProcessExceptions = ''Yes'', @ServerExecutionID = 0;' + CHAR(10) + CHAR(13) + 
    'INSERT INTO #Actual' + CHAR(10) + '(' +  REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + ')' + CHAR(10) +
    'SELECT ' + REPLACE(f.ColList,', ServerExecutionID, DWLoadDate','') + CHAR(10) + 'FROM ' + @WarehouseDatabase + '.zException' + @StageSchema + '.' + @StageTable + ';' + CHAR(10) + CHAR(13) + 
    '--Assert' + CHAR(10) + 'EXEC tSQLt.AssertEqualsTable #Expected, #Actual;' + CHAR(10) + 'GO'
    FROM sys.tables a CROSS JOIN @ReprocessTempColumnDef b
        CROSS JOIN @SourceSelectColumnList c
        CROSS JOIN @KeyColumn d
        CROSS JOIN InsertColumnListCTE f
        CROSS JOIN InsertValueListCTE g
        CROSS JOIN FKFakesCTE fkf
        CROSS JOIN FKTableInsertStatementCTE fkis
    WHERE a.schema_id = SCHEMA_ID(@StageSchema) AND name = @StageTable;
END;

SELECT Description, UnitTest 
FROM @UnitTest
ORDER BY TestOrder, Description;