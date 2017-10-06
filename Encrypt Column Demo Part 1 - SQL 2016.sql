/*This example will show the steps to encrpyt a column of data 
in an already existing table that contains data.  The example will also show
how to decrypt and restrict who can see the decrypted data in 
the column There are also detailed notes on most steps that explain further*/

/*SQL Server Security is built on layers, this what we will be using

               Service Master Key
			           |
			   Database Master Key
			           |
			      Certificate
				       |
			     Symmetric Key
*/


USE master;
GO

/*On a new install of SQL Server the only existing symmetric key is the Service Master Key (SMK)
this is created automatically the first time SQL server starts up.  This key should be backed up when SQL server
is first started
*/
SELECT *
FROM sys.symmetric_keys;
GO

/*******************************************************************************************************************************************/
--SETUP FOR DEMO

--Switch to our database, no FILESTREAM
USE EncryptedColumn;
GO

--Create Schema
CREATE SCHEMA HumanResources AUTHORIZATION dbo;
GO

--Create test table
CREATE TABLE HumanResources.Employee(
	EmployeeID INT NOT NULL,
	FirstName VARCHAR(50) NOT NULL,
	LastName VARCHAR(50) NOT NULL,
	BirthDate DATETIME2(7) NOT NULL,
);
GO

--Insert Data into HumanResources.Employee
INSERT INTO HumanResources.Employee
(EmployeeID,FirstName,LastName,BirthDate)

VALUES
( 1, 'Jane', 'Doe', N'1989-06-02T00:00:00'), 
( 2, 'Spike', 'Spigel', N'1982-09-25T00:00:00'), 
( 3, 'Faye', 'Valentine', N'1962-07-13T00:00:00'), 
( 4, 'Bruce', 'Wayne', N'1939-05-27T00:00:00'), 
( 5, 'Master', 'Chief', N'1965-03-23T00:00:00');
GO

--Table with birthdate column 
SELECT *	
FROM HumanResources.employee;


/*We get a memo from Dwight Schrute that we must encrpyt the birthdate data of 
our employees.  We do not want anyone to get access to the Database File and be able to 
view birthdates.  We also only want to restrict access to view the birthdate and while not 
removing access to the employee table from all users who current have select rights to the table.


The solution is to encrypt the column that will contains the birthdate data with a symmetric key
so the birtdate data is encrypted at rest and in flight - with the exeception of granting 
access to the symmetric key to select users so they can view birthdate data */


/*Create Database Master Key (DMK) on the database and encrypt using a password. 
The DMK is used to protect the private keys of Certificates and asymmetric keys 
that are present in the database. 
 */
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Password123';  --Use Master Key created on Database
GO

/*ALWAYS backup the DMK and store in a separate location
This is a critical task.*/
BACKUP MASTER KEY TO FILE = 'C:\SQLBackup\Certificates and Keys\LukeSkywalker_EncryptedColumn_DMK.key'
ENCRYPTION BY PASSWORD = 'Password456';


/*Create the Certificate which will automatically be encrypted by the DMK in this database
unless you specify to encrypt by password.  If encrypt by password then you must explicitly Open and Close the
Certificate with the password*/

CREATE CERTIFICATE PII					--Create certificate used to secure encryption key                                                 
WITH SUBJECT = 'Protect Birtdate Data';

--ALWAYS backup Certificate with a private key and store in a separate location
BACKUP CERTIFICATE PII 
TO FILE = 'C:\SQLBackup\Certificates and Keys\LukeSkywalker_EncryptedColumn_Birthdate_Cert.cer'
WITH PRIVATE KEY(
  FILE = 'C:\SQLBackup\Certificates and Keys\LukeSkywalker_EncryptedColumn_Birthdate_Cert.key',
  ENCRYPTION BY PASSWORD = 'Password123'
);

/*This is what we will explicitly use to encrypt the birthdate column in the Employee table*/
CREATE SYMMETRIC KEY BirthdatePII								--Create encryption key
WITH ALGORITHM = AES_128
ENCRYPTION BY CERTIFICATE PII;									--Encrypt by certificate

/*The key is part of the database and therefore will be backed up when the database is backed up,
If you Drop the key,*/

SELECT *
FROM sys.symmetric_keys;

SELECT *
FROM sys.certificates;

