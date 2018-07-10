SELECT  
'IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE OBJECT_SCHEMA_NAME(object_id) = ''' + SCHEMA_NAME(t.schema_id) + ''' AND OBJECT_NAME(object_id) = ''' + wc.TableName + ''' AND name = ''infx_Watermark'')' + CHAR(10) +
'BEGIN' + CHAR(10) + 
'    CREATE NONCLUSTERED INDEX infx_Watermark ON ' + SCHEMA_NAME(t.schema_id) + '.' + wc.TableName + ' (' + wc.ColumnName + ') WHERE ' + wc.ColumnName + ' >= ''20180601''' + ';' + CHAR(10) + CHAR(13) +
'    IF EXISTS (SELECT 1 FROM sys.indexes WHERE OBJECT_SCHEMA_NAME(object_id) = ''' + SCHEMA_NAME(t.schema_id) + ''' AND OBJECT_NAME(object_id) = ''' + wc.TableName + ''' AND name = ''infx_Watermark'')' + CHAR(10) + 
'    BEGIN' + CHAR(10) + 
'        PRINT ''<<< SUCCESSFULLY Added infx_Watermark TO ' + SCHEMA_NAME(t.schema_id) + '.' + wc.TableName + '>>>'';' + CHAR(10) + 
'    END;' + CHAR(10) + 
'    ELSE' + CHAR(10) + 
'    BEGIN' + CHAR(10) + 
'        PRINT ''<<< FAILED Adding infx_Watermark TO ' + SCHEMA_NAME(t.schema_id) + '.' + wc.TableName + '>>>'';' + CHAR(10) + 
'    END;' + CHAR(10) + 
'END;' + CHAR(10) + 
'GO' + CHAR(10), wc.SchemaName, wc.TableName, wc.ColumnName, t.name
FROM ETL.WatermarkColumn wc LEFT OUTER JOIN sys.tables t ON wc.TableName = t.name AND SCHEMA_NAME(t.schema_id) NOT LIKE 'z%'
WHERE wc.ColumnName IS NOT NULL 
ORDER BY wc.SchemaName, wc.TableName
