/*FILESTEAM must be enabled on the server first*/



/***************************************************************************************************************************************************************/
/*This examle is creating a database and adding a table that has a filestream column*/
/**************************************************************************************************************************************************************/
--Create the Database
CREATE DATABASE EmployeeRecords
ON 
PRIMARY ( NAME = EmpRec1,  --defines the logical name and where primary database file will reside
    FILENAME = 'c:\EmployeeRecords\EmpRec1.mdf'),
FILEGROUP FileStreamGroup1 CONTAINS FILESTREAM( NAME = EmpRec2,  --Defines the logical name and where the 'files' will reside
    FILENAME = 'c:\EmployeeRecords\filestream1')
LOG ON  ( NAME = EmpRecLog1,    --Defines the logical name and where the log file will be stored
    FILENAME = 'c:\EmployeeRecords\EmpReclog1.ldf')
GO

--Use database just created
USE EmployeeRecords;
GO

--Run to confirm if filesteam is enabled on any database on the server
--the first column will tell you the file level access and the second will tell you the access
SELECT DB_NAME(database_id),
non_transacted_access,
non_transacted_access_desc
FROM sys.database_filestream_options;
GO

--Create Schema or use dbo
CREATE SCHEMA Test AUTHORIZATION dbo

--Create table that will have a FILESTREAM column
CREATE TABLE Test.EmployeeJobs
(EmployeeJobsID	UNIQUEIDENTIFIER	ROWGUIDCOL					NOT NULL UNIQUE,  -- Must have a column that is uniqueidentifer, rowguidcol and be unique 
 Description						VARCHAR(50)					NOT NULL,  --normal column, not required
 JobDocument						VARBINARY(MAX)	FILESTREAM	NULL  --FILESTREAM Column
 );
 GO


 --Insert a row into the table using a simple text file
 INSERT INTO Test.EmployeeJobs
 (EmployeeJobsID,Description,JobDocument)
 VALUES
 (NEWID(),
  'TestJob',
  (SELECT * FROM OPENROWSET(BULK N'C:\TEMP\log.txt', SINGLE_BLOB) AS test)
); 

--Select from table
SELECT *
FROM Test.EmployeeJobs


--Go to the directory ''c:\EmployeeRecords\filestream1' specified in step one and you can find the file




/***************************************************************************************************************************************************************/
/*This examle is creating a database and adding a FILETABLE*/
/**************************************************************************************************************************************************************/

--The advantage is it has Windows API compatibility for file data stored within an SQL Server database

--Create Database with filestream directory for files, these can be stored outside the SQL install folder
CREATE DATABASE TestFileTableDB
ON PRIMARY
(Name = TestFileTabledb,
FILENAME = 'C:\TestFileTableDB\FTDB.mdf'),
FILEGROUP FTFG CONTAINS FILESTREAM
(NAME = TestFS,
FILENAME='C:\TestFileTableDB\FS')
LOG ON
(Name = TestFileTabledbLog,
FILENAME = 'C:\TestFileTableDB\FTDBLog.ldf')
WITH FILESTREAM (NON_TRANSACTED_ACCESS = FULL,
DIRECTORY_NAME = N'FileTableDB');
GO

--Use the database
USE TestFileTableDB;
GO

--Run to confirm if filesteam is enabled on any database on the server
--the first column will tell you the file level access and the second will tell you the access
SELECT DB_NAME(database_id),
non_transacted_access,
non_transacted_access_desc
FROM sys.database_filestream_options;
GO


/*Create FILETABLE using database created above*/
CREATE TABLE TestFileTable
AS FILETABLE
WITH (FILETABLE_DIRECTORY = 'TestFileTable_Dir');
GO


--Insert a simple text file into the table, with a name for the entry
INSERT INTO dbo.TestFileTable
	([name],file_stream)
SELECT 'MyTestFile.txt', * FROM OPENROWSET(BULK N'c:\Users\BugsBunny\Documents\MyTestFile.txt', SINGLE_BLOB) AS FileData