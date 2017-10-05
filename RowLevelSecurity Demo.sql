/*Row Level Security is part of SQL Server 2016 and give the ability to limit access to rows
based on users characteritics
1.  Create security function(s)
2.  Create security predicates using security functions
It uses security predicates that can be used to filter out rows for select statments
and explicitly block write operations*/

CREATE DATABASE RowLevelSecurity;
GO

USE RowLevelSecurity;
GO

/*Check for existing security policies or predicates*/
SELECT *
FROM sys.security_policies

SELECT *
FROM sys.security_predicates


/*table to apply RLS to */
SELECT *
FROM Sales.Orders;
GO

/*Implement RLS on SalespersonID in the orders table
1.  Users who have access to only their salesperson
2.  Users who have access to 2 or more salesperson
3.  Users who have access to all
4.  Users who do not have access to an org
*/
SELECT SalespersonPersonID, COUNT(*) AS TotalOrders
FROM Sales.Orders
GROUP BY SalespersonPersonID
ORDER BY SalespersonPersonID

/*Create Users
Names are not the security, but for testing purposes*/
CREATE USER Salesperson2 WITHOUT LOGIN;
CREATE USER Salesperson3 WITHOUT LOGIN;
CREATE USER Salesperson6 WITHOUT LOGIN;
CREATE USER Salesperson67 WITHOUT LOGIN;
CREATE USER SalesPerson1x WITHOUT LOGIN;
CREATE USER Salespersonall WITHOUT LOGIN;
GO

/*Grant users select rights on table*/
GRANT SELECT ON Sales.Orders TO SalesPerson2;
GRANT SELECT ON Sales.Orders TO SalesPerson3;
GRANT SELECT ON Sales.Orders TO SalesPerson6;
GRANT SELECT ON Sales.Orders TO SalesPerson67;
GRANT SELECT ON Sales.Orders TO SalesPerson1x;
GRANT SELECT ON Sales.Orders TO SalesPersonall;
GO


SELECT *
FROM sys.sysusers
WHERE name LIKE 'Sales%'

/*Users currently have no access to table*/
EXECUTE AS USER = 'Salesperson2'
SELECT *
FROM Sales.Orders;
GO
REVERT;
GO

/*Create schema for security functions*/
CREATE SCHEMA Sec AUTHORIZATION dbo;
GO

/************************************************************************************************/
/*Create a simple security function or predicate to be applied to the security policy on a table
This one will only allow
	SalesPerson2 to view SalespersonpersonID = 2
	SalesPerson3 to view SalespersonpersonID = 3
	SalesPerson6 to view SalespersonpersonID = 6
	SalesPersonall to view all records in the table
	dbo access to all (it does not get access by default)
	*/  
/***********************************************************************************************/
CREATE FUNCTION Sec.SimpleOrderAccess 
(@SalesPersonPersonID AS INT)
RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS SimpleOrderAccess
	WHERE @SalesPersonPersonID = (CASE WHEN USER_NAME() = ('Salesperson2') THEN 2  -- these 3 cases will grant access to only those rows that have the specified OrgID
						 WHEN USER_NAME() = ('Salesperson3') THEN 3
						 WHEN USER_NAME() = ('Salesperson6') THEN 6
						 END)
						OR USER_NAME() = 'Salespersonall'  --These two rows grant access to all
						OR USER_NAME() = 'dbo';
GO

/**************************************************************************************/
/*Create the security policy for the table referencing the function in the step above*/
/*************************************************************************************/
CREATE SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD FILTER PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Orders
WITH (STATE = ON);

/*****************Test access**********************************************/

/*Sysadmin access*/
SELECT *
FROM Sales.Orders


/*User with limited access*/
EXECUTE AS USER = 'Salesperson2'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/*User with access to all records*/
EXECUTE AS USER = 'SalesPersonall'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/*User with SELECT but no access through security policy*/
EXECUTE AS USER = 'SalesPerson67'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/*User has select permissions but is not covered under
security policy*/
EXECUTE AS USER = 'SalesPerson67';
GO
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/*Grant user update rights, who has only rights to view data for salesperson2*/
GRANT INSERT, UPDATE, DELETE ON Sales.Orders TO SalesPerson2;
GO

