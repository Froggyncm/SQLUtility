ALTER PROCEDURE [Organization].[OrganizationSetHierarchyID] @ProcessExceptions CHAR(3),  @ServerExecutionID BIGINT
AS
SET NOCOUNT ON;

CREATE TABLE #PreStage
(OrganizationID         INT,
ParentOrganizationID    INT,
LastModified            DATETIME2,
DWLoadDate              DATETIME2);

CREATE TABLE #Processing
(OrganizationID         INT,
ParentOrganizationID    INT,
Num                     INT,
OrganizationHierarchyID HIERARCHYID);

CREATE TABLE #UpdateHierarchy
(OrganizationID         INT,
OrganizationHierarchyID HIERARCHYID);

INSERT INTO #PreStage 
(OrganizationID, ParentOrganizationID, LastModified, DWLoadDate)
SELECT OrganizationID, ParentOrganizationID, LastModified, DWLoadDate
FROM Organization.ParentOrganizationXRefOrganization;

--Find circular references
WITH FindRoot (OrganizationID, ParentOrganizationID, Path, Distance) 
AS
(SELECT a.OrganizationID, a.ParentOrganizationID, CAST(a.OrganizationID AS NVARCHAR(MAX)) Path, 0 Distance
FROM #PreStage a
UNION ALL
SELECT c.OrganizationID, b.ParentOrganizationID, c.Path + N' > ' + CAST(b.OrganizationID AS NVARCHAR(MAX)), c.Distance + 1
FROM #PreStage b INNER JOIN FindRoot c ON b.OrganizationID = c.ParentOrganizationID AND b.ParentOrganizationID <> b.OrganizationID AND c.ParentOrganizationID <> c.OrganizationID
/*this limits the recursion for nested circular references, this number should always be greater than the longest hierarchy distance between organizations */
WHERE c.Distance < 50),
IdentifyCircularOrgs 
AS
(SELECT d.OrganizationID
FROM FindRoot d
WHERE d.OrganizationID = d.ParentOrganizationID AND d.ParentOrganizationID <> 0 AND d.Distance > 0),
IdentifyNestedOrgs (OrganizationID)
AS 
(SELECT e.OrganizationID
FROM #PreStage e
WHERE EXISTS (SELECT 1 FROM IdentifyCircularOrgs f WHERE f.OrganizationID = e.ParentOrganizationID)
    AND NOT EXISTS (SELECT 1 FROM IdentifyCircularOrgs g WHERE g.OrganizationID = e.OrganizationID)),
IdentifyChildOrgs (RelationLevel, OrganizationID, ParentOrganizationID)
AS
(SELECT 1 AS RelationLevel, h.OrganizationID, h.ParentOrganizationID
FROM #PreStage h
WHERE h.OrganizationID IN (SELECT i.OrganizationID FROM IdentifyNestedOrgs i) 
UNION ALL
SELECT RelationLevel + 1, k.OrganizationID, k.ParentOrganizationID
FROM IdentifyChildOrgs j INNER JOIN  Organization.ParentOrganizationXRefOrganization k ON k.ParentOrganizationID = j.OrganizationID),
RemoveOrgs (OrganizationID) 
AS 
(SELECT OrganizationID
FROM IdentifyCircularOrgs
UNION ALL
SELECT OrganizationID
FROM IdentifyNestedOrgs
UNION ALL
SELECT OrganizationID
FROM IdentifyChildOrgs)
--Remove Circular organizations and insert into exceptions
DELETE FROM s
OUTPUT Deleted.OrganizationID, Deleted.ParentOrganizationID, Deleted.LastModified, @ServerExecutionID ServerExecutionID, Deleted.DWLoadDate, 0 ErrorCode, 0 ErrorColumn, 
    'Circular ParentOrganizationID Reference' ErrorDescription
INTO zExceptionEZLynx.ParentOrganizationXRefOrganization
(OrganizationID, ParentOrganizationID, LastModified, ServerExecutionID, DWLoadDate, ErrorCode, ErrorColumn, ErrorDescription)
FROM #PreStage s
WHERE s.OrganizationID IN (SELECT DISTINCT l.OrganizationID FROM RemoveOrgs l);

INSERT INTO #Processing
(OrganizationID, ParentOrganizationID, Num, OrganizationHierarchyID)
SELECT OrganizationID, ParentOrganizationID, ROW_NUMBER() OVER (PARTITION BY ParentOrganizationID ORDER BY ParentOrganizationID), NULL 
FROM #PreStage;

--Set HierarchyID and update the Organization table
WITH paths(path, OrganizaitonID, ParentOrganizationID)
AS 
(SELECT hierarchyid::GetRoot() AS OrgNode, a1.OrganizationID, a1.ParentOrganizationID
FROM #Processing AS a1
WHERE a1.OrganizationID = 0
UNION ALL
SELECT CAST(c1.path.ToString() + CAST(b1.OrganizationID AS VARCHAR(MAX)) + '/' AS HIERARCHYID), b1.OrganizationID, b1.ParentOrganizationID
FROM #Processing AS b1 INNER JOIN paths AS c1 ON b1.ParentOrganizationID = c1.OrganizaitonID
WHERE b1.OrganizationID <> 0)
INSERT #UpdateHierarchy
(OrganizationID, OrganizationHierarchyID)
SELECT e1.OrganizaitonID, e1.path
FROM Organization.Organization d1 INNER JOIN paths e1 ON d1.OrganizationID = e1.OrganizaitonID
OPTION (MAXRECURSION 0);

UPDATE a2
SET a2.OrganizationHierarchyID = ISNULL(b2.OrganizationHierarchyID,NULL)
FROM Organization.Organization a2 LEFT OUTER JOIN #UpdateHierarchy b2 ON b2.OrganizationID = a2.OrganizationID
WHERE EXISTS (SELECT a2.OrganizationHierarchyID EXCEPT SELECT b2.OrganizationHierarchyID);

--Delete from exceptions
DELETE FROM a3
FROM zExceptionEZLynx.ParentOrganizationXRefOrganization a3 INNER JOIN Organization.Organization b3 ON b3.OrganizationID = a3.OrganizationID
WHERE b3.OrganizationHierarchyID IS NOT NULL AND a3.ErrorDescription = 'Circular ParentOrganizationID Reference';

