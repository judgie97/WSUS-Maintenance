USE [SUSDB]
GO

declare @Proc nvarchar(50)
declare @RowCnt int
declare @MaxRows int
declare @ExecSql nvarchar(255)

select @RowCnt = 1
select @Proc = 'spDeleteUpdate'

-- These next two rows are specific to source table or query
declare @Import table (rownum int IDENTITY (1, 1) Primary key NOT NULL , LocalUpdateID nvarchar(10))
insert into @Import (LocalUpdateID) SELECT LocalUpdateID
  FROM [SUSDB].[PUBLIC_VIEWS].[vUpdate] v INNER JOIN tbUpdate t ON v.UpdateId=t.UpdateId
  WHERE ClassificationId = 'EBFC1FC5-71A4-4F7B-9ACA-3B9A503104A0' AND CreationDate < DATEADD(day, -730, GETDATE()) AND IsDeclined = 1

select @MaxRows=count(*) from @Import

while @RowCnt <= @MaxRows
begin
    select @ExecSql = 'exec ' + @Proc + ' ''' + LocalUpdateID + '''' from @Import where rownum = @RowCnt 
    --print @ExecSql
    execute sp_executesql @ExecSql
    Select @RowCnt = @RowCnt + 1
end