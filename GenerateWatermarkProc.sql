DECLARE @TargetDatabase     sysname = 'EZLynxWarehouse',
        @TargetSchema       sysname,
        @TargetTable        sysname,
        @WatermarkColumn    sysname;

DECLARE @Statement TABLE
(TableName  NVARCHAR(256)   NOT NULL,
Statement   NVARCHAR(MAX)   NOT NULL);

DECLARE curwatermark CURSOR FOR 
    WITH TestCTE
    AS
    (SELECT SCHEMA_NAME(t.schema_id) schemaname, t.name tablename, c.name columnname
    FROM sys.tables t INNER JOIN sys.columns c ON t.object_id = c.object_id
    WHERE c.name IN ('LastModified','LastModifiedDateTime','LastModDate', 'DateLastModified', 'LastChange') AND SCHEMA_NAME(t.schema_id) NOT LIKE 'zException%')
    SELECT SCHEMA_NAME(t.schema_id) schemaname, t.name tablename, c.name columnname
    FROM sys.tables t INNER JOIN sys.columns c ON t.object_id = c.object_id
    WHERE c.name IN ('Created','ActionDateTime','LastViewDateTime','LastViewed','SECreatedDateTime','CreatedDateTime','LogDate','DateCreated','AssignmentModifiedDate')
        AND t.name NOT IN (SELECT tablename FROM TestCTE) AND SCHEMA_NAME(t.schema_id) NOT LIKE 'zException%'
    UNION
    SELECT TestCTE.schemaname, TestCTE.tablename, TestCTE.columnname 
    FROM TestCTE
    ORDER BY 1,2,3
--Generate for full load (no watermark column exists)
--SELECT schemaname, tablename, columnname
--FROM (VALUES ('EZLynx','AddressType','DWLoadDate'), ('EZLynx','ApplicantAddressType','DWLoadDate'), ('EZLynx','ApplicantType','DWLoadDate'), ('EZLynx','AttachmentType','DWLoadDate'),
--    ('EZLynx','City','DWLoadDate'), ('EZLynx','Contact','DWLoadDate'), ('EZLynx','ContactType','DWLoadDate'), ('EZLynx','Country','DWLoadDate'), ('EZLynx','County','DWLoadDate'),
--    ('EZLynx','CustomerAlertType','DWLoadDate'), ('EZLynx','CyberSourceList','DWLoadDate'), ('EZLynx','Education','DWLoadDate'), ('EZLynx','EzLynxDBTable','DWLoadDate'), ('EZLynx','Gender','DWLoadDate'),
--    ('EZLynx','Industry','DWLoadDate'), ('EZLynx','LicenseClass','DWLoadDate'), ('EZLynx','LicenseType','DWLoadDate'), ('EZLynx','LicenseUserGroup','DWLoadDate'), ('EZLynx','ManagementSystem','DWLoadDate'),
--    ('EZLynx','MaritalStatus','DWLoadDate'), ('EZLynx','MessageActionTypes','DWLoadDate'), ('EZLynx','MessageComments','DWLoadDate'), ('EZLynx','MessageRecipientTypes','DWLoadDate'), ('EZLynx','MessageStatusChanges','DWLoadDate'),
--    ('EZLynx','MessageStatusTypes','DWLoadDate'), ('EZLynx','MessageTypes','DWLoadDate'), ('EZLynx','MimeType','DWLoadDate'), ('EZLynx','MonthlyOrganizationProductUsage','DWLoadDate'), ('EZLynx','Occupation','DWLoadDate'),
--    ('EZLynx','OrganizationType','DWLoadDate'), ('EZLynx','Permission','DWLoadDate'), ('EZLynx','PhoneType','DWLoadDate'), ('EZLynx','Prefix','DWLoadDate'), ('EZLynx','Product','DWLoadDate'), ('EZLynx','PromptType','DWLoadDate'),
--    ('EZLynx','Provider','DWLoadDate'), ('EZLynx','Relationship','DWLoadDate'), ('EZLynx','ResidenceType','DWLoadDate'), ('EZLynx','SalesProductQuote','DWLoadDate'), ('EZLynx','State','DWLoadDate'), ('EZLynx','Status','DWLoadDate'),
--    ('EZLynx','Suffix','DWLoadDate'),('EZLynx','TxErrorClass','DWLoadDate'), ('EZLynx','UserRole','DWLoadDate'), ('EZLynx','Validation','DWLoadDate'), ('Policy','Al3FileType','DWLoadDate'), ('Policy','AL3TransactionType','DWLoadDate'),
--    ('Policy','ClaimPaymentType','DWLoadDate'), ('Policy','ClaimStatus','DWLoadDate'), ('Policy','InterestType','DWLoadDate'), ('Policy','NAICCodeMaster','DWLoadDate'), ('Policy','ProcessStatus','DWLoadDate'),
--    ('Policy','ProcessStep','DWLoadDate'), ('Policy','ProducerCodeMapping','DWLoadDate'), ('Policy','ProducerType','DWLoadDate'), ('Policy','State','DWLoadDate')) AS Watermark(schemaname, tablename, columnname)
--ORDER BY 1,2,3
FOR READ ONLY;

