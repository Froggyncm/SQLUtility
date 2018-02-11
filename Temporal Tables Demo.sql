/*System Versioned Temporal tables (SQL 2016) will version data and track history, it will create a main table and a History table.
Ideally records get inserted into the main table and when a change is detected it will move the record to the history
table and create a new row in the temporal table.  Each record will have a start and end date.  The record in the temporal table
will always have 9999-12-31 as the end date.*/

USE TemporalTest;
GO

CREATE SCHEMA HumanResources AUTHORIZATION dbo;
GO

/*******************************************************************************************************************************************/
/*CREATE TEMPORAL TABLE*/
/*******************************************************************************************************************************************/

/* Steps to Create temporal table(s)
1. Generated Always As Row - works with the Period for System Time and is required to be set for temporal tables
	1a. System Time columns must be data type DateTime2
2. Constraint on Datetime2 is for ease of the constraint name only, the system would default this to UTC and the 9999 anyway.
3. Hidden - hides the columns from displaying in query when using * and they won't be displayed unless explictly selected (NOT REQUIRED)
4. Period For System_Time - sets the date columns to be used
5. With System_Versioning - turns on versioning, Names history Table*
	* by default the history table has no constraints
	5a. History table must be in the same database 
6. Special considerations must be made for In Memory Optimized tables */
CREATE TABLE HumanResources.Department 
(DepartmentID		INT						IDENTITY(1,1)		NOT NULL,
 DepartmentName		VARCHAR(100)								NOT NULL,
 RowStartDate		DATETIME2	GENERATED ALWAYS AS ROW START	HIDDEN	CONSTRAINT DF_Department_Start	DEFAULT SYSUTCDATETIME()										NOT NULL,
 RowEndDate			DATETIME2	GENERATED ALWAYS AS ROW END		HIDDEN	CONSTRAINT DF_Department_End	DEFAULT CONVERT( DATETIME2, '9999-12-31 23:59:59.9999999')		NOT NULL,
 CONSTRAINT [PK_Department] PRIMARY KEY CLUSTERED (DepartmentID),
 PERIOD FOR SYSTEM_TIME (RowStartDate,RowEndDate))
 WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
 GO

 /*****************************************************/
 /*Query to identify temporal tables*/
 /*****************************************************/

 -- List temporal tables, temporal_type = 2  
  SELECT tables.object_id, temporal_type, temporal_type_desc, history_table_id,
    tables.name
    FROM sys.tables
    WHERE temporal_type = 2; -- SYSTEM_VERSIONED_TEMPORAL_TABLE
GO

  -- List temporal tables and history tables
  SELECT h.name temporal_name, h.temporal_type_desc, h.temporal_type,
    t.name AS history_table_name, t.temporal_type, t.temporal_type_desc
    FROM sys.tables t
      JOIN sys.tables h
        ON t.object_id = h.history_table_id;
GO
/*********************************************************************************/
/*Verify our columns are hidden, but that we can still select them in a query*/
/******************************************************************************/
 SELECT *	
 FROM HumanResources.Department;
 GO
 
 --Columns not hidden
 SELECT *
 FROM HumanResources.Department_History;
 GO

 --Can do an explict query selecting the columns
 SELECT DepartmentID,
        DepartmentName,
        ManagerID,
        RowStartDate,
        RowEndDate		
 FROM HumanResources.Department;
 GO


 /************************************************************************************************************/
 /*How Temporal tables work by the book or using the Wrath of Khan methodology*/
 /************************************************************************************************************/

 /*With SYSTEM VERSION ON Cannot insert a record with explictly set rowstartdate and/or rowenddate for the temporal
 table */
 INSERT INTO HumanResources.Department
 (DepartmentName,ManagerID,RowStartDate,RowEndDate)
 VALUES
 ('Sales', 1, '1/1/1900','12/31/9999' );
 GO
 
 
 INSERT INTO HumanResources.Department
 (DepartmentName,ManagerID) --Insert only on Non-Generate Always columns) 
 VALUES
 ('TestDepartment', 1);
 GO

 SELECT *
 FROM HumanResources.Department
 FOR SYSTEM_TIME ALL;
 GO

 --update existing record
