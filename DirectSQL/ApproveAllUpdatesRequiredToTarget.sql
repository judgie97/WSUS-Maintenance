USE [SUSDB]
GO

declare @TargetGroup uniqueidentifier
SELECT @TargetGroup = 'B73CA6ED-5727-47F3-84DE-015E03F6A88A'

declare @Proc nvarchar(50)
declare @RowCnt int
declare @MaxRows int
declare @ExecSql nvarchar(255)
select @RowCnt = 1
select @Proc = 'spDeployUpdate'

declare @Import table (rownum int IDENTITY (1, 1) Primary key NOT NULL , UpdateId nvarchar(36), RevisionNumber int)
insert into @Import (UpdateId, RevisionNumber) SELECT [a].[UpdateId] AS UpdateId, [v].[RevisionNumber] As RevisionNumber
FROM (SELECT [UpdateId]
  FROM [SUSDB].[dbo].[tbUpdateSummaryForAllComputers] s INNER JOIN [SUSDB].[dbo].[tbUpdate] u ON s.LocalUpdateID = u.LocalUpdateID
  WHERE s.NotInstalled > 0 OR s.Downloaded > 0 OR s.Installed > 0 OR s.InstalledPendingReboot > 0 OR s.FAILED > 0 OR s.UNKNOWN > 0) a 
  INNER JOIN [SUSDB].[PUBLIC_VIEWS].[vUpdate] v ON a.UpdateID = v.UpdateId
  WHERE v.IsDeclined = 0

select @MaxRows=count(*) from @Import
while @RowCnt <= @MaxRows
begin
    select @ExecSql = 'exec ' + @Proc + ' ''' + UpdateId + ''',' + CAST(RevisionNumber as nvarchar) + ',0' + ',''' + CAST(@TargetGroup as nvarchar(36))+''',''administrator''' from @Import where rownum = @RowCnt 
    --print @ExecSql
    execute sp_executesql @ExecSql
    Select @RowCnt = @RowCnt + 1
end