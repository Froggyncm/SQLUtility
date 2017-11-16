/*Row Level Security is part of SQL Server 2016 and give the ability to securly limit access to rows
based on filter and block predicates by user.
It uses security predicates that can be used to filter out rows for select statments
and explicitly block write operations
MUST RUN RowLevelSecurity-PrepforDemo.sql script first*/

USE RLSecurity;
GO

/*Check for existing security policies or predicates*/
SELECT *
FROM sys.security_policies;
GO

SELECT *
FROM sys.security_predicates;
GO

SELECT pol.[name], pol.is_enabled, pre.predicate_definition, pre.predicate_type_desc, pre.operation_desc, o.[name] AS TableAppliedTo
FROM sys.security_policies pol INNER JOIN sys.security_predicates pre ON pre.object_id = pol.object_id
INNER JOIN sys.objects o ON o.object_id = pre.target_object_id;
GO

/**************
Use two tables Orders and Invoices with FK between*/

/*table to apply RLS to */
SELECT *
FROM Sales.Orders;
GO

SELECT * 
FROM Sales.Invoices;
GO

/*Implement RLS on the orders table*/
SELECT SalespersonPersonID, COUNT(*) AS TotalOrders
FROM Sales.Orders
GROUP BY SalespersonPersonID
ORDER BY SalespersonPersonID

/*Create Users
Names are not the security, but for testing purposes*/
CREATE USER Salesperson2 WITHOUT LOGIN;        --only access to salesperson 2
CREATE USER Salesperson3 WITHOUT LOGIN;        --only access to salesperson 3   
CREATE USER Salesperson6 WITHOUT LOGIN;        --only access to salesperson 6
CREATE USER Salesperson67 WITHOUT LOGIN;       --only access to salesperson 6 and 7
CREATE USER SalesPerson1x WITHOUT LOGIN;       --only access to salesperson 13,14, 15,16
CREATE USER Salespersonall WITHOUT LOGIN;      --only access to all salesperson
GO

/*Users still need select rights on the table
Grant users select rights on table*/
GRANT SELECT ON Sales.Orders TO SalesPerson2;
GRANT SELECT ON Sales.Orders TO SalesPerson3;
GRANT SELECT ON Sales.Orders TO SalesPerson6;
GRANT SELECT ON Sales.Orders TO SalesPerson67;
GRANT SELECT ON Sales.Orders TO SalesPerson1x;
GRANT SELECT ON Sales.Orders TO SalesPersonall;
GO

GRANT SHOWPLAN TO Salesperson2;
GRANT SHOWPLAN TO Salesperson3;
GRANT SHOWPLAN TO Salesperson6;
GRANT SHOWPLAN TO Salesperson67;
GRANT SHOWPLAN TO SalesPerson1x;
GRANT SHOWPLAN TO Salespersonall;
GO


SELECT *
FROM sys.sysusers
WHERE name LIKE 'Sales%'

/*Users currently have access to all rows in the table they have SELECT rights*/
EXECUTE AS USER = 'Salesperson2'
SELECT *
FROM Sales.Orders;
GO
REVERT;
GO

/*Create schema for security 
The functions and policys need to be in the same database*/
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
/*Inline table function, returns a table
Cannot use CTE within this function*/
CREATE FUNCTION Sec.SimpleOrderAccess 
(@SalesPersonPersonID AS INT)  --This variable(s) is used to link to a column(s) in the table the security will be applied to
RETURNS TABLE 
WITH SCHEMABINDING  --This is not option, cannot bind to a security policy without being turned on.  Also allows user with no access to functions to be able to run function)
AS
RETURN SELECT 1 AS SimpleOrderAccess
	WHERE @SalesPersonPersonID = (CASE WHEN USER_NAME() = ('Salesperson2') THEN 2  -- these 3 cases will grant access to only those rows that have the specified ID  
										 WHEN USER_NAME() = ('Salesperson3') THEN 3
										 WHEN USER_NAME() = ('Salesperson6') THEN 6
										 END)
	OR USER_NAME() = 'Salespersonall'			--These two rows grant access to all 
	OR USER_NAME() = 'dbo';                     --Must explicitly grant access to dbo 
GO

/**************************************************************************************/
/*Create the security policy for the table referencing the function in the step above*/
/*************************************************************************************/
CREATE SECURITY POLICY Sec.SimpleSalesPersonAccess											--Descriptive name is best
ADD FILTER PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Orders				--use variable in funciton to apply to column in table to grant access
WITH (STATE = ON);																		--Policy is on and in effect

/*****************Test access**********************************************/

/*Sysadmin access (dbo)*/
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


/*User has select permissions but is not covered under
security policy
Cannot see any row returned*/
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


/*With only one FILTER predicate in place
User can Insert a new row that they then cannot view
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

SELECT OrderID, CustomerID, SalespersonPersonID
FROM Sales.Orders
WHERE OrderID = 73597

/*User has no rights to see the record
compared to user who has rights*/
EXECUTE AS USER = 'SalesPerson2'
SELECT *
FROM Sales.Orders
WHERE OrderID = 73597;
GO
REVERT;
GO

EXECUTE AS USER = 'SalesPerson3'
SELECT *
FROM Sales.Orders
WHERE OrderID = 73597;
GO
REVERT;
GO


/*Even though we gave the user UPDATE rights, 
the filter will not allow updates on rows that 
are filtered, 
this user cannot view this row so they cannot update it */
EXECUTE AS USER = 'SalesPerson2'
UPDATE Sales.Orders
SET ContactPersonID = 6
WHERE OrderID = 73597;
GO
REVERT;
GO

/*Even though we gave the user DELETE priveleges they cannot DELETE a record they cannot view */
EXECUTE AS USER = 'SalesPerson2'
DELETE Sales.Orders
WHERE OrderID = 73597;
GO
REVERT;
GO


/*User SalesPerson2 can however update a row they have access
because we only applied a FILTER predicate and not any BLOCK predicates
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

/*SalesPerson2 can delete a row they have access to,
insert record for salesperson2 */
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


/*BLOCK predicates applies to all write operations
They are set in the BEFORE and AFTER context
	AFTER INSERT and AFTER UPDATE will block a user from inserting a row that would be filtered or blocked by
	the predicate 
	BEFORE UPDATE  will prevent users from updating rows that currently violate the predicate
	BEFORE DELETE can block DELETE operations*/


/*ALTER the security policy to block inserts to rows you cannot view*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
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

/*DROP the security policy, this can be done even if policy is on */
DROP SECURITY POLICY Sec.SimpleSalesPersonAccess   --Policy is ON and has predicates applied to it

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

/*Create security policy with FILTER predicate only*/
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

/*Users now have access to all rows on the table as the policy is off
and no predicates are being applied */
SELECT *
FROM Sales.Orders


/*User who was limited by policy can now 
select on all rows in the table*/
EXECUTE AS USER = 'Salesperson2'
SELECT OrderID, SalespersonPersonID, OrderDate
FROM Sales.Orders;
GO
REVERT;
GO

/****************************/
/*ALTER FUNCTION with policy disabled but not dropped
The system will not allow */
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

/*ENABLE the security policy*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
WITH (STATE = ON);


/*****************************************************************
You must ALTER the security policy and drop the filter predicate
Allowed while the POLICY is ON*/
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


/*Add the security predicate back 
All done while the policy was ON*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD FILTER PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Orders;
GO

/*************************************************************************************/
/*Query second table joined to table with security predicate applied*/
SELECT *
FROM sales.Invoices

GRANT SELECT ON Sales.Invoices TO Salesperson2;

EXECUTE AS USER = 'Salesperson2'
SELECT *
FROM Sales.Invoices
REVERT;
GO

/*Query with inner join to table with no security predicate join works as normal*/
EXECUTE AS USER = 'Salesperson2'
SELECT O.OrderID, o.SalespersonPersonID, I.SalespersonPersonID, I.InvoiceID
FROM Sales.Orders o INNER JOIN Sales.Invoices I ON I.OrderID = o.OrderID
WHERE I.SalespersonPersonID = 3 
REVERT;
GO

/*query with outer join to table we can see the data for that table, but not for the other table*/
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

/*The user should now have access to both rows 3 and 6*/
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

SELECT *
FROM Sales.UserOrgAccess

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

/********************************************************************************************/
/*Add Multiple Filter and Blocks to single table using one security predicate*/
/*****************************************************************************************/

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD BLOCK PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Invoices AFTER INSERT;
GO

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD BLOCK PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Invoices AFTER UPDATE;
GO

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD BLOCK PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Invoices BEFORE UPDATE;
GO

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD BLOCK PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Invoices BEFORE DELETE;
GO

SELECT TOP 10 *
FROM Sales.Invoices
ORDER BY OrderID DESC;
GO

/*Grant rights to user*/
GRANT INSERT, UPDATE, DELETE ON Sales.Invoices TO SalesPerson2;
GO

/*User who has rights can insert row for same security row*/
EXECUTE AS USER = 'SalesPerson2'
INSERT INTO Sales.Invoices
(InvoiceID,CustomerID,BillToCustomerID,OrderID,DeliveryMethodID,ContactPersonID,AccountsPersonID,SalespersonPersonID,PackedByPersonID,InvoiceDate,CustomerPurchaseOrderNumber,
    IsCreditNote,CreditNoteReason,Comments,DeliveryInstructions,InternalComments,TotalDryItems,TotalChillerItems,DeliveryRun,RunPosition,ReturnedDeliveryData,ConfirmedDeliveryTime,
    ConfirmedReceivedBy,LastEditedBy,LastEditedWhen)
VALUES
( 70511, 905, 905, 5, 3, 3105, 3105, 2, 14, N'2013-01-01T00:00:00', N'10369', 
0, NULL, NULL, N'Shop 30, 1476 Poddar Lane', NULL, 3, 0, N'', N'', N'{"Events": [{ "Event":"Ready for collection","EventTime":"2013-01-01T12:00:00","ConNote":"EAN-125-1055"},
{ "Event":"DeliveryAttempt","EventTime":"2013-01-02T07:25:00","ConNote":"EAN-125-1055","DriverID":15,"Latitude":45.7849627,"Longitude":-93.5569028,"Status":"Delivered"}],
"DeliveredWhen":"2013-01-02T07:25:00","ReceivedBy":"Sara Huiting"}', N'2013-01-02T07:25:00', N'Sara Huiting', 15, N'2013-01-02T07:00:00' );
GO
REVERT;
GO

/*User Cannot insert records that they cannot SELECT*/
EXECUTE AS USER = 'SalesPerson2'
INSERT INTO Sales.Invoices
(InvoiceID,CustomerID,BillToCustomerID,OrderID,DeliveryMethodID,ContactPersonID,AccountsPersonID,SalespersonPersonID,PackedByPersonID,InvoiceDate,CustomerPurchaseOrderNumber,
    IsCreditNote,CreditNoteReason,Comments,DeliveryInstructions,InternalComments,TotalDryItems,TotalChillerItems,DeliveryRun,RunPosition,ReturnedDeliveryData,ConfirmedDeliveryTime,
    ConfirmedReceivedBy,LastEditedBy,LastEditedWhen)
VALUES
( 70512, 905, 905, 5, 3, 3105, 3105, 3, 14, N'2013-01-01T00:00:00', N'10369',     --- insert salesperson 3
0, NULL, NULL, N'Shop 30, 1476 Poddar Lane', NULL, 3, 0, N'', N'', N'{"Events": [{ "Event":"Ready for collection","EventTime":"2013-01-01T12:00:00","ConNote":"EAN-125-1055"},
{ "Event":"DeliveryAttempt","EventTime":"2013-01-02T07:25:00","ConNote":"EAN-125-1055","DriverID":15,"Latitude":45.7849627,"Longitude":-93.5569028,"Status":"Delivered"}],
"DeliveredWhen":"2013-01-02T07:25:00","ReceivedBy":"Sara Huiting"}', N'2013-01-02T07:25:00', N'Sara Huiting', 15, N'2013-01-02T07:00:00' );
GO
REVERT;
GO


/*INSERT Row for salesperson 3 as sysadmin*/
INSERT INTO Sales.Invoices
(InvoiceID,CustomerID,BillToCustomerID,OrderID,DeliveryMethodID,ContactPersonID,AccountsPersonID,SalespersonPersonID,PackedByPersonID,InvoiceDate,CustomerPurchaseOrderNumber,
    IsCreditNote,CreditNoteReason,Comments,DeliveryInstructions,InternalComments,TotalDryItems,TotalChillerItems,DeliveryRun,RunPosition,ReturnedDeliveryData,ConfirmedDeliveryTime,
    ConfirmedReceivedBy,LastEditedBy,LastEditedWhen)
VALUES
( 70513, 905, 905, 5, 3, 3105, 3105, 3, 14, N'2013-01-01T00:00:00', N'10369', 
0, NULL, NULL, N'Shop 30, 1476 Poddar Lane', NULL, 3, 0, N'', N'', N'{"Events": [{ "Event":"Ready for collection","EventTime":"2013-01-01T12:00:00","ConNote":"EAN-125-1055"},
{ "Event":"DeliveryAttempt","EventTime":"2013-01-02T07:25:00","ConNote":"EAN-125-1055","DriverID":15,"Latitude":45.7849627,"Longitude":-93.5569028,"Status":"Delivered"}],
"DeliveredWhen":"2013-01-02T07:25:00","ReceivedBy":"Sara Huiting"}', N'2013-01-02T07:25:00', N'Sara Huiting', 15, N'2013-01-02T07:00:00' );
GO

SELECT * FROM Sales.Invoices
WHERE InvoiceID = 70513

/*User Cannot update a record they cannot select*/
EXECUTE AS USER = 'SalesPerson2'
UPDATE Sales.Invoices
SET SalespersonPersonID = 2   --Update existing row from Salesperson3 to Salesperson2
WHERE InvoiceID = 70513;
GO
REVERT;
GO

/*User cannot delete row they do not have access to SELECT*/
EXECUTE AS USER = 'SalesPerson2'
DELETE Sales.Invoices        --salespersonid3
WHERE InvoiceID = 70513;
GO
REVERT;
GO

/*DROP Predicates from table for next section*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
DROP FILTER PREDICATE ON Sales.Invoices

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
DROP BLOCK PREDICATE ON Sales.Invoices AFTER INSERT;
GO

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
DROP BLOCK PREDICATE ON Sales.Invoices AFTER UPDATE;
GO

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
DROP BLOCK PREDICATE ON Sales.Invoices BEFORE UPDATE;
GO

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
DROP BLOCK PREDICATE ON Sales.Invoices BEFORE DELETE;
GO


/*********************************************************************************/
/*Add Mulitple Filter and Block predicates to same table*/
/********************************************************************************/

/*Create new Security function */
CREATE FUNCTION sec.SecondSecFunction 
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
GO

/*Add both functions to table, on for filter and one for block
You can add multiple predicates on the same table but only one per type of predicate*/
ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD FILTER PREDICATE Sec.SimpleOrderAccess(SalesPersonPersonID) ON Sales.Invoices;              ---Predicate SIMPLEORDERACCESS
GO

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD BLOCK PREDICATE Sec.SecondSecFunction(SalesPersonPersonID) ON Sales.Invoices AFTER INSERT;         --Predicate SECONDSECFUNCITON
GO

ALTER SECURITY POLICY Sec.SimpleSalesPersonAccess
ADD BLOCK PREDICATE Sec.SecondSecFunction(SalesPersonPersonID) ON Sales.Invoices AFTER UPDATE;           --Predicate SECONDSECFUNCITON
GO

SELECT pol.[name], pol.is_enabled, pre.predicate_definition, pre.predicate_type_desc, pre.operation_desc, o.[name] AS TableAppliedTo
FROM sys.security_policies pol INNER JOIN sys.security_predicates pre ON pre.object_id = pol.object_id
INNER JOIN sys.objects o ON o.object_id = pre.target_object_id


SELECT *
FROM sys.security_predicates


/*********************************************************************/
/*Create second policy to apply different security predicate to same table same column*/
/***********************************************************************/

/*Will Fail as you can only have one security predicate (by type and table) on a table)*/
CREATE SECURITY POLICY Sec.SecondPolicy
ADD BLOCK PREDICATE Sec.SecondSecFunction(SalesPersonPersonID) ON Sales.Invoices BEFORE DELETE
WITH (STATE = ON);



/*****************************************************************************************/
/*Create second security predicate for same table and different column*/
/**************************************************************************************/

/*Cannot create security policy even with filter predicate using a differen column*/
CREATE SECURITY POLICY Sec.SecondPolicy
ADD FILTER PREDICATE Sec.SecondSecFunction(PackedbyPersonID) ON Sales.Invoices;
GO


/*********************************************************************************/
/*Cannot create Policy or Predicate in another database*/
USE Demo1;
GO

CREATE FUNCTION dbo.SecondDatabase
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
GO

USE RLSecurity;
GO

/*Cannot apply Predicate in one database to security policy in different database*/
CREATE SECURITY POLICY Sec.SecondPolicy
ADD BLOCK PREDICATE Demo1.dbo.SecondDatabase(SalesPersonPersonID) ON Sales.Orders 
WITH (STATE = ON);
GO

/*Cannot create policy in one database and applied table is in another database*/
USE Demo1;
GO

CREATE SECURITY POLICY dbo.SecondPolicy
ADD FILTER PREDICATE dbo.SecondDatabase(SalesPersonPersonID) ON RowLevelSecurity.Sales.Orders AFTER INSERT
WITH (STATE = ON);
GO



/***************************************************************************************************************************************/
/*How Security is applied and the overhead cost*/
/**************************************************************************************************************************************/
USE RLSecurity;
GO

/*Created Sample tables with 50 users and table with 5 million rows*/
SELECT *
FROM Sales.SampleUser;
GO

/*Created table with 5 million rows*/

SELECT *
FROM Sales.SampleData

SELECT UserID, COUNT(*)
FROM Sales.SampleData
GROUP BY UserID;
GO

/*Each table has a primary key, Sample data has FK to Sample User table
and NonClustered Indexes created on table*/

--ALTER TABLE Sales.SampleData WITH CHECK 
--	ADD CONSTRAINT fk_Sampledata_Sampleuser	FOREIGN KEY (UserID)
--	REFERENCES Sales.SampleUser(UserID);
--GO

--CREATE NONCLUSTERED INDEX [IX_SampleData_CreateDate] ON [dbo].[SampleData] ([CreateDate] ASC) 
--GO
--CREATE NONCLUSTERED INDEX [IX_SampleData_UserID] ON [dbo].[SampleData] ([UserID] ASC) 
--GO
--CREATE NONCLUSTERED INDEX [IX_SampleUser_Username] ON [dbo].[SampleUser] ([Username] ASC) 
--GO


/*Create users and then run queries while SQL Trace is running 
This will be used to compare to after RLS is implemented on the table*/
CREATE LOGIN test_sa WITH PASSWORD = N'testsa', DEFAULT_DATABASE = master,
	CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;    ---apply only to check expiration and windows policy for login
GO

ALTER SERVER ROLE sysadmin ADD MEMBER test_sa;
GO

CREATE LOGIN User10 WITH PASSWORD = N'User10', DEFAULT_DATABASE = master,
	CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
	GO

CREATE USER User10 FOR LOGIN User10;
GO

ALTER ROLE db_datareader ADD MEMBER User10;
GO


/*Login as sysadmin and implement RLS on the table SampleData*/
USE RLSecurity;
GO

CREATE FUNCTION dbo.fn_securitypredicateUser (@UserID int)
RETURNS TABLE
WITH Schemabinding
AS
   RETURN SELECT 1 AS [fn_securitypredicateUser_result]
           FROM Sales.SampleUser SU
           WHERE (SU.UserID = @UserID AND SU.Username = USER_NAME())
              OR IS_SRVROLEMEMBER(N'sysadmin') = 1;
GO

CREATE SECURITY POLICY fn_security
ADD FILTER preDICATE dbo.fn_securitypredicateUser(UserID)
ON Sales.SampleData
WITH (STATE = ON);
GO


/*Run with sa account*/

SELECT *
FROM Sales.SampleData;
GO

/*Login as user10*/
USE RLSecurity;
GO

SELECT *
FROM Sales.SampleData;
GO

SELECT 1/(FloatColumn-517.89)
FROM Sales.SampleData
WHERE UserID = 3 
GO