UPDATE HumanResources.Department
SET DepartmentName = 'DepartmentTest'
WHERE DepartmentID = 1;
GO

--new record created
SELECT DepartmentID,DepartmentName,ManagerID,RowStartDate,RowEndDate		
FROM HumanResources.Department;
GO

--Insert new record into table 
INSERT INTO HumanResources.Department
(DepartmentName,ManagerID,RowStartDate)
VALUES
('Paint Shop',2,DEFAULT);
GO

--SELECT record
SELECT *
FROM HumanResources.Department
WHERE DepartmentName = 'Paint Shop';
GO

--Update record with exact same data
UPDATE HumanResources.Department
SET DepartmentName = 'Paint Shop'
WHERE DepartmentID = 6;
GO

--Temporal tables see this as an update even though the data did not change
SELECT *
FROM HumanResources.Department
FOR SYSTEM_TIME ALL
WHERE DepartmentID = 6;
GO


--existing record moved to history
SELECT *
FROM HumanResources.Department_History;
GO

SELECT DepartmentID,DepartmentName,ManagerID,RowStartDate,RowEndDate
FROM HumanResources.Department
FOR SYSTEM_TIME ALL
WHERE DepartmentID = 1;
GO 

--Delete record
DELETE HumanResources.Department
WHERE DepartmentID = 1;
GO

SELECT *
FROM HumanResources.Department
FOR SYSTEM_TIME ALL
WHERE DepartmentID = 1;
GO 

--Record removed from main table
SELECT *
FROM HumanResources.Department;
GO 

--Record moved to history
SELECT *
FROM HumanResources.Department_History;
GO 

 /*Cannot insert any row into the History table with System versioning turned on*/
 INSERT INTO HumanResources.Department_History
 (
     DepartmentID,DepartmentName,ManagerID,RowStartDate,RowEndDate
 )
 VALUES
 (   1,'Sales',2,'1/1/2005','9/6/2017' );
 GO


/*Columns added to the Temporal table will automatically be added to the history table*/
ALTER TABLE HumanResources.Department
ADD PayrollID	INT		NULL;
GO

SELECT *
FROM HumanResources.Department;
GO

SELECT *
FROM HumanResources.Department_History;
GO

/*Remove a column will remove the column and data from history too*/
ALTER TABLE HumanResources.Department
DROP COLUMN PayrollID;
GO

SELECT *
FROM HumanResources.Department;
GO

SELECT *
FROM HumanResources.Department_History;
GO

/******************************************************************************************************/
/*Cannot TRUNCATE a Temporal table*/
/******************************************************************************************************/

INSERT INTO HumanResources.Department
(DepartmentName,ManagerID)
VALUES
('Sales', 2), ('Human Resources',3);
GO

SELECT *
FROM HumanResources.Department
FOR SYSTEM_TIME ALL;
GO

TRUNCATE TABLE HumanResources.Department;
GO

 /***************************************************************************************************************/
 /*Cannot have any constraints on History table while system versioning is ON
 Try to add constraints to history table while System Versioning is ON and you will receive message you cannot
 If add to a table that is not system versioned but then try to make it the history table you will
 get error that is not allowed*/
 /***********************************************************************************************************/
ALTER TABLE HumanResources.Department_History
	ADD CONSTRAINT ck_RowStartDate check (RowStartDate <= RowEndDate);
GO

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = OFF);
GO

ALTER TABLE HumanResources.Department_History
	ADD CONSTRAINT ck_RowStartDate check (RowStartDate <= RowEndDate);
GO

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

ALTER TABLE HumanResources.Department_History
	DROP CONSTRAINT ck_RowStartDate;
GO

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

/**************************************************/
/*Cannot DROP a SYSTEM VERSIONED Table*/
/*************************************************/
DROP TABLE HumanResources.Department;
GO

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = OFF);

DROP TABLE HumanResources.Department;
GO

/*must explictily drop the history table too*/
DROP TABLE HumanResources.Department_History;
GO



