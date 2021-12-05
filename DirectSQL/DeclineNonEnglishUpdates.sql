USE [SUSDB]
GO

declare @Proc nvarchar(50)
declare @RowCnt int
declare @MaxRows int
declare @ExecSql nvarchar(255)

select @RowCnt = 1
select @Proc = 'spDeclineUpdate'

-- These next two rows are specific to source table or query
declare @Import table (rownum int IDENTITY (1, 1) Primary key NOT NULL , UpdateId nvarchar(36))
insert into @Import (UpdateId) select UpdateId from (SELECT [UT].[UpdateId] AS [UpdateId]
      ,[LocaleId]
      ,[Title]
      ,[Description]
	  ,[U].[IsDeclined]
  FROM [SUSDB].[PUBLIC_VIEWS].[vUpdateText] UT INNER JOIN [SUSDB].[PUBLIC_VIEWS].[vUpdate] U ON UT.UpdateId = U.UpdateId
  WHERE (NOT LocaleId = 1033) AND IsDeclined = 0) a

select @MaxRows=count(*) from @Import

while @RowCnt <= @MaxRows
begin
    select @ExecSql = 'exec ' + @Proc + ' ''' + UpdateId + '''' from @Import where rownum = @RowCnt 
    --print @ExecSql
    execute sp_executesql @ExecSql
    Select @RowCnt = @RowCnt + 1
end