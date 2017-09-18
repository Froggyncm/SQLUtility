/*BACKUP and RESTORE Scripts
This is a work in progress and is not complete*/









/*************************************************************************************************************************************/
/*Restoring database with FILESTREAM data as well*/
/*************************************************************************************************************************************/

/*Script to restore a database, with filesteam, from a .bak file off a disk
note - that you must create the directory where the filestream database file, log file and filestream documents if 
they don't exists i.e. restoring the backup to on a new server*/

RESTORE DATABASE RestoreFileTableDB
FROM DISK = N'C:\TestFileTableDB\TestFileTableDB.bak' WITH REPLACE, RECOVERY,  --locaiton of backup file 
MOVE 'TestFileTabledb' TO N'C:\RestoreFileTableDB\RestoreFileTableDB.mdf',  
MOVE 'TestFileTabledbLog' TO N'C:\RestoreFileTableDB\RestoreFileTableDB.ldf',
MOVE 'TestFS' TO N'C:\RestoreFileTableDB\FS\', STATS = 10;  --STATS = 10 is just the percentage that progress messages are reported




/*************************************************************************************************************************************/
/*Restoring database with FILESTREAM and TDE enabled*/
/*************************************************************************************************************************************/

/*Script to restore a database, with filesteam and TDE, from a .bak file off a disk
note - that you must create the directory where the filestream database file, log file and filestream documents if 
they don't exists i.e. restoring the backup to on a new server*/ 
RESTORE DATABASE RestoreFileTableDB
FROM DISK = N'C:\TestFileTableDB\TestFileTableDB.bak' WITH REPLACE, RECOVERY,
MOVE 'TestFileTabledb' TO N'C:\RestoreFileTableDB\RestoreFileTableDB.mdf',
MOVE 'TestFileTabledbLog' TO N'C:\RestoreFileTableDB\RestoreFileTableDB.ldf',
MOVE 'TestFS' TO N'C:\RestoreFileTableDB\FS\', STATS = 10;

/*running the step above will result in an error if you try to restore the database to a different server
that does not have the Database Decryption Certification*/

--Change to Master database
USE Master;
GO

--Create a Master Key for the SQL instance if it does not have one already
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'LukeSkywalker1'
GO

--If the Master Key already exists for the server, you will need to open it to create the certificate
OPEN MASTER KEY DECRYPTION BY PASSWORD = 'LukeSkywalker1'


/*This assumes you have access to the original certificate or the backup of the certificate and that you have the password for the private key
This creates the certificate on the new server on the Database using the certificate file from the original server
and with the private key from that certificate*/
CREATE CERTIFICATE EmpRecTDECert FROM FILE = 'C:\BobaFett\EmpRecTDE.cer'
WITH PRIVATE KEY (FILE =  'C:\BobaFett\EmpRecCertTDE.key',DECRYPTION BY PASSWORD = 'HanSolo1');
GO

/*Now you can restore the database with the security certificate in place*/
RESTORE DATABASE RestoreFileTableDB
FROM DISK = N'C:\TestFileTableDB\TestFileTableDB.bak' WITH REPLACE, RECOVERY,
MOVE 'TestFileTabledb' TO N'C:\RestoreFileTableDB\RestoreFileTableDB.mdf',
MOVE 'TestFileTabledbLog' TO N'C:\RestoreFileTableDB\RestoreFileTableDB.ldf',
MOVE 'TestFS' TO N'C:\RestoreFileTableDB\FS\', STATS = 10;