/*Setup for next Demo*/
CREATE TABLE HumanResources.Department 
(DepartmentID		INT						IDENTITY(1,1)		NOT NULL,
 DepartmentName		VARCHAR(100)								NOT NULL,
 ManagerID			INT											NULL,
 RowStartDate		DATETIME2	GENERATED ALWAYS AS ROW START	HIDDEN	CONSTRAINT DF_Department_Start	DEFAULT SYSUTCDATETIME()										NOT NULL,
 RowEndDate			DATETIME2	GENERATED ALWAYS AS ROW END		HIDDEN	CONSTRAINT DF_Department_End	DEFAULT CONVERT( DATETIME2, '9999-12-31 23:59:59.9999999')		NOT NULL,
 CONSTRAINT [PK_Department] PRIMARY KEY CLUSTERED (DepartmentID),
 PERIOD FOR SYSTEM_TIME (RowStartDate,RowEndDate))
 WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
 GO

  INSERT INTO HumanResources.Department
 (DepartmentName,ManagerID) --Insert only on Non-Generate Always columns) 
 VALUES
 ('TestDepartment', 1),('Sales', 2), ('Human Resources',3);
 GO

UPDATE HumanResources.Department
SET DepartmentName = 'DepartmentTest'
WHERE DepartmentID = 1;
GO

/************************************************************************************************************************************************************/
/*Insert recrods into the temporal table, 
the scripts below will show the limitations when you have system versioning off and/or Drop Period FOR System_Time*/
/************************************************************************************************************************************************************/
 

 /*****************************************************************************************/
/*Turn off system versioning and drop period for system time so we can insert records into
the temporal table and specifiy a rowstartdate*/
/*****************************************************************************************/
ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = OFF);
GO

ALTER TABLE HumanResources.Department
DROP PERIOD FOR SYSTEM_TIME;
GO

INSERT INTO HumanResources.Department
(
    DepartmentName,ManagerID,RowStartDate,RowEndDate
)
VALUES
( 'Information Technology', 5, '2006-01-01', DEFAULT );  --DEFAULT is 9999-12-31
GO

ALTER TABLE HumanResources.Department
ADD PERIOD FOR SYSTEM_TIME (RowStartDate,RowEndDate);
GO

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

--Record in main table has start date of 2006-01-01
SELECT *
FROM HumanResources.Department
FOR SYSTEM_TIME ALL
ORDER BY DepartmentID, RowEndDate;
GO


 /************************************************************************************************/
 /*We can insert records into History if we turn system versioning off,
 however the table has no constraints and will let us insert the record below
 Even though we specified the constraint in our clause to turn on system versioning, that
 only applies when system versioning is turned on*/
 /**********************************************************************************************/
ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = OFF);
GO

 INSERT INTO HumanResources.Department_History
 (
     DepartmentID,DepartmentName,ManagerID,RowStartDate,RowEndDate
 )
 VALUES
 (   1,'Sales',2,'9/5/2017','1/5/2017' );
 GO

SELECT *
FROM HumanResources.Department_History;

/*System versioning will run a consistency_check on the records in the history table and 
not allow system versioning to be turned back on*/
ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

DELETE FROM HumanResources.Department_History
WHERE DepartmentID = 1 AND DepartmentName = 'Sales';
GO

/***********************************************************/
 /*Insert a record that does not violate the constraint
 and we are able to turn system versioning back on*/
 /********************************************************/
 
 SELECT DepartmentID, RowStartDate, RowEndDate
 FROM HumanResources.Department
 WHERE DepartmentName = 'Sales';
 GO
 
 INSERT INTO HumanResources.Department_History
 (
     DepartmentID,DepartmentName,ManagerID,RowStartDate,RowEndDate
 )
 VALUES
 (   2,'Sales',2,'1/1/2005','9/5/2017' );
 GO

SELECT *
FROM HumanResources.Department_History;
GO


ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

/**********************************************************************************************************/
/*System Versioning will allow gaps of time between rows, see Sales*/
/*****************************************************************************************************/
INSERT INTO HumanResources.Department
(DepartmentName,ManagerID)
VALUES
('Maintenance', 5);
GO

ALTER TABLE HumanResources.Department
SET(SYSTEM_VERSIONING = OFF)

SELECT *
FROM HumanResources.Department 
WHERE DepartmentName = 'Maintenance'

INSERT INTO HumanResources.Department_History
(DepartmentID,DepartmentName,ManagerID,RowStartDate,RowEndDate)
VALUES
(5, 'Maintenance', 20, '2005-01-01', '2012-12-31')

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));

