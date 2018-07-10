DECLARE @SourceSchema           sysname = 'Policy',
        @SourceTable            sysname = 'TransactionDetailHist',
        @TargetDatabase         sysname = 'EZLynxWarehouse',
        @TargetSchema           sysname = 'Policy',
        @TargetTable            sysname = 'TransactionDetailHist',
        @SchemaID               INT,
        @ObjectID               INT;

SELECT @SchemaID = schema_id
FROM EZLynxWarehouse.sys.schemas
WHERE name = @TargetSchema;

SELECT @ObjectID = object_id
FROM EZLynxWarehouse.sys.tables
WHERE schema_id = @SchemaID AND name = @TargetTable;

WITH ColCTE AS
(SELECT DISTINCT  CASE WHEN b.name LIKE '%-%' THEN '['+b.name+']' ELSE b.name END name, b.column_id, CASE WHEN b.column_id = e.column_id THEN 'Yes' ELSE 'No' END KeyColumn, 
'<datatypespace>' + UPPER(c.name) + CASE WHEN c.name IN ('nvarchar','nchar') THEN '(' + REPLACE(CAST(b.max_length/2 AS VARCHAR(30)),'-1','MAX') + ')'
                    WHEN c.name IN ('varchar','char') THEN '(' + REPLACE(CAST(b.max_length AS VARCHAR(30)),'-1','MAX') + ')'
                    WHEN c.name IN ('decimal','numeric') THEN '(' + CAST(b.precision AS VARCHAR(30)) + ',' + CAST(b.scale AS VARCHAR(30)) + ')' 
                    ELSE '' END  + '<nullspace>' + CASE WHEN b.is_nullable = 1 THEN 'NULL' ELSE 'NOT NULL' END ColDef, c.name DataType, LEN(b.name) ColumnNameLength,
LEN(UPPER(c.name) + CASE WHEN c.name IN ('nvarchar','nchar') THEN '(' + REPLACE(CAST(b.max_length/2 AS VARCHAR(30)),'-1','MAX') + ')'
                    WHEN c.name IN ('varchar','char') THEN '(' + REPLACE(CAST(b.max_length AS VARCHAR(30)),'-1','MAX') + ')'
                    WHEN c.name IN ('decimal','numeric') THEN '(' + CAST(b.precision AS VARCHAR(30)) + ',' + CAST(b.scale AS VARCHAR(30)) + ')' 
                    ELSE '' END) DataTypeLength
FROM sys.tables a INNER JOIN sys.columns b ON a.object_id = b.object_id
    INNER JOIN sys.types c ON b.system_type_id = c.system_type_id 
    LEFT OUTER JOIN sys.indexes d ON b.object_id = d.object_id
    LEFT OUTER JOIN sys.index_columns e ON d.object_id = e.object_id AND d.index_id = e.index_id AND e.column_id = b.column_id
WHERE a.schema_id = SCHEMA_ID(@SourceSchema) AND a.name = @SourceTable AND d.is_primary_key = 1 AND c.name <> 'sysname' AND b.is_column_set = 0),
DeletedExistsCTE
AS
(SELECT MAX(CASE WHEN name = 'Deleted' THEN 1 ELSE 0 END) DeleteExists
FROM ColCTE),
SourceSelectColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM ColCTE
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) SelectColList),
KeyColumnCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ' AND tgt.' + name + ' = src.' + name
            FROM ColCTE
            WHERE KeyColumn = 'Yes'
            ORDER BY column_id
            FOR XML PATH ('')),1,4,''))) AS VARCHAR(MAX)) ColList),
UpdateSetClauseCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', tgt.' + name + ' = src.' + name
            FROM ColCTE
            WHERE name NOT IN ('RowHash') AND KeyColumn = 'No'
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', ' + name
            FROM ColCTE
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
InsertSourceColumnListCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ', src.' + name
            FROM ColCTE
            WHERE name NOT IN ('RowHash')
            ORDER BY column_id
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) ColList),
FKListCTE
AS
(SELECT DISTINCT '        WITH OrphanCTE' + CHAR(10) + '        AS' + CHAR(10) + '        (SELECT ' + c2.name + CHAR(10) + '        FROM ' + @SourceSchema + '.' + @SourceTable + CHAR(10) + '        EXCEPT' + CHAR(10) + '        SELECT ' + c1.name + CHAR(10) + 
    '        FROM ' + @TargetDatabase + '.' + s2.name + '.' + t2.name + ')' + CHAR(10) + '        DELETE FROM s' + CHAR(10) + '        FROM ' + @SourceSchema + '.' + @SourceTable + ' s INNER JOIN OrphanCTE o ON s.' + c2.name + ' = o.' + c2.name FKCheckExceptionBranch,
    '    WITH OrphanCTE' + CHAR(10) + '    AS' + CHAR(10) + '    (SELECT ' + c2.name + CHAR(10) + '    FROM ' + @SourceSchema + '.' + @SourceTable + CHAR(10) + '    EXCEPT' + CHAR(10) + '    SELECT ' + c1.name + CHAR(10) + 
    '    FROM ' + @TargetDatabase + '.' + s2.name + '.' + t2.name + ')' + CHAR(10) + '    DELETE FROM s' + CHAR(10) +  '    OUTPUT deleted.' + REPLACE(REPLACE(sscl.SelectColList,', RowHash',''),', ',', deleted.') + ', 0 ErrorCode, 0 ErrorColumn, ''Orphan ' + c2.name + ''' ErrorDescription' + CHAR(10) + 
    '    INTO ' + @TargetDatabase + '.' + 'zException' + @SourceSchema + '.' + @SourceTable + CHAR(10) + '    (' + REPLACE(sscl.SelectColList,', RowHash','') + ', ErrorCode, ErrorColumn, ErrorDescription)' + CHAR(10) + 
    '    FROM ' + @SourceSchema + '.' + @SourceTable + ' s INNER JOIN OrphanCTE o ON s.' + c2.name + ' = o.' + c2.name FKCheckMainBranch, 
    s2.name ParentSchema, t2.name ParentTable, s1.name ChildSchemaName, t1.name ChildTableName, c1.name ParentKey, c2.name ChildKey 
FROM EZLynxWarehouse.sys.foreign_keys fk INNER JOIN EZLynxWarehouse.sys.tables t1 ON fk.parent_object_id = t1.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s1 ON t1.schema_id = s1.schema_id
    INNER JOIN EZLynxWarehouse.sys.tables t2 ON fk.referenced_object_id = t2.object_id
    INNER JOIN EZLynxWarehouse.sys.schemas s2 ON t2.schema_id = s2.schema_id
    INNER JOIN EZLynxWarehouse.sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    INNER JOIN EZLynxWarehouse.sys.columns c1 ON fkc.referenced_object_id = c1.object_id AND fkc.referenced_column_id = c1.column_id
    INNER JOIN EZLynxWarehouse.sys.columns c2 ON fkc.parent_object_id = c2.object_id AND fkc.parent_column_id = c2.column_id
    CROSS JOIN SourceSelectColumnListCTE sscl
WHERE fk.parent_object_id = @ObjectID),
FKExceptionBranchCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ';' + FKCheckExceptionBranch
            FROM FKListCTE
            ORDER BY ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) + ';' FKExceptionList),
FKMainBranchCTE
AS
(SELECT CAST(LTRIM(RTRIM(STUFF((SELECT ';' + FKCheckMainBranch
            FROM FKListCTE
            ORDER BY ParentTable
            FOR XML PATH ('')),1,1,''))) AS VARCHAR(MAX)) + ';' FKMainList)
SELECT 'CREATE PROCEDURE ' + @SourceSchema + '.Merge' + @SourceTable + ' @ProcessExceptions CHAR(3), @ServerExecutionID BIGINT' + CHAR(10) + 'AS' + CHAR(10) +
    'SET NOCOUNT ON;' + CHAR(10) + 'DECLARE @LoadDate       DATETIME2;' + CHAR(10) + CHAR(13) + 
    'IF @ProcessExceptions = ''Yes''' + CHAR(10) + 'BEGIN' + CHAR(10) + '    DECLARE @ExceptionProcess TABLE' + CHAR(10) + '    (LoadDate   DATETIME2    NOT NULL);' + CHAR(10) + 'END;' + CHAR(10) + CHAR(13) +
    'IF @ProcessExceptions = ''Yes''' + CHAR(10) + 'BEGIN' + CHAR(10) + '    INSERT INTO @ExceptionProcess' + 
    CHAR(10) + '    (LoadDate)' + CHAR(10) + '    SELECT DISTINCT DWLoadDate' + CHAR(10) + '    FROM ' + @TargetDatabase + '.zException' + @SourceSchema + '.' + @SourceTable + CHAR(10) + '    WHERE ErrorDescription LIKE ''Orphan%' + ''';' + CHAR(10) + CHAR(13) + 
    '    SELECT @LoadDate = MIN(LoadDate)' + CHAR(10) + '    FROM @ExceptionProcess;' + CHAR(10) + CHAR(13) + '    WHILE @LoadDate IS NOT NULL' + 
    CHAR(10) + '    BEGIN' + CHAR(10) + '        DELETE FROM @ExceptionProcess' + CHAR(10) + '        WHERE LoadDate = @LoadDate;' + CHAR(10) + CHAR(13) + '        TRUNCATE TABLE ' + @SourceSchema + '.' + 
    @SourceTable + ';' + CHAR(10) + CHAR(13) + '        INSERT INTO ' + @SourceSchema + '.' + @SourceTable + CHAR(10) + '        (' + 
    f.ColList + ')' + CHAR(10) + '        SELECT DISTINCT ' + REPLACE(REPLACE(f.ColList,'ServerExecutionID, ',''),'DWLoadDate','') + '@ServerExecutionID, CURRENT_TIMESTAMP' + CHAR(10) + 
    '        FROM ' + @TargetDatabase + '.zException' + @SourceSchema + '.' + @SourceTable + CHAR(10) + 
    '        WHERE DWLoadDate = @LoadDate AND ErrorDescription LIKE ''Orphan%' + ''';' + CHAR(10) + CHAR(13) +
    CASE WHEN fke.FKExceptionList IS NOT NULL THEN '        --Foreign key check' + CHAR(10) + '        ' + REPLACE(fke.FKExceptionList,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
    '        WITH SourceCTE' + CHAR(10) + '        AS' + CHAR(10) + '        (SELECT ' + c.SelectColList + CHAR(10) + '        FROM ' + @SourceSchema + '.' + @SourceTable + ')' + CHAR(10) + 
    '        MERGE INTO ' + @TargetDatabase + '.' + @TargetSchema + '.' + @TargetTable + ' WITH (HOLDLOCK) AS tgt' + CHAR(10) +
    '        USING SourceCTE AS src ON ' + d.ColList + CHAR(10) + 
    '        WHEN MATCHED AND src.RowHash <> tgt.RowHash THEN' + CHAR(10) +
    '            UPDATE' + CHAR(10) + '            SET ' + REPLACE(u.ColList,',' ,',' + CHAR(10) + '               ') + CHAR(10) +
    '        WHEN NOT MATCHED THEN' + CHAR(10) + '            INSERT (' + f.ColList + ')' + CHAR(10) + '            VALUES(' + g.ColList  + ');' + CHAR(10) + CHAR(13) +
    '        --Cleanup exception table' + CHAR(10) + '        DELETE FROM e' + CHAR(10) + '        FROM ' + @TargetDatabase + '.zException' + @SourceSchema + '.' + @SourceTable + ' e INNER JOIN ' + @SourceSchema + '.' + @SourceTable + ' s ON ' + 
    REPLACE(REPLACE(d.ColList,'tgt.','e.'),'src.','s.') + ' AND e.DWLoadDate = @LoadDate;' + CHAR(10) + CHAR(13) +
    '        SELECT @LoadDate = MIN(LoadDate)' + CHAR(10) + '        FROM @ExceptionProcess;' + CHAR(10) + '    END;' +
    CHAR(10) + 'END;' + CHAR(10) + 'ELSE' + CHAR(10) + 'BEGIN' + CHAR(10) + 
    CASE WHEN fkm.FKMainList IS NOT NULL THEN '    --Foreign key check' + CHAR(10) + '    ' + REPLACE(fkm.FKMainList,';',';' + CHAR(10) + CHAR(13)) ELSE '' END + 
    '    WITH SourceCTE' + CHAR(10) + '    AS' + CHAR(10) + '    (SELECT ' + c.SelectColList + CHAR(10) + '    FROM ' + @SourceSchema + '.' + @SourceTable + ')' + CHAR(10) + 
    '    MERGE INTO ' + @TargetDatabase + '.' + @TargetSchema + '.' + @TargetTable + ' WITH (HOLDLOCK) AS tgt' + CHAR(10) +
    '    USING SourceCTE AS src ON ' + d.ColList + CHAR(10) + 
    '    WHEN MATCHED AND src.RowHash <> tgt.RowHash THEN' + CHAR(10) +
    '        UPDATE' + CHAR(10) + '        SET ' + REPLACE(u.ColList,',' ,',' + CHAR(10) + '           ') + CHAR(10) +
    '    WHEN NOT MATCHED THEN' + CHAR(10) + '        INSERT (' + f.ColList + ')' + CHAR(10) + '        VALUES(' + g.ColList  + ');' + CHAR(10) + 'END;'
FROM sys.tables a CROSS JOIN SourceSelectColumnListCTE c
    CROSS JOIN KeyColumnCTE d
    CROSS JOIN InsertColumnListCTE f
    CROSS JOIN InsertSourceColumnListCTE g
    CROSS JOIN UpdateSetClauseCTE u
    CROSS JOIN DeletedExistsCTE de
    CROSS JOIN FKExceptionBranchCTE fke 
    CROSS JOIN FKMainBranchCTE fkm
WHERE a.schema_id = SCHEMA_ID(@SourceSchema) AND a.name = @SourceTable;