SELECT *
FROM sys.sysusers 
WHERE name = 'SalesPerson2';
GO

/*User can Insert a new row that they then cannot view
Below user SalesPerson2 has Insert but through security policy 
can only select users with SalesPersonPersonID = 2 */
EXECUTE AS USER = 'SalesPerson2';
GO
INSERT INTO Sales.Orders
(OrderID,CustomerID,SalespersonPersonID,PickedByPersonID,ContactPersonID,BackorderOrderID,OrderDate,ExpectedDeliveryDate,
       CustomerPurchaseOrderNumber,IsUndersupplyBackordered,Comments,DeliveryInstructions,InternalComments,PickingCompletedWhen,
       LastEditedBy,LastEditedWhen)
VALUES
( 73597, 222, 3, NULL, 5, 5, N'2013-01-01T00:00:00', N'2013-01-02T00:00:00', N'10941', 1, NULL, NULL, NULL, N'2013-01-01T12:00:00', 7, N'2013-01-01T12:00:00' );
REVERT;
GO

/*User has rights to see the record*/
EXECUTE AS USER = 'SalesPerson3'
SELECT *
FROM Sales.Orders
WHERE OrderID = 73597;
GO
REVERT;
GO

/*Even though we gave the user UPDATE rights, the filter is will not allow updates on rows that 
are filters, this user cannot view this row so they cannot update it */
EXECUTE AS USER = 'SalesPerson2'
UPDATE Sales.Orders
SET ContactPersonID = 6
WHERE OrderID = 73597;
GO
REVERT;
GO


/*Even though we gave the user DELETE priveleges they cannot DELETE a record they cannot view */
EXECUTE AS USER = 'SalesPerson3'
DELETE Sales.Orders
WHERE OrderID = 73598;
GO
REVERT;
GO


/*User SalesPerson2 can however update a row they have access to
Insert a new row with salespersonpersonid = 2*/
EXECUTE AS USER = 'SalesPerson2';
GO
INSERT INTO Sales.Orders
(OrderID,CustomerID,SalespersonPersonID,PickedByPersonID,ContactPersonID,BackorderOrderID,OrderDate,ExpectedDeliveryDate,
       CustomerPurchaseOrderNumber,IsUndersupplyBackordered,Comments,DeliveryInstructions,InternalComments,PickingCompletedWhen,
       LastEditedBy,LastEditedWhen)
VALUES
( 73600, 222, 2, NULL, 5, 5, N'2013-01-01T00:00:00', N'2013-01-02T00:00:00', N'10941', 1, NULL, NULL, NULL, N'2013-01-01T12:00:00', 7, N'2013-01-01T12:00:00' );
REVERT;
GO

/*SalesPerson2 can update the row inserted in the above statment because they can view it
and change it to a value they cannot see*/
EXECUTE AS USER = 'SalesPerson2'
UPDATE Sales.Orders
SET SalespersonPersonID = 3
WHERE OrderID = 73600
REVERT;
GO

/*SalesPerson2 can delete a row they have access to*/
EXECUTE AS USER = 'SalesPerson2';
GO
INSERT INTO Sales.Orders
(OrderID,CustomerID,SalespersonPersonID,PickedByPersonID,ContactPersonID,BackorderOrderID,OrderDate,ExpectedDeliveryDate,
       CustomerPurchaseOrderNumber,IsUndersupplyBackordered,Comments,DeliveryInstructions,InternalComments,PickingCompletedWhen,
       LastEditedBy,LastEditedWhen)
VALUES
( 73601, 222, 2, NULL, 5, 5, N'2013-01-01T00:00:00', N'2013-01-02T00:00:00', N'10941', 1, NULL, NULL, NULL, N'2013-01-01T12:00:00', 7, N'2013-01-01T12:00:00' );
REVERT;
GO

/*SalesPerson2 can update the row inserted in the above statment because they can view it
and change it to a value they cannot see*/
EXECUTE AS USER = 'SalesPerson2'
DELETE Sales.Orders
WHERE OrderID = 73601
REVERT;
GO


