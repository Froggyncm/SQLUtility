/*Demo for using HierarchyID 
From online source https://docs.microsoft.com/en-us/sql/relational-databases/tables/lesson-1-2-populating-a-table-with-existing-hierarchical-data
*/

USE HierarchyTest;
GO

/*Create table that will store the HeirarchyID, this can be it's own table or add it to an existing table
uniqueness is not supported natively and the primary key on that column is a way around that limitation*/
CREATE TABLE dbo.NewOrg 
(OrgNode		HIERARCHYID,
OrgID			INT,
OrgName			VARCHAR(64)
CONSTRAINT PK_NewOrg_OrgNode PRIMARY KEY CLUSTERED(OrgNode));
GO

/*Create a temp table that we will need to populate our NewOrg table */
CREATE TABLE #Children
(OrgID			INT,
ParentOrgID		INT,
Num				INT);
GO

/*the exculusion in the where clause is excluding organizations that have no children as this is the test database
and it looks like there are several 'ORG1' organizations created for testing*/
INSERT INTO #Children
(
    OrgID,
    ParentOrgID,
    Num
)
SELECT OrganizationID, ParentOrganizationID,
	ROW_NUMBER() OVER (PARTITION BY ParentOrganizationID ORDER BY ParentOrganizationID)
FROM dbo.Organization
WHERE OrganizationID NOT IN  (
1,
3,
7383,
7561,
8279,
8290,
8301,
8302,
8304,
8315,
8326,
8337,
8348,
8359,
8370,
8381,
8392,
8403,
8418,
8429,
8440,
8451,
8462,
8473,
8484,
8495,
8506,
8517,
8528,
8539,
8550,
8561,
8572,
8583,
8594,
8605,
8616,
8627,
8639
)
;
GO


SELECT *
FROM #Children
ORDER BY ParentOrgID, Num;
GO

/*populate the NewOrg Table*/
WITH paths(path,OrgID)
AS 
(SELECT hierarchyid::GetRoot() AS OrgNode, OrgID
FROM #Children AS C
WHERE C.ParentOrgID = 0

UNION ALL

SELECT CAST(p.path.ToString() + CAST(c.Num AS Varchar(30)) + '/' AS HierarchyID),
C.orgID
FROM #Children AS C
JOIN paths AS p ON c.ParentOrgID = p.OrgID)
INSERT dbo.NewOrg
(
    OrgNode,
    OrgID,
    OrgName
)
SELECT P.path, o.OrganizationID, o.Name
FROM dbo.Organization O
JOIN paths P ON o.OrganizationID = p.OrgID;
GO 

/*Drop temporary table*/
DROP TABLE #Children;
GO

/*Syntax needed to convert the hierarchyid to a more understandable format*/
SELECT OrgNode.ToString() AS LogicalNode, *   
FROM NewOrg   
ORDER BY LogicalNode;  
GO  


/*look at orgid 4537 which is nested by 3 levels*/
SELECT OrganizationID, Name, Description, ParentOrganizationID
FROM dbo.Organization
WHERE OrganizationID IN (4537, 4340, 706);
GO

SELECT OrgNode.ToString() AS LogicalNode, *   
FROM NewOrg   
WHERE
OrgID IN (4537,4340,706);  
GO  

/*Get 3rd level children regardless of parent org*/
SELECT OrgNode.ToString() AS LogicalNode, *  
FROM dbo.NewOrg
WHERE OrgNode.GetLevel() = 3;
GO


/*query to show all children*/
DECLARE @orgnode HIERARCHYID

SELECT @orgnode = OrgNode 
FROM dbo.NewOrg
WHERE OrgName = 'Frampton Insurance Agency'

Select OrgNode.ToString() AS LogicalNode,  OrgID, OrgName
 From dbo.NewOrg
 Where OrgNode.IsDescendantOf(@orgnode) = 1;
 GO

 /*find referees
 */
DECLARE @orgnode HIERARCHYID

SELECT @orgnode = OrgNode 
FROM dbo.NewOrg
WHERE OrgName = 'Frampton Insurance Agency'

SELECT OrgNode.ToString() AS LogicalNode,  OrgID, OrgName
FROM dbo.NewOrg
WHERE @orgnode.IsDescendantOf(OrgNode) = 1;
GO

