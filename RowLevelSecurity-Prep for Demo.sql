/*Tables needed for the RowLevelSecurity Demo.sql 
These tables were created before the demo to reduce time
Some of the tables and data were created using tables in the Microsoft SQL2016 WideWorldImporters database
 https://www.mssqltips.com/sqlservertip/4394/download-and-install-sql-server-2016-sample-databases-wideworldimporters-and-wideworldimportersdw/ */

CREATE DATABASE RowLevelSecurity;
GO

USE RowLevelSecurity;
GO

/*Create Orders table*/
CREATE TABLE Sales.Orders
(OrderID int NOT NULL,
	CustomerID int NOT NULL,
	SalespersonPersonID int NOT NULL,
	PickedByPersonID int NULL,
	ContactPersonID int NOT NULL,
	BackorderOrderID int NULL,
	OrderDate date NOT NULL,
	ExpectedDeliveryDate date NOT NULL,
	CustomerPurchaseOrderNumber nvarchar(20) NULL,
	IsUndersupplyBackordered bit NOT NULL,
	Comments nvarchar(max) NULL,
	DeliveryInstructions nvarchar(max) NULL,
	InternalComments nvarchar(max) NULL,
	PickingCompletedWhen datetime2(7) NULL,
	LastEditedBy int NOT NULL,
	LastEditedWhen datetime2(7) NOT NULL,
 CONSTRAINT PK_Sales_Orders PRIMARY KEY CLUSTERED (OrderID));
 GO

/*Create Invoices table with FK to Orders table*/

CREATE TABLE Sales.Invoices(
	InvoiceID int NOT NULL,
	CustomerID int NOT NULL,
	BillToCustomerID int NOT NULL,
	OrderID int NULL,
	DeliveryMethodID int NOT NULL,
	ContactPersonID int NOT NULL,
	AccountsPersonID int NOT NULL,
	SalespersonPersonID int NOT NULL,
	PackedByPersonID int NOT NULL,
	InvoiceDate date NOT NULL,
	CustomerPurchaseOrderNumber nvarchar(20) NULL,
	IsCreditNote bit NOT NULL,
	CreditNoteReason nvarchar(max) NULL,
	Comments nvarchar(max) NULL,
	DeliveryInstructions nvarchar(max) NULL,
	InternalComments nvarchar(max) NULL,
	TotalDryItems int NOT NULL,
	TotalChillerItems int NOT NULL,
	DeliveryRun nvarchar(5) NULL,
	RunPosition nvarchar(5) NULL,
	ReturnedDeliveryData nvarchar(max) NULL,
	ConfirmedDeliveryTime  DATETIME2 Null,
	ConfirmedReceivedBy  NVARCHAR(50)	Null,
	LastEditedBy int NOT NULL,
	LastEditedWhen datetime2(7) NOT NULL,
 CONSTRAINT PK_Sales_Invoices PRIMARY KEY CLUSTERED (InvoiceID));
 GO

ALTER TABLE Sales.Invoices  WITH CHECK ADD  CONSTRAINT FK_Sales_Invoices_OrderID_Sales_Orders FOREIGN KEY(OrderID)
REFERENCES Sales.Orders (OrderID)
GO

/*Insert data into Orders table*/
INSERT INTO Sales.Orders
(OrderID,CustomerID,SalespersonPersonID,PickedByPersonID,ContactPersonID,BackorderOrderID,
    OrderDate,ExpectedDeliveryDate,CustomerPurchaseOrderNumber,IsUndersupplyBackordered,
    Comments,DeliveryInstructions,InternalComments,PickingCompletedWhen,LastEditedBy,LastEditedWhen)
SELECT OrderID,CustomerID,SalespersonPersonID,PickedByPersonID,ContactPersonID,BackorderOrderID,
       OrderDate,ExpectedDeliveryDate,CustomerPurchaseOrderNumber,IsUndersupplyBackordered,
       Comments,DeliveryInstructions,InternalComments,PickingCompletedWhen,LastEditedBy,LastEditedWhen
FROM WideWorldImporters.sales.Orders;
GO

/*Insert data into Invoices table*/
INSERT INTO Sales.Invoices
(InvoiceID,CustomerID,BillToCustomerID,OrderID,DeliveryMethodID,ContactPersonID,AccountsPersonID,
    SalespersonPersonID,PackedByPersonID,InvoiceDate,CustomerPurchaseOrderNumber,IsCreditNote,
    CreditNoteReason,Comments,DeliveryInstructions,InternalComments,TotalDryItems,TotalChillerItems,
    DeliveryRun,RunPosition,ReturnedDeliveryData,ConfirmedDeliveryTime,ConfirmedReceivedBy,    LastEditedBy,
    LastEditedWhen)
SELECT InvoiceID,CustomerID,BillToCustomerID,OrderID,DeliveryMethodID,ContactPersonID,AccountsPersonID,
       SalespersonPersonID,PackedByPersonID,InvoiceDate,CustomerPurchaseOrderNumber,IsCreditNote,CreditNoteReason,
       Comments,DeliveryInstructions,InternalComments,TotalDryItems,TotalChillerItems,DeliveryRun,RunPosition,
       ReturnedDeliveryData,ConfirmedDeliveryTime,ConfirmedReceivedBy,LastEditedBy,LastEditedWhen
FROM WideWorldImporters.Sales.Invoices

/***************************************************************************************************/
/*Create tables for performance testing
Copied from https://www.mssqltips.com/sqlservertip/4194/test-performance-overhead-of-sql-server-row-level-security/ */
*/

/*SampleUser table*/
CREATE TABLE Sales.SampleUser(
    UserID int NOT NULL PRIMARY KEY,
    Username varchar(30)
)
GO

-- Create SampleData table and foreign key to SampleUser table
CREATE TABLE Sales.SampleData
( RowKey int NOT NULL PRIMARY KEY, 
CreateDate datetime NOT NULL,
OtherDate datetime NOT NULL,
VarcharColumn varchar(20) NULL,
IntColumn int NULL,
FloatColumn float NULL,
UserID int NOT NULL
)
GO
ALTER TABLE Sales.SampleData  WITH CHECK 
   ADD CONSTRAINT FK_SampleData_SampleUser FOREIGN KEY(UserID)
   REFERENCES Sales.SampleUser (UserID)
GO

-- Load SampleUser table
DECLARE @val INT
SELECT @val=1
WHILE @val < 51
BEGIN  
   INSERT INTO Sales.SampleUser VALUES (@val,'User' + cast(@val AS VARCHAR))
   SELECT @val=@val+1
END
GO

-- Load SampleData table
DECLARE @val INT
SELECT @val=1
WHILE @val < 5000000
BEGIN  
   INSERT INTO Sales.SampleData VALUES
      (@val,
	   getdate(),
       DATEADD(DAY, ABS(CHECKSUM(NEWID()) % 365),'2015-01-01'),
       'TEST' + cast(round(rand()*100,0) AS VARCHAR),
       round(rand()*100000,0), 
	   round(rand()*10000,2),
	   round(rand()*49,0)+1)
   SELECT @val=@val+1
END
GO


CREATE NONCLUSTERED INDEX IX_SampleData_CreateDate ON Sales.SampleData (CreateDate ASC) 
GO
CREATE NONCLUSTERED INDEX IX_SampleData_UserID ON Sales.SampleData (UserID ASC) 
GO
CREATE NONCLUSTERED INDEX IX_SampleUser_Username ON Sales.SampleUser (Username ASC) 
GO


-- sysadmin user
CREATE LOGIN [test_sa] WITH PASSWORD=N'#######', DEFAULT_DATABASE=[master], 
   CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF
GO
ALTER SERVER ROLE [sysadmin] ADD MEMBER [test_sa]
GO

-- regular user
CREATE LOGIN [User10] WITH PASSWORD=N'#######', DEFAULT_DATABASE=[master], 
   CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF
GO
USE [TestDB]
GO
CREATE USER [User10] FOR LOGIN [User10]
GO
USE [TestDB]
GO
ALTER ROLE [db_datareader] ADD MEMBER [User10]
GO