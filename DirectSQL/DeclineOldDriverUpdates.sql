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
insert into @Import (UpdateId) SELECT [UpdateId]
  FROM [SUSDB].[PUBLIC_VIEWS].[vUpdate]
  WHERE ClassificationId = 'EBFC1FC5-71A4-4F7B-9ACA-3B9A503104A0' AND CreationDate < DATEADD(day, -365, GETDATE()) AND IsDeclined = 0

select @MaxRows=count(*) from @Import

while @RowCnt <= @MaxRows
begin
    select @ExecSql = 'exec ' + @Proc + ' ''' + UpdateId + '''' from @Import where rownum = @RowCnt 
    --print @ExecSql
    execute sp_executesql @ExecSql
    Select @RowCnt = @RowCnt + 1
end