OPEN curwatermark;
FETCH curwatermark INTO @TargetSchema, @TargetTable, @WatermarkColumn;

WHILE @@FETCH_STATUS = 0
BEGIN
    INSERT INTO @Statement
    (TableName, Statement)
    SELECT @TargetSchema + '.' + @TargetTable, 'CREATE PROCEDURE ' + @TargetSchema + '.UpdateWatermarkFor' + @TargetTable + 
        ' @ApplicationName VARCHAR(128), @TaskName VARCHAR(128), @InstanceName VARCHAR(128), @DatabaseName VARCHAR(128)' + CHAR(10) + 'AS' + CHAR(10) +
        'SET NOCOUNT ON;' + CHAR(10) + CHAR(13) + 'DECLARE @LoadWatermark   DATETIME2;' + CHAR(10) + CHAR(13) + 
        'IF EXISTS (SELECT 1 FROM ' + @TargetSchema + '.' + @TargetTable + ')' + CHAR(10) + 
        'BEGIN' + CHAR(10) + 
        '    SELECT @LoadWatermark = MAX(' + @WatermarkColumn + ')' + CHAR(10) +
        '    FROM ' + @TargetDatabase + '.' + @TargetSchema + '.' + @TargetTable + CHAR(10) + CHAR(13) + 
        '    IF @LoadWatermark IS NOT NULL' + CHAR(10) + 
        '    BEGIN' + CHAR(10) + 
        '        UPDATE a' + CHAR(10) + 
        '        SET a.LoadWatermark = @LoadWatermark' + CHAR(10) + 
        '        FROM EZLynxWarehouse.ETL.LoadWatermark a INNER JOIN EZLynxWarehouse.ETL.LoadTask b ON a.TaskID = b.TaskID' + CHAR(10) + 
        '            INNER JOIN EZLynxWarehouse.ETL.SourceInstanceXrefLoadDatabase c ON a.DatabaseID = c.DatabaseID' + CHAR(10) + 
        '            INNER JOIN EZLynxWarehouse.ETL.LoadDatabase d ON c.DatabaseName = d.DatabaseName' + CHAR(10) + 
        '        WHERE b.TaskName = @TaskName AND c.InstanceName = @InstanceName AND c.DatabaseName = @DatabaseName;' + CHAR(10) + 
        '    END;' + CHAR(10) + 
        'END;';

    FETCH curwatermark INTO @TargetSchema, @TargetTable, @WatermarkColumn;
END;

CLOSE curwatermark;
DEALLOCATE curwatermark;

SELECT TableName, Statement 
FROM @Statement
ORDER BY TableName;
GO
