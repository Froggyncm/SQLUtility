
/*Find last update on tables in a database*/

Use FileImport;
GO

select OBJECT_NAME(object_id), last_user_update
FROM sys.dm_db_index_usage_stats
Where database_id = DB_ID('FileImport')
and last_user_update < '20180205'
order by 1;