/*Encrypting Column
datatype of varbinary
Since our column already exists as a Datetime2 we must create a new column*/
ALTER TABLE HumanResources.Employee
ADD BirthdatePII_Encrypt VARBINARY(MAX) NULL;			--Datatype Varbinary(MAX) required
GO

--Encrypt the data by opening the certificate, encrypting the data, and then closing the certificate
OPEN SYMMETRIC KEY BirthdatePII
DECRYPTION BY CERTIFICATE PII;
GO

UPDATE HumanResources.Employee
SET BirthdatePII_Encrypt = ENCRYPTBYKEY(KEY_GUID('BirthdatePII'),CONVERT(VARBINARY(100),BirthDate))  --datatime2 must be converted to varbinary 
FROM HumanResources.Employee;
GO

CLOSE SYMMETRIC KEY BirthdatePII;
GO

--Run a straight select statement and you will see the new column populated with encrypted data
SELECT *
FROM HumanResources.Employee;

--How to insert data into the now encrypted column
OPEN SYMMETRIC KEY BirthdatePII	
DECRYPTION BY CERTIFICATE PII;

INSERT INTO HumanResources.Employee
(EmployeeID,FirstName,LastName,BirthDate,BirthDatePII_encrypt)
VALUES
(6, 'Han','Solo', '1948-04-12', ENCRYPTBYKEY(KEY_GUID('BirthdatePII'), CONVERT(VARBINARY(100),CONVERT(DATETIME2,'1948-04-12') )));
GO

CLOSE SYMMETRIC KEY BirthdatePII;
GO

--Create a test user that has access to select on the Test Database
CREATE USER TestBirthDate WITHOUT LOGIN;
GO
GRANT SELECT ON HumanResources.Employee TO TestBirthDate;	
GO


--Run select as newly created user
EXECUTE AS USER = 'testbirthdate';     --User has select rights on table only
GO
SELECT *
FROM HumanResources.Employee;
GO
REVERT;
GO

/*Now run with syntax to decrypt the birthdate column and with the key closed the user will
GET NULL*/
EXECUTE AS USER = 'TestBirthDate';       --user only has select rights on table
GO
SELECT EmployeeID,
       FirstName,
       LastName,
       BirthDate,
	   Convert( datetime2, DecryptByKey(BirthDatePII_encrypt)) as 'datetime plaintext'  --using the decryption syntax
FROM HumanResources.Employee;
GO
REVERT


/*Now run and open the symmetric key (closing it behind the statement)
The user will get an error because they don't have rights to open and close the key*/
EXECUTE AS USER = 'testBirthDate';
GO
OPEN SYMMETRIC KEY BirthDatePII						--with encrypted columns must open the key
DECRYPTION BY CERTIFICATE PII;
GO
SELECT EmployeeID,
       FirstName,
       LastName,
       BirthDate,
	   Convert( datetime2, DecryptByKey(BirthdatePII_Encrypt)) as 'datetime plaintext'    --use decryption syntax
FROM HumanResources.Employee;
GO
CLOSE SYMMETRIC KEY BirthDatePII;					--explicitly close the key 
GO
REVERT;


/*To be able to open the Symmetric key the user needs CONTROL access, if done by the user directly.
Sysadmin has this access
*/
GRANT CONTROL ON CERTIFICATE :: PII TO testBirthDate;    --User must have control access to be able to use the certificate
GO

GRANT VIEW DEFINITION ON SYMMETRIC KEY :: BirthDatePII TO TestBirthDate;          --user must have vew definition on encryption
GO

--Now run as the test user again
EXECUTE AS USER = 'testBirthDate';										--User with Select on table, control on certificate and view definition on key                                      
GO
OPEN SYMMETRIC KEY BirthDatePII
DECRYPTION BY CERTIFICATE PII;
GO
SELECT EmployeeID,
       FirstName,
       LastName,
       BirthDate,
	   Convert( datetime2, DecryptByKey(BirthDatePII_Encrypt)) as 'datetime plaintext'
FROM HumanResources.Employee;
GO
CLOSE SYMMETRIC KEY BirthdatePII;
GO
REVERT;

--Backup Whole Database
BACKUP DATABASE Test TO DISK = 'C:\SQLBackup\Database\LukeSkywalker_EncryptedColumn.bak' WITH STATS = 10;
GO

/*Open Part 2 script*/