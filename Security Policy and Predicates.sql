USE BountyHunters;
GO

--SQL 2016 Select security policies in database
SELECT Name, object_id, type, type_desc,
is_ms_shipped,is_enabled,is_schema_bound
FROM sys.security_policies


--Select security Predicates in database

SELECT * 
FROM sys.security_predicates


USE $Database;
GO

--Create table you want to apply security to
CREATE TABLE Contracts.Contract 
(ContractID				INT			NOT NULL,
 ContractName			VARCHAR(50)	NOT NULL,
 ContractType			INT			NOT NULL,
 ContractDate			DATETIME2   NOT NULL,
 TargetFirstName		VARCHAR(50) NOT NULL,
 TargetLastName			VARCHAR(50)	NULL,
 OrgID					INT			NOT NULL);
GO

--Insert records into table
INSERT INTO Contracts.Contract
(	ContractID,
    ContractName,
	ContractType,
    ContractDate,
    TargetFirstName,
    TargetLastName,
    OrgID
)
VALUES
(1, 'Smuggler2',2,CURRENT_TIMESTAMP, 'Chewbacca',NULL,1),
(1, 'Smuggler1',2,CURRENT_TIMESTAMP, 'Han','Solo',1),
(1, 'RebelAlliance2',1,CURRENT_TIMESTAMP, 'Luke','Skywalker',2),
(1, 'RebelAlliance1',1,CURRENT_TIMESTAMP, 'Leia','Organa',2),
(1, 'RebelAlliance3',1,CURRENT_TIMESTAMP, 'Ben','Kenobi',2),
(1, 'Political1',1,CURRENT_TIMESTAMP, 'Bail','Organa',3),
(1, 'Political2',1,CURRENT_TIMESTAMP, 'JarJar','Binks',3);
GO


--Create users
CREATE USER OrgID1 WITHOUT LOGIN
CREATE USER OrgID2 WITHOUT LOGIN
CREATE USER OrgID3 WITHOUT LOGIN
CREATE USER OrgID4 WITHOUT LOGIN



--Grant Select rights to user above on table
GRANT SELECT ON Contracts.Contract TO OrgID1
GRANT SELECT ON Contracts.Contract TO OrgID2
GRANT SELECT ON Contracts.Contract TO OrgID3
GRANT SELECT ON Contracts.Contract TO OrgID4

	

--Create predicate funtion that will be used in the Security Policy
CREATE FUNCTION Contracts.Fn_OrgAccess
(@OrgID AS INT )
RETURNS TABLE 
WITH SCHEMABINDING  --must have
AS
RETURN SELECT 1 AS AccessRight
	WHERE @OrgID = (CASE WHEN USER_NAME() = ('OrgID1') THEN 1  -- these 3 cases will grant access to only those rows that have the specified OrgID
						 WHEN USER_NAME() = ('OrgID2') THEN 2
						 WHEN USER_NAME() = ('OrgID3') THEN 3
						 END)
					OR USER_NAME() = 'OrgID4'  --These two rows grant access to all rows
					OR USER_NAME() = 'dbo';
GO


--Create security Policy using the predicate function from above
CREATE SECURITY POLICY OrgAccess
ADD FILTER PREDICATE Contracts.fn_OrgAccess(OrgID) ON Contracts.Contract
WITH (STATE = ON)  --turns the policy on


--Execute as user that should only see certain rows
EXECUTE AS USER = 'OrgID3'
SELECT * FROM Contracts.Contract
REVERT 


--Run as yourself
SELECT *
FROM Contracts.Contract


--Run as user who can see all 
EXECUTE AS USER = 'OrgID4'
SELECT * FROM Contracts.Contract
REVERT 



--DROP SECURITY POLICY OrgAccess

--DROP FUNCTION Contracts.Fn_OrgAccess