/*BLOCK predicates apply to all write operations
They are set in the BEFORE and AFTER context
	AFTER INSERT and AFTER UPDATE will block a user from inserting a row that would be filtered or blocked by
	the predicate 
	BEFORE UPDATE  will prevent users from updating rows that currently violate the predicate
	BEFORE DELETE can block DELETE operations*/


/*ALTER the security policy to block inserts to rows you cannot view*/
ALTER SECURITY POLICY SimpleSalesPersonAccess
 ADD BLOCK PREDICATE Sec.SimpleOrderAccess(SalespersonPersonID)
 ON Sales.Orders AFTER INSERT

 /*user SalesPerson2 now cannot insert a record for SalesPersonPersonID = 3 */
EXECUTE AS USER = 'SalesPerson2';
GO
INSERT INTO Sales.Orders
(OrderID,CustomerID,SalespersonPersonID,PickedByPersonID,ContactPersonID,BackorderOrderID,OrderDate,ExpectedDeliveryDate,
       CustomerPurchaseOrderNumber,IsUndersupplyBackordered,Comments,DeliveryInstructions,InternalComments,PickingCompletedWhen,
       LastEditedBy,LastEditedWhen)
VALUES
( 73602, 222, 3, NULL, 5, 5, N'2013-01-01T00:00:00', N'2013-01-02T00:00:00', N'10941', 1, NULL, NULL, NULL, N'2013-01-01T12:00:00', 7, N'2013-01-01T12:00:00' );
REVERT;
GO

/*However User SalesPerson2 Can insert a record for SalesPersonPersonID = 2*/
EXECUTE AS USER = 'SalesPerson2';
GO
INSERT INTO Sales.Orders
(OrderID,CustomerID,SalespersonPersonID,PickedByPersonID,ContactPersonID,BackorderOrderID,OrderDate,ExpectedDeliveryDate,
       CustomerPurchaseOrderNumber,IsUndersupplyBackordered,Comments,DeliveryInstructions,InternalComments,PickingCompletedWhen,
       LastEditedBy,LastEditedWhen)
VALUES
( 73602, 222, 2, NULL, 5, 5, N'2013-01-01T00:00:00', N'2013-01-02T00:00:00', N'10941', 1, NULL, NULL, NULL, N'2013-01-01T12:00:00', 7, N'2013-01-01T12:00:00' );
REVERT;
GO

/****************************************************************/
/*ALTER Security predicate while security policy is in place
Cannot because it is being referenced by security policy*/
ALTER FUNCTION sec.SimpleOrderAccess 
(@SalesPersonPersonID AS INT)
RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS AccessRight
	WHERE @SalesPersonPersonID = (CASE WHEN USER_NAME() = ('Salesperson2') THEN 2  -- these 3 cases will grant access to only those rows that have the specified OrgID
						 WHEN USER_NAME() = ('Salesperson3') THEN 3
						 WHEN USER_NAME() = ('Salesperson6') THEN 6
						 END)
						OR USER_NAME() = 'Salespersonall';
					  --These two rows grant access to all;
GO


/*DROP security policy and test users access*/
DROP SECURITY POLICY Sec.SimpleSalesPersonAccess

/*Sysadmin access*/
SELECT *
FROM Sales.Orders


/*User with limited access*/
EXECUTE AS USER = 'Salesperson2'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/*User with access to all records*/
EXECUTE AS USER = 'SalesPersonall'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/*User with SELECT but no access through security policy*/
EXECUTE AS USER = 'SalesPerson67'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/*************************************************************/
/*ALTER security predicate to not include explicit access to dbo*/
ALTER FUNCTION sec.SimpleOrderAccess 
(@SalesPersonPersonID AS INT)
RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS AccessRight
	WHERE @SalesPersonPersonID = (CASE WHEN USER_NAME() = ('Salesperson2') THEN 2  -- these 3 cases will grant access to only those rows that have the specified OrgID
						 WHEN USER_NAME() = ('Salesperson3') THEN 3
						 WHEN USER_NAME() = ('Salesperson6') THEN 6
						 END)
						OR USER_NAME() = 'Salespersonall';
					  --These two rows grant access to all;
GO

/*Create security policy*/
CREATE SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD FILTER PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Orders
WITH (STATE = ON);