SELECT DepartmentID,
       DepartmentName,
       ManagerID,
       RowStartDate,
       RowEndDate
FROM HumanResources.Department
FOR SYSTEM_TIME ALL  --system versioning to select all records from temporal table and history table
WHERE DepartmentID = 5
GO

/*****************************************************************************************************/
/*System versioning will not allow a record in history that overlaps row dates, in the history table 
and between the history table and the temporal table */
/*****************************************************************************************************/

/*overlaping dates in history table*/
ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = OFF);
GO

SELECT DepartmentID, DepartmentName, RowStartDate, RowEndDate
FROM HumanResources.Department;
GO

INSERT INTO HumanResources.Department_History
(DepartmentID,DepartmentName,ManagerID,RowStartDate,RowEndDate )
VALUES
( 4, 'IT', 5, '2001-01-01', '2006-01-01'),
(4, 'IT', 10, '2005-12-31', '2008-10-01');
GO

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

DELETE FROM HumanResources.Department_History
WHERE DepartmentID = 4 AND ManagerID = 10 and DepartmentName = 'IT';
GO

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

SELECT *
FROM HumanResources.Department
FOR SYSTEM_TIME ALL
ORDER BY DepartmentID, RowEndDate;
GO

/*Overlaping dates between history table and main table*/
ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = OFF);
GO

INSERT INTO HumanResources.Department_History
(DepartmentID,DepartmentName,ManagerID,RowStartDate,RowEndDate )
VALUES
( 1, 'Maintenance', 5, '2017-09-06 00:00:00.0000000', '2017-09-26 14:57:49.6057479'  );  --overlaps with temporal by 1 second
GO

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

DELETE FROM HumanResources.Department_History
WHERE Departmentid = 1 AND RowEndDate = '2017-09-26 14:57:49.6057479';
GO

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

/************************************************************************/
/*ADD A COLUMN TO HISTORY*/
/***********************************************************************/

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = OFF);
GO

ALTER TABLE HumanResources.Department_History
ADD PayrollID	INT		NULL;
GO

SELECT *
FROM HumanResources.Department;
GO

SELECT *
FROM HumanResources.Department_History;
GO

/*Cannot turn on as History must contain the same number of columns as the Temporal table */
ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

ALTER TABLE HumanResources.Department_History
DROP COLUMN PayrollID;
GO

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

/******************************************************************/
/*Add a Column to Temporal and a different Column Name to History*/
/*****************************************************************/
ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = OFF);
GO

ALTER TABLE HumanResources.Department_History
ADD PayrollID	INT		NULL;
GO

ALTER TABLE HumanResources.Department
ADD PayID	INT		NULL;
GO

/*Cannot turn on as History must have same column name as Temporal */
ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

ALTER TABLE HumanResources.Department_History
DROP Column PayrollID;
GO

ALTER TABLE HumanResources.Department
DROP Column PayID;
GO

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

/******************************************************/
/*Add same column name with different data types*/
/*****************************************************/
ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = OFF);
GO

ALTER TABLE HumanResources.Department
ADD PayrollID	INT		NULL;
GO

ALTER TABLE HumanResources.Department_History
ADD PayrollID	CHAR(5)		NULL;
GO

/*Cannot turn versioning on with different data types*/
ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

ALTER TABLE HumanResources.Department
DROP COLUMN PayrollID;
GO

ALTER TABLE HumanResources.Department_History
DROP COLUMN PayrollID;
GO

ALTER TABLE HumanResources.Department
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Department_History, DATA_CONSISTENCY_CHECK = ON));
GO

/*************************************************************************************************************************************************/
/*Implement System Versioning on existing table that contains data */
/**************************************************************************************************************************************************/
USE TemporalTest;
GO

CREATE SCHEMA Purchasing;
GO

CREATE TABLE Purchasing.Supplier(
	SupplierID					INT													NOT NULL,
	SupplierName				NVARCHAR(100)										NOT NULL,
	SupplierCategoryID			INT													NOT NULL,
	PrimaryContactPersonID		INT													NOT NULL,
	AlternateContactPersonID	INT													NOT NULL,
	DeliveryMethodID			INT													NULL,
	DeliveryCityID				INT													NOT NULL,
	PostalCityID				INT													NOT NULL,
	SupplierReference			NVARCHAR(20)										NULL,
	BankAccountName				NVARCHAR(50) MASKED WITH (FUNCTION = 'default()')	NULL,
	BankAccountBranch			NVARCHAR(50) MASKED WITH (FUNCTION = 'default()')	NULL,
	BankAccountCode				NVARCHAR(20) MASKED WITH (FUNCTION = 'default()')	NULL,
	BankAccountNumber			NVARCHAR(20) MASKED WITH (FUNCTION = 'default()')	NULL,
	BankInternationalCode		NVARCHAR(20) MASKED WITH (FUNCTION = 'default()')	NULL,
	PaymentDays					INT													NOT NULL,
	InternalComments			NVARCHAR(max)										NULL,
	PhoneNumber					NVARCHAR(20)										NOT NULL,
	FaxNumber					NVARCHAR(20)										NOT NULL,
	WebsiteURL					NVARCHAR(256)										NOT NULL,
	DeliveryAddressLine1		NVARCHAR(60)										NOT NULL,
	DeliveryAddressLine2		NVARCHAR(60)										NULL,
	DeliveryPostalCode			NVARCHAR(10)										NOT NULL,
	DeliveryLocation			GEOGRAPHY											NULL,
	PostalAddressLine1			NVARCHAR(60)										NOT NULL,
	PostalAddressLine2			NVARCHAR(60)										NULL,
	PostalPostalCode			NVARCHAR(10)										NOT NULL,
	LastEditedBy				INT													NOT NULL
	CONSTRAINT PK_Purchasing_Suppliers PRIMARY KEY CLUSTERED (SupplierID));
GO

--Insert data into our table
INSERT INTO Purchasing.Supplier
(	SupplierID,SupplierName,SupplierCategoryID,PrimaryContactPersonID,AlternateContactPersonID,DeliveryMethodID,DeliveryCityID,PostalCityID,
    SupplierReference,BankAccountName,BankAccountBranch,BankAccountCode,BankAccountNumber,BankInternationalCode,PaymentDays,InternalComments,
    PhoneNumber,FaxNumber,WebsiteURL,DeliveryAddressLine1,DeliveryAddressLine2,DeliveryPostalCode,DeliveryLocation,PostalAddressLine1,
    PostalAddressLine2,PostalPostalCode,LastEditedBy
)
SELECT SupplierID,SupplierName,SupplierCategoryID,PrimaryContactPersonID,AlternateContactPersonID,DeliveryMethodID,DeliveryCityID,PostalCityID,
       SupplierReference,BankAccountName,BankAccountBranch,BankAccountCode,BankAccountNumber,BankInternationalCode,PaymentDays,InternalComments,
       PhoneNumber,FaxNumber,WebsiteURL,DeliveryAddressLine1,DeliveryAddressLine2,DeliveryPostalCode,DeliveryLocation,PostalAddressLine1,
	   PostalAddressLine2,PostalPostalCode,LastEditedBy
FROM WideWorldImporters.Purchasing.Suppliers;
GO

SELECT *
FROM Purchasing.Supplier

/*System Versioning requires the temporal table to have a primary key, the date columns to be used for period for system time must exist or be added*/
/*The first step is to add the Period for System Time columns on the temporal table, 
these either need to be added or use ones already there
This will add the system versioning and default the existing records start date to the current sysutcdatetime
*/
ALTER TABLE Purchasing.Supplier
ADD RowStartDate	DATETIME2	GENERATED ALWAYS AS ROW START	HIDDEN	CONSTRAINT DF_Supplier_Start	DEFAULT SYSUTCDATETIME()	NOT NULL,
	RowEndDate		DATETIME2   GENERATED ALWAYS AS ROW END		HIDDEN  CONSTRAINT DF_Supplier_End		DEFAULT CONVERT( DATETIME2, '9999-12-31 23:59:59.9999999') NOT NULL,
PERIOD FOR SYSTEM_TIME(RowStartDate,RowEndDate);
GO

ALTER TABLE Purchasing.Supplier
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = Purchasing.Supplier_History, DATA_CONSISTENCY_CHECK = ON));
GO

SELECT SupplierID,SupplierName,RowStartDate,RowEndDate
FROM Purchasing.Supplier;
GO

/*************************************************************************************************************************/
/*Alter Existing table to become System Version table and specify the start dates*/
/**************************************************************************************************************************/
CREATE TABLE Purchasing.Vendor(
	VendorID					INT													NOT NULL,
	VendorName				NVARCHAR(100)										NOT NULL,
	SupplierCategoryID			INT													NOT NULL,
	PrimaryContactPersonID		INT													NOT NULL,
	AlternateContactPersonID	INT													NOT NULL,
	DeliveryMethodID			INT													NULL,
	DeliveryCityID				INT													NOT NULL,
	PostalCityID				INT													NOT NULL,
	SupplierReference			NVARCHAR(20)										NULL,
	BankAccountName				NVARCHAR(50) MASKED WITH (FUNCTION = 'default()')	NULL,
	BankAccountBranch			NVARCHAR(50) MASKED WITH (FUNCTION = 'default()')	NULL,
	BankAccountCode				NVARCHAR(20) MASKED WITH (FUNCTION = 'default()')	NULL,
	BankAccountNumber			NVARCHAR(20) MASKED WITH (FUNCTION = 'default()')	NULL,
	BankInternationalCode		NVARCHAR(20) MASKED WITH (FUNCTION = 'default()')	NULL,
	PaymentDays					INT													NOT NULL,
	InternalComments			NVARCHAR(max)										NULL,
	PhoneNumber					NVARCHAR(20)										NOT NULL,
	FaxNumber					NVARCHAR(20)										NOT NULL,
	WebsiteURL					NVARCHAR(256)										NOT NULL,
	DeliveryAddressLine1		NVARCHAR(60)										NOT NULL,
	DeliveryAddressLine2		NVARCHAR(60)										NULL,
	DeliveryPostalCode			NVARCHAR(10)										NOT NULL,
	DeliveryLocation			GEOGRAPHY											NULL,
	PostalAddressLine1			NVARCHAR(60)										NOT NULL,
	PostalAddressLine2			NVARCHAR(60)										NULL,
	PostalPostalCode			NVARCHAR(10)										NOT NULL,
	LastEditedBy				INT													NOT NULL
	CONSTRAINT PK_Purchasing_Supplier PRIMARY KEY CLUSTERED (VendorID));
GO

--Insert data into our table
INSERT INTO Purchasing.Vendor
(	VendorID,VendorName,SupplierCategoryID,PrimaryContactPersonID,AlternateContactPersonID,DeliveryMethodID,DeliveryCityID,PostalCityID,
    SupplierReference,BankAccountName,BankAccountBranch,BankAccountCode,BankAccountNumber,BankInternationalCode,PaymentDays,InternalComments,
    PhoneNumber,FaxNumber,WebsiteURL,DeliveryAddressLine1,DeliveryAddressLine2,DeliveryPostalCode,DeliveryLocation,PostalAddressLine1,
    PostalAddressLine2,PostalPostalCode,LastEditedBy
)
SELECT SupplierID,SupplierName,SupplierCategoryID,PrimaryContactPersonID,AlternateContactPersonID,DeliveryMethodID,DeliveryCityID,PostalCityID,
       SupplierReference,BankAccountName,BankAccountBranch,BankAccountCode,BankAccountNumber,BankInternationalCode,PaymentDays,InternalComments,
       PhoneNumber,FaxNumber,WebsiteURL,DeliveryAddressLine1,DeliveryAddressLine2,DeliveryPostalCode,DeliveryLocation,PostalAddressLine1,
	   PostalAddressLine2,PostalPostalCode,LastEditedBy
FROM WideWorldImporters.Purchasing.Suppliers;
GO


SELECT *
FROM Purchasing.Vendor

ALTER TABLE Purchasing.Vendor
ADD VersionStart	DATETIME2	GENERATED ALWAYS AS ROW START	HIDDEN	CONSTRAINT DF_Vendor_Start	DEFAULT SYSUTCDATETIME()	NOT NULL,
	VersionEnd		DATETIME2   GENERATED ALWAYS AS ROW END		HIDDEN  CONSTRAINT DF_Vendor_End		DEFAULT CONVERT( DATETIME2, '9999-12-31 23:59:59.9999999') NOT NULL,
PERIOD FOR SYSTEM_TIME(VersionStart,VersionEnd)
GO

ALTER TABLE Purchasing.Vendor
DROP PERIOD FOR SYSTEM_TIME;
GO

UPDATE Purchasing.Vendor
SET VersionStart = '2016-01-01'

ALTER TABLE Purchasing.Vendor
ADD PERIOD FOR SYSTEM_TIME (VersionStart,VersionEnd);

ALTER TABLE Purchasing.Vendor
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = Purchasing.Vendor_History, DATA_CONSISTENCY_CHECK = ON));
GO

/*****************************************************************************************************************************/
/*SYSTEM VERSION TABLES WITH FOREIGN KEYS*/
/*****************************************************************************************************************************/

/*Create table with a FK dependancey on HumanResources.Department*/
CREATE TABLE HumanResources.Employee
(EmployeeID		INT						IDENTITY(1,1)		NOT NULL,
 FirstName		VARCHAR(100)								NOT NULL,
 LastName		VARCHAR(100)								NOT NULL,
 DepartmentID	INT											NOT NULL,
 RowStartDate		DATETIME2	GENERATED ALWAYS AS ROW START	HIDDEN	CONSTRAINT DF_Employee_Start	DEFAULT SYSUTCDATETIME()										NOT NULL,
 RowEndDate			DATETIME2	GENERATED ALWAYS AS ROW END		HIDDEN	CONSTRAINT DF_Employee_End		DEFAULT CONVERT( DATETIME2, '9999-12-31 23:59:59.9999999')		NOT NULL,
 CONSTRAINT [PK_Employee] PRIMARY KEY CLUSTERED (EmployeeID),
 CONSTRAINT [FK_Employee] FOREIGN KEY (DepartmentID) REFERENCES HumanResources.Department(DepartmentID),
 PERIOD FOR SYSTEM_TIME (RowStartDate,RowEndDate))
 WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Employee_History, DATA_CONSISTENCY_CHECK = ON));
 GO

SELECT *
FROM HumanResources.Department
WHERE DepartmentID = 89;
GO
 
 /*Insert record into Child table where PK does not exsist in parent table,
 Normal PK restraints apply with system versioning ON or OFF*/
 INSERT INTO HumanResources.Employee
 (FirstName,LastName,DepartmentID)
 VALUES
 ( 'Roger','Rabbit', 89);
 GO

 /************************************************/
 /*Insert a FK record with start date prior to Parent table record start date*/
 /**********************************************/
SELECT *
FROM HumanResources.Department;
GO

ALTER TABLE HumanResources.Employee
SET (SYSTEM_VERSIONING = OFF);
GO

ALTER TABLE HumanResources.Employee
DROP PERIOD FOR SYSTEM_TIME;
GO

INSERT INTO HumanResources.Employee
(FirstName,LastName,DepartmentID,RowStartDate,RowEndDate)
VALUES
( 'Roger','Rabbit','1','2016-01-01', DEFAULT);
GO

ALTER TABLE HumanResources.Employee
ADD PERIOD FOR SYSTEM_TIME (RowStartDate,RowEndDate);
GO

ALTER TABLE HumanResources.Employee
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Employee_History, DATA_CONSISTENCY_CHECK = ON))

SELECT e.EmployeeID, e.FirstName, e.RowStartDate AS EmployeeRowStart, d.DepartmentName, d.RowStartDate AS DeptRowStart
FROM HumanResources.Employee e INNER JOIN HumanResources.Department d ON d.DepartmentID = e.DepartmentID
WHERE e.FirstName = 'Roger';
GO

/*********************************************************************************************************/
/*INSERT record into child history where no corresponding FK exists in parent table (temporal or history)*/
/********************************************************************************************************/

ALTER TABLE HumanResources.Employee
SET (SYSTEM_VERSIONING = OFF);
GO

SELECT *
FROM HumanResources.Department
FOR SYSTEM_TIME ALL
ORDER BY DepartmentID;
GO

INSERT INTO HumanResources.Employee_History
(EmployeeID,FirstName,LastName,DepartmentID,RowStartDate,RowEndDate)
VALUES
(99, 'Roger','Rabbit', 89, '2012-01-01', '2016-12-31');
GO

ALTER TABLE HumanResources.Employee
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = HumanResources.Employee_History, DATA_CONSISTENCY_CHECK = ON));
GO

/***********************************************************************************************************************/
/*FILETABLE*/
/***********************************************************************************************************************/

/*Make table with FILESTREAM data a Temporal table
This will fail*/
USE FileTableTest;
GO

ALTER TABLE Test.Employeejobs
ADD RowStartDate	DATETIME2	GENERATED ALWAYS AS ROW START	HIDDEN	CONSTRAINT DF_Employeejobs_Start	DEFAULT SYSUTCDATETIME()	NOT NULL,
	RowEndDate		DATETIME2   GENERATED ALWAYS AS ROW END		HIDDEN  CONSTRAINT DF_Employeejobs_End		DEFAULT CONVERT( DATETIME2, '9999-12-31 23:59:59.9999999') NOT NULL,
PERIOD FOR SYSTEM_TIME(RowStartDate,RowEndDate);
GO

ALTER TABLE Test.Employeejobs
SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = Test.Employeejobs_History, DATA_CONSISTENCY_CHECK = ON));
GO

USE FileTableTest;
GO

/*FILETABLE
will not allow*/
ALTER TABLE dbo.TestFileTable
ADD RowStartDate	DATETIME2	GENERATED ALWAYS AS ROW START	HIDDEN	CONSTRAINT DF_TestFileTable_Start	DEFAULT SYSUTCDATETIME()	NOT NULL,
	RowEndDate		DATETIME2   GENERATED ALWAYS AS ROW END		HIDDEN  CONSTRAINT DF_TestFileTable_End		DEFAULT CONVERT( DATETIME2, '9999-12-31 23:59:59.9999999') NOT NULL,
PERIOD FOR SYSTEM_TIME(RowStartDate,RowEndDate);
GO

/*QUERYING TEMPORAL TABLES*/
/*When querying system versioned tables, there is a clause FOR SYSTEM_TIME that goes after your table select
that will include data from the history table in your query.  If left off this will query the temporal table
as a regular table */

SELECT *
FROM HumanResources.Department;
GO


SELECT *
FROM HumanResources.Department_History;
GO

/*ALL will return rows from both the main and history table*/
SELECT *
FROM HumanResources.Department
FOR SYSTEM_TIME ALL
ORDER BY DepartmentID, RowEndDate;
GO

/*AS OF will only return rows where the startdate is less than or equal to the parameter value 
AND the end date is is greater than the parameter value  */
SELECT *
FROM HumanResources.Department
FOR SYSTEM_TIME AS OF '2007-06-01';
GO

/*FROM TO  will return rows that were active within the specificed date range, 
regardless of wether the RowStartDate is before the FROM date 
or the RowEndDate is after the TO date. But does not include rows whose RowStartDate is = the TO date
nor does it include rows whose END DATE = FROM date */
SELECT *
FROM HumanResources.Department
FOR SYSTEM_TIME FROM '2017-01-01' TO '2017-09-06 20:55:59.9411652';
GO

/*BETWEEN will return rows that are active within the specified range, however unlike the FROM TO syntax
BETWEEN will return rows that have a RowStartDate = the upper boundary defined by the endpoint */

SELECT *
FROM HumanResources.Department
FOR SYSTEM_TIME BETWEEN '2017-01-01' AND '2017-09-06 20:55:59.9411652';


/*CONTAINED IN will return rows that RowStartDate and RowEndDate that are within the specified dates
and will include rows whose RowStartDate = lower boundry date or RowEndDate = upper boundry date */
SELECT *
FROM HumanResources.Department
FOR SYSTEM_TIME CONTAINED IN ('2005-01-01','2017-09-06 20:55:59.9411652';)

/****************************************************************************************************************************/
/*Performance Testing - TEMPORAL TABLES ONLY*/
/****************************************************************************************************************************/

/*Two temporal tables, both with history
FK
Indexes
TTSampleUser has 50 rows
TTSampleData has 4999999 rows*/

USE TemporalTest;
GO

/*run temporal query on table with 4999999 rows with Show Execution Plan ON*/
SELECT *
FROM PerfTest.TTSampleData
FOR SYSTEM_TIME ALL;
GO

