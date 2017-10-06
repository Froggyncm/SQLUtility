/*************************************************************************************************************************************
Database with Encrypted Column Restored to new SQL instance (on same machine)*/

USE master;
GO


--Restore database 
RESTORE DATABASE EncryptedColumn
FROM DISK = N'C:\SQLBackup\Database\LukeSkywalker_EncryptedColumn.bak' WITH REPLACE,  --using replace as this is a test and will override certain checks
MOVE 'EncryptedColumn' TO N'C:\Program Files\Microsoft SQL Server\MSSQL13.BOBBAFETT\MSSQL\DATA\EncryptedColumn.mdf',
MOVE 'EncryptedColumn_Log' TO N'C:\Program Files\Microsoft SQL Server\MSSQL13.BOBBAFETT\MSSQL\DATA\EncryptedColumn_log.ldf',
STATS = 10;

USE EncryptedColumn;
GO

--Select from table, data appears encrypted
SELECT *
FROM HumanResources.Employee;
GO

--Select symmetric keys
SELECT *
FROM sys.symmetric_keys


--Select by opening key, we get an error 
OPEN SYMMETRIC KEY BirthdatePII
DECRYPTION BY CERTIFICATE PII;
GO
SELECT EmployeeID,
       FirstName,
       LastName,
       BirthDate,
	   Convert( datetime2, DecryptByKey(BirthdatePII_Encrypt)) as 'datetime plaintext'
FROM HumanResources.Employee;
GO
CLOSE SYMMETRIC KEY BirthdatePII;
GO


/*We need to associate the DMK with this server's SMK because we restored the database on another
SQL server instance.  If we just try to add the SMK we will get an error because we encrypted the
DMK with a password */
ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY


/*Try to a new password to the Master Key, this is unsuccessful because this was restored to 
a new SQL instance (on same machine) and it is not associated with this SQL instance SMK.
 */
ALTER MASTER KEY ADD ENCRYPTION BY PASSWORD = 'Iforgot123'


--We need to open and with decrypting the DMK with it's password 
OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Password123';
GO

--ALTER it to add encryption by the Service Master Key
ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY;
GO

--Close DMK
CLOSE MASTER KEY


--Now let's try our query again
OPEN SYMMETRIC KEY BirthDatePII
DECRYPTION BY CERTIFICATE PII;
GO
SELECT EmployeeID,
       FirstName,
       LastName,
       BirthDate,
	   Convert( datetime2, DecryptByKey(BirthDatePII_encrypt)) as 'datetime plaintext'
FROM HumanResources.Employee;
GO
CLOSE SYMMETRIC KEY BirthDatePII;
GO

--Insert data
OPEN SYMMETRIC KEY BirthDatePII
DECRYPTION BY CERTIFICATE PII;

INSERT INTO HumanResources.Employee
(EmployeeID,FirstName,LastName,BirthDate,BirthDatePII_encrypt)
VALUES
(6, 'Leia','Organa', '1971-03-01', ENCRYPTBYKEY(KEY_GUID('BirthDatePII'), CONVERT(VARBINARY(100),CONVERT(DATETIME2,'1971-03-01') )));
GO

CLOSE SYMMETRIC KEY BirthdatePII;
GO

--Verify data inserted into table
--Now let's try our query again
OPEN SYMMETRIC KEY BirthDatePII
DECRYPTION BY CERTIFICATE PII;
GO
SELECT EmployeeID,
       FirstName,
       LastName,
       BirthDate,
	   Convert( datetime2, DecryptByKey(BirthDatePI_encrypt)) as 'datetime plaintext'
FROM HumanResources.Employee;
GO
CLOSE SYMMETRIC KEY BirthdatePII;
GO

/*The DMK can be protected by Multiple passwords, because we encrypted the DMK with the SMK
it will allow us to add passwords without using the existing password to open.  And these can just as easily be dropped.
If we did not have this associated with the SMK we would need to open the DMK with any password it was set with
and alter and add a password, closing the DMK.
Once closed, any of the passwords we add can be used to open the DMK.  
*/
ALTER MASTER KEY ADD ENCRYPTION BY PASSWORD = 'Iforgot123';
GO


--Remove the association to the SMK from the DMK
ALTER MASTER KEY DROP ENCRYPTION BY SERVICE MASTER KEY;
GO

--Now let's try our query again
OPEN SYMMETRIC KEY BirthDatePII
DECRYPTION BY CERTIFICATE PII;
GO
SELECT EmployeeID,
       FirstName,
       LastName,
       BirthDate,
	   Convert( datetime2, DecryptByKey(BirthDatePII_encrypt)) as 'datetime plaintext'
FROM HumanResources.Employee;
GO
CLOSE SYMMETRIC KEY BirthDatePII;
GO


--Explicitly open DMK
OPEN MASTER KEY DECRYPTION BY PASSWORD = 'Iforgot123';
GO
OPEN SYMMETRIC KEY BirthDatePII
DECRYPTION BY CERTIFICATE PII;
GO
SELECT EmployeeID,
       FirstName,
       LastName,
       BirthDate,
	   Convert( datetime2, DecryptByKey(BirthDatePI_encrypt)) as 'datetime plaintext'
FROM HumanResources.Employee;
GO
CLOSE SYMMETRIC KEY BirthDatePI;
GO
CLOSE MASTER KEY;
GO