/*Sysadmin access does not have access with DBO not having 
explicit rights in the security predicate*/
SELECT *
FROM Sales.Orders


/*User with limited access*/
EXECUTE AS USER = 'Salesperson2'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/*User with access to all records*/
EXECUTE AS USER = 'SalesPersonall'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/*User with SELECT but no access through security policy*/
EXECUTE AS USER = 'SalesPerson67'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/***************************************************************************/
/*DISABLE security policy*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
WITH (STATE = OFF);

/*Sysadmin access */
SELECT *
FROM Sales.Orders


/*User with limited access*/
EXECUTE AS USER = 'Salesperson2'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/****************************/
/*ALTER FUNCTION with policy disabled but not dropped*/
ALTER FUNCTION sec.SimpleOrderAccess 
(@SalesPersonPersonID AS INT)
RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS AccessRight
	WHERE @SalesPersonPersonID = (CASE WHEN USER_NAME() = ('Salesperson2') THEN 2  -- these 3 cases will grant access to only those rows that have the specified OrgID
						 WHEN USER_NAME() = ('Salesperson3') THEN 3
						 WHEN USER_NAME() = ('Salesperson6') THEN 6
						 END)
						OR USER_NAME() = 'Salespersonall'
						OR USER_NAME() = 'dbo';
						;
					  --These two rows grant access to all;
GO

/************
You must ALTER the security policy and drop the filter predicate*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess DROP filter PREDICATE ON 
Sales.Orders

/*Now we can alter the function that is not referenced by the policy*/
ALTER FUNCTION sec.SimpleOrderAccess 
(@SalesPersonPersonID AS INT)
RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS AccessRight
	WHERE @SalesPersonPersonID = (CASE WHEN USER_NAME() = ('Salesperson2') THEN 2  -- these 3 cases will grant access to only those rows that have the specified OrgID
						 WHEN USER_NAME() = ('Salesperson3') THEN 3
						 WHEN USER_NAME() = ('Salesperson6') THEN 6
						 END)
						OR USER_NAME() = 'Salespersonall'
						OR USER_NAME() = 'dbo';
						;
					  --These two rows grant access to all;
GO


/*Add the security predicate back*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD FILTER PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Orders;
GO

/*Turn the policy back on*/
ALTER SECURITY POLICY sec.simplesalespersonaccess
WITH (STATE = ON);
GO

/*Drop the predicate from the policy while policy is ON*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
DROP FILTER PREDICATE ON Sales.Orders
GO

/*ALTER the predicate*/
ALTER FUNCTION sec.SimpleOrderAccess 
(@SalesPersonPersonID AS INT)
RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS AccessRight
	WHERE @SalesPersonPersonID = (CASE WHEN USER_NAME() = ('Salesperson2') THEN 2  -- these 3 cases will grant access to only those rows that have the specified OrgID
						 WHEN USER_NAME() = ('Salesperson3') THEN 3
						 WHEN USER_NAME() = ('Salesperson6') THEN 6
						 END)
						OR USER_NAME() = 'Salespersonall'
						OR USER_NAME() = 'dbo';
						;
					  --These two rows grant access to all;
GO
 /***********************
 Check user access and they can see all rows*/
 /*Sysadmin access */
SELECT *
FROM Sales.Orders


/*User with limited access*/
EXECUTE AS USER = 'Salesperson2'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/*User with access to all records*/
EXECUTE AS USER = 'SalesPersonall'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/*User with SELECT but no access through security policy*/
EXECUTE AS USER = 'SalesPerson67'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/****************************************************/
/*ADD SECURITY POLICY back*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD FILTER PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Orders;
GO

/*************************************************************************************/
/*Add in second table with foreign key*/
SELECT *
FROM sales.Invoices

GRANT SELECT ON Sales.Invoices TO Salesperson2;

EXECUTE AS USER = 'Salesperson2'
SELECT *
FROM Sales.Invoices
REVERT;
GO

/*Query joined to table with no security predicate join works as normal*/
EXECUTE AS USER = 'Salesperson2'
SELECT O.OrderID, o.SalespersonPersonID, I.SalespersonPersonID, I.InvoiceID
FROM Sales.Orders o INNER JOIN Sales.Invoices I ON I.OrderID = o.OrderID
WHERE I.SalespersonPersonID = 3 
REVERT;
GO


EXECUTE AS USER = 'Salesperson2'
SELECT O.OrderID, o.SalespersonPersonID, I.SalespersonPersonID, I.InvoiceID
FROM Sales.Invoices I LEFT JOIN  Sales.Orders O ON I.OrderID = o.OrderID
WHERE I.SalespersonPersonID = 3 
REVERT;
GO

/***********************************************************************************/
/*Alter security policy and apply existing predicate to 2nd table that has column to filer on*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD FILTER PREDICATE Sec.SimpleOrderAccess(salespersonpersonid) ON Sales.Invoices;
GO
 
/*User cannot see any records with predicate applied to both tables*/
EXECUTE AS USER = 'Salesperson2'
SELECT O.OrderID, o.SalespersonPersonID, I.SalespersonPersonID, I.InvoiceID
FROM Sales.Orders o INNER JOIN Sales.Invoices I ON I.OrderID = o.OrderID
WHERE I.SalespersonPersonID = 3 
REVERT;
GO

/*User cannot see any records with predicate applied to both tables*/
EXECUTE AS USER = 'Salesperson2'
SELECT O.OrderID, o.SalespersonPersonID, I.SalespersonPersonID, I.InvoiceID
FROM Sales.Invoices I LEFT JOIN  Sales.Orders O ON I.OrderID = o.OrderID
WHERE I.SalespersonPersonID = 3 
REVERT;
GO

/****************************************************************************************/
/*Add in multiple rows for same user who can have access to 2 
or more orgs, but not access to all rows in the table*/

/*Drop the predicate from the policy while policy is ON*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
DROP FILTER PREDICATE ON Sales.Orders
GO

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
DROP FILTER PREDICATE ON Sales.Invoices
GO

/*ALTER the predicate*/
ALTER FUNCTION sec.SimpleOrderAccess 
(@SalesPersonPersonID AS INT)
RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS AccessRight
	WHERE @SalesPersonPersonID = (CASE WHEN USER_NAME() = ('Salesperson2') THEN 2  -- these 3 cases will grant access to only those rows that have the specified OrgID
						 WHEN USER_NAME() = ('Salesperson3') THEN 3
						 WHEN USER_NAME() = ('Salesperson6') THEN 6
						 END)
						OR (USER_NAME() = 'Salesperson3' AND @SalesPersonPersonID IN(3,6))
						OR USER_NAME() = 'dbo';
GO

/*Add filter predicate back*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD FILTER PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Orders;
GO

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD FILTER PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Invoices;
GO

--GRANT SHOWPLAN TO Salesperson3 

/*Thhe user should have access to both rows 3 and 6*/
EXECUTE AS USER = 'SalesPerson3'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/*******************************************************************/
/*Row Level Security using a explicit user access lookup table*/
/******************************************************************/

CREATE TABLE Sales.UserOrgAccess
(UserOrgAccessID		INT,
UserID					INT,
UserName				NVARCHAR(50),
OrgID					INT);
GO

INSERT INTO Sales.UserOrgAccess
(UserOrgAccessID,UserID,UserName,OrgID)
VALUES
(1,1,'SalesPerson1',1 ), (2,2,'SalesPerson2',2),
(3,3,'SalesPerson3',3), (4,3,'SalesPerson3',6);
GO

/*Drop the predicate from the policy while policy is ON*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
DROP FILTER PREDICATE ON Sales.Orders
GO

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
DROP FILTER PREDICATE ON Sales.Invoices
GO

/*ALTER the predicate*/
ALTER FUNCTION sec.SimpleOrderAccess 
(@SalesPersonPersonID AS INT)
RETURNS TABLE 
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS AccessRight
	WHERE @SalesPersonPersonID in (SELECT OrgID
									FROM sales.UserOrgAccess
									WHERE UserName = USER_NAME())
						OR USER_NAME() = 'dbo';
GO

/*Add filter predicate back*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD FILTER PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Orders;
GO

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD FILTER PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Invoices;
GO

EXECUTE AS USER = 'SalesPerson3'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO