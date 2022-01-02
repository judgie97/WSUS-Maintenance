param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('Initial', 'Hourly', 'Daily', 'Weekly', 'Automatic')]
    [String]$Action
)

function Get-DaysSincePatchTuesday {
    $now = Get-Date
    $firstDayOfMonth = Get-Date -Day 1 -Month $($now.Month) -Year $now.Year

    switch ($firstDayOfMonth.DayOfWeek) {
        "Sunday"    {$thisMonthPT = $firstDayOfMonth.AddDays(9); break}
        "Monday"    {$thisMonthPT = $firstDayOfMonth.AddDays(8); break}
        "Tuesday"   {$thisMonthPT = $firstDayOfMonth.AddDays(7); break}
        "Wednesday" {$thisMonthPT = $firstDayOfMonth.AddDays(13); break}
        "Thursday"  {$thisMonthPT = $firstDayOfMonth.AddDays(12); break}
        "Friday"    {$thisMonthPT = $firstDayOfMonth.AddDays(11); break}
        "Saturday"  {$thisMonthPT = $firstDayOfMonth.AddDays(10); break}
    }

    $firstDayOfLastMonth = Get-Date -Day 1 -Month $($now.AddMonths(-1).Month) -Year $now.AddMonths(-1).Year

    switch ($firstDayOfLastMonth.DayOfWeek) {
        "Sunday"    {$lastMonthPT = $firstDayOfLastMonth.AddDays(9); break}
        "Monday"    {$lastMonthPT = $firstDayOfLastMonth.AddDays(8); break}
        "Tuesday"   {$lastMonthPT = $firstDayOfLastMonth.AddDays(7); break}
        "Wednesday" {$lastMonthPT = $firstDayOfLastMonth.AddDays(13); break}
        "Thursday"  {$lastMonthPT = $firstDayOfLastMonth.AddDays(12); break}
        "Friday"    {$lastMonthPT = $firstDayOfLastMonth.AddDays(11); break}
        "Saturday"  {$lastMonthPT = $firstDayOfLastMonth.AddDays(10); break}
    }

    if($now.date -ge $thisMonthPT.date) {
        $patchTuesday = $thisMonthPT
    } else {
        $patchTuesday = $lastMonthPT
    }

    return ((Get-Date).Date - $patchTuesday.Date).TotalDays
}

function Install-CustomIndexes {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = 
@"
-- Create custom index in tbLocalizedPropertyForRevision
USE [SUSDB]

CREATE NONCLUSTERED INDEX [nclLocalizedPropertyID] ON [dbo].[tbLocalizedPropertyForRevision]
(
        [LocalizedPropertyID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

-- Create custom index in tbRevisionSupersedesUpdate
CREATE NONCLUSTERED INDEX [nclSupercededUpdateID] ON [dbo].[tbRevisionSupersedesUpdate]
(
        [SupersededUpdateID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
"@
    $cmd.CommandTimeout = 3600    
    $cmd.ExecuteNonQuery()
    $conn.Close()
}

function Invoke-DatabaseReindex {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = 
@"
USE SUSDB; 
SET NOCOUNT ON; 
 
-- Rebuild or reorganize indexes based on their fragmentation levels 
DECLARE @work_to_do TABLE ( 
    objectid int 
    , indexid int 
    , pagedensity float 
    , fragmentation float 
    , numrows int 
) 
 
DECLARE @objectid int; 
DECLARE @indexid int; 
DECLARE @schemaname nvarchar(130);  
DECLARE @objectname nvarchar(130);  
DECLARE @indexname nvarchar(130);  
DECLARE @numrows int 
DECLARE @density float; 
DECLARE @fragmentation float; 
DECLARE @command nvarchar(4000);  
DECLARE @fillfactorset bit 
DECLARE @numpages int 
 
-- Select indexes that need to be defragmented based on the following 
-- * Page density is low 
-- * External fragmentation is high in relation to index size 
PRINT 'Estimating fragmentation: Begin. ' + convert(nvarchar, getdate(), 121)  
INSERT @work_to_do 
SELECT 
    f.object_id 
    , index_id 
    , avg_page_space_used_in_percent 
    , avg_fragmentation_in_percent 
    , record_count 
FROM  
    sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL , NULL, 'SAMPLED') AS f 
WHERE 
    (f.avg_page_space_used_in_percent < 85.0 and f.avg_page_space_used_in_percent/100.0 * page_count < page_count - 1) 
    or (f.page_count > 50 and f.avg_fragmentation_in_percent > 15.0) 
    or (f.page_count > 10 and f.avg_fragmentation_in_percent > 80.0) 
 
PRINT 'Number of indexes to rebuild: ' + cast(@@ROWCOUNT as nvarchar(20)) 
 
PRINT 'Estimating fragmentation: End. ' + convert(nvarchar, getdate(), 121) 
 
SELECT @numpages = sum(ps.used_page_count) 
FROM 
    @work_to_do AS fi 
    INNER JOIN sys.indexes AS i ON fi.objectid = i.object_id and fi.indexid = i.index_id 
    INNER JOIN sys.dm_db_partition_stats AS ps on i.object_id = ps.object_id and i.index_id = ps.index_id 
 
-- Declare the cursor for the list of indexes to be processed. 
DECLARE curIndexes CURSOR FOR SELECT * FROM @work_to_do 
 
-- Open the cursor. 
OPEN curIndexes 
 
-- Loop through the indexes 
WHILE (1=1) 
BEGIN 
    FETCH NEXT FROM curIndexes 
    INTO @objectid, @indexid, @density, @fragmentation, @numrows; 
    IF @@FETCH_STATUS < 0 BREAK; 
 
    SELECT  
        @objectname = QUOTENAME(o.name) 
        , @schemaname = QUOTENAME(s.name) 
    FROM  
        sys.objects AS o 
        INNER JOIN sys.schemas as s ON s.schema_id = o.schema_id 
    WHERE  
        o.object_id = @objectid; 
 
    SELECT  
        @indexname = QUOTENAME(name) 
        , @fillfactorset = CASE fill_factor WHEN 0 THEN 0 ELSE 1 END 
    FROM  
        sys.indexes 
    WHERE 
        object_id = @objectid AND index_id = @indexid; 
 
    IF ((@density BETWEEN 75.0 AND 85.0) AND @fillfactorset = 1) OR (@fragmentation < 30.0) 
        SET @command = N'ALTER INDEX ' + @indexname + N' ON ' + @schemaname + N'.' + @objectname + N' REORGANIZE'; 
    ELSE IF @numrows >= 5000 AND @fillfactorset = 0 
        SET @command = N'ALTER INDEX ' + @indexname + N' ON ' + @schemaname + N'.' + @objectname + N' REBUILD WITH (FILLFACTOR = 90)'; 
    ELSE 
        SET @command = N'ALTER INDEX ' + @indexname + N' ON ' + @schemaname + N'.' + @objectname + N' REBUILD'; 
    PRINT convert(nvarchar, getdate(), 121) + N' Executing: ' + @command; 
    EXEC (@command); 
    PRINT convert(nvarchar, getdate(), 121) + N' Done.'; 
END 
 
-- Close and deallocate the cursor. 
CLOSE curIndexes; 
DEALLOCATE curIndexes; 
 
 
IF EXISTS (SELECT * FROM @work_to_do) 
BEGIN 
    PRINT 'Estimated number of pages in fragmented indexes: ' + cast(@numpages as nvarchar(20)) 
    SELECT @numpages = @numpages - sum(ps.used_page_count) 
    FROM 
        @work_to_do AS fi 
        INNER JOIN sys.indexes AS i ON fi.objectid = i.object_id and fi.indexid = i.index_id 
        INNER JOIN sys.dm_db_partition_stats AS ps on i.object_id = ps.object_id and i.index_id = ps.index_id 
 
    PRINT 'Estimated number of pages freed: ' + cast(@numpages as nvarchar(20)) 
END 
 
 
--Update all statistics 
PRINT 'Updating all statistics.' + convert(nvarchar, getdate(), 121)  
EXEC sp_updatestats 
PRINT 'Done updating statistics.' + convert(nvarchar, getdate(), 121)  
"@
    $cmd.CommandTimeout = 259200   
    $cmd.ExecuteNonQuery()
    $conn.Close()
}

function Invoke-DeclineArmUpdates {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = 
@"
USE [SUSDB]

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
  WHERE LocaleId = 1033 AND Title LIKE '%ARM64%' AND IsDeclined = 0) a

select @MaxRows=count(*) from @Import

while @RowCnt <= @MaxRows
begin
    select @ExecSql = 'exec ' + @Proc + ' ''' + UpdateId + '''' from @Import where rownum = @RowCnt 
    --print @ExecSql
    execute sp_executesql @ExecSql
    Select @RowCnt = @RowCnt + 1
end
"@
    $cmd.CommandTimeout = 3600    
    $cmd.ExecuteNonQuery()
    $conn.Close()
}

function Invoke-DeclineX86Updates {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = 
@"
USE [SUSDB]

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
  WHERE LocaleId = 1033 AND Title LIKE '%x86-based%' OR Title LIKE '%x86 Client%' AND IsDeclined = 0) a

select @MaxRows=count(*) from @Import

while @RowCnt <= @MaxRows
begin
    select @ExecSql = 'exec ' + @Proc + ' ''' + UpdateId + '''' from @Import where rownum = @RowCnt 
    --print @ExecSql
    execute sp_executesql @ExecSql
    Select @RowCnt = @RowCnt + 1
end
"@
    $cmd.CommandTimeout = 3600    
    $cmd.ExecuteNonQuery()
    $conn.Close()
}

function Invoke-DeclineOldDriverUpdates {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = 
@"
USE [SUSDB]

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
"@
    $cmd.CommandTimeout = 3600    
    $cmd.ExecuteNonQuery()
    $conn.Close()
}

function Invoke-DeclineSupersededUpdates {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = 
@"
USE [SUSDB]

declare @Proc nvarchar(50)
declare @RowCnt int
declare @MaxRows int
declare @ExecSql nvarchar(255)

select @RowCnt = 1
select @Proc = 'spDeclineUpdate'

-- These next two rows are specific to source table or query
declare @Import table (rownum int IDENTITY (1, 1) Primary key NOT NULL , UpdateId nvarchar(36))
insert into @Import (UpdateId) select UpdateId from (SELECT [UpdateID]
      ,[Declined]
      ,[IsSuperseded]
  FROM [SUSDB].[dbo].[vwMinimalUpdate]
  WHERE Declined = 0 AND IsSuperseded = 1) a

select @MaxRows=count(*) from @Import

while @RowCnt <= @MaxRows
begin
    select @ExecSql = 'exec ' + @Proc + ' ''' + UpdateId + '''' from @Import where rownum = @RowCnt 
    --print @ExecSql
    execute sp_executesql @ExecSql
    Select @RowCnt = @RowCnt + 1
end
"@
    $cmd.CommandTimeout = 3600
    $cmd.ExecuteNonQuery()
    $conn.Close()
}

function Invoke-ApproveUpdatesToTargetGroup {
param (
    [Parameter()]
    [String] $Target
)
    $conn.Open()
    $cmd = $conn.CreateCommand()
$first = @"
USE [SUSDB]

declare @TargetGroup uniqueidentifier
"@

$second = "SELECT @TargetGroup = '$Target'"

$third = @"
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
  WHERE s.NotInstalled > 0 OR s.Downloaded > 0 OR s.Installed > 0 OR s.InstalledPendingReboot > 0 OR s.FAILED > 0) a 
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
"@

    $cmd.CommandText = $first + $second + $third
    $cmd.CommandTimeout = 3600
    $cmd.ExecuteNonQuery()
    $conn.Close()
}

function Invoke-WsusCleanupTool {
    Invoke-WsusServerCleanup -CleanupObsoleteComputers
    Invoke-WsusServerCleanup -CleanupObsoleteUpdates
    Invoke-WsusServerCleanup -CleanupUnneededContentFiles
    Invoke-WsusServerCleanup -CompressUpdates
    Invoke-WsusServerCleanup -DeclineExpiredUpdates
    Invoke-WsusServerCleanup -DeclineSupersededUpdates
}

function Invoke-InitialWsusMaintenance {
    Install-CustomIndexes
    #TODO Ideally we would check the IIS config here
    #Create the scheduled task
    #Create Hourly Task
    $principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 31) -RepetitionDuration (New-TimeSpan -Days (20 * 365))

    $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument '-File C:\Scripts\Invoke-WsusMaintenance.ps1 -Action Automatic'
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "WSUS Maintenance Weekly" -Description "Runs weekly Wsus cleanup and reindex" -Principal $principal

    #Setup the registry keys for the maintenance
    Push-Location
    Set-Location HKLM:
    New-Item -Path .\SOFTWARE -Name WSUSMaintenance
    Get-Item -Path .\SOFTWARE\WSUSMaintenance   | Set-ItemProperty -Name LastWeeklyRun -Value (Get-Date).ToString()
    Get-Item -Path .\SOFTWARE\WSUSMaintenance   | Set-ItemProperty -Name LastDailyRun -Value (Get-Date).ToString()
    Get-Item -Path .\SOFTWARE\WSUSMaintenance   | Set-ItemProperty -Name LastHourlyRun -Value (Get-Date).ToString()
    Pop-Location
}

function Invoke-HourlyWsusMaintenance {
    Invoke-DeclineArmUpdates
    Invoke-DeclineX86Updates
    Invoke-DeclineSupersededUpdates
    Invoke-DeclineOldDriverUpdates

    Push-Location
    Set-Location HKLM:
    Get-Item -Path .\SOFTWARE\WSUSMaintenance   | Set-ItemProperty -Name LastHourlyRun -Value (Get-Date).ToString()
    Pop-Location
}

function Invoke-DailyWsusMaintenance {
    $day = Get-DaysSincePatchTuesday
    if(-not (($day -ge 2) -and ($day -le 12))) {
        (Get-WsusServer).GetSubscription().StartSynchronization()
    }
    if($day -ge 2 -and $day -le 4) {
        Invoke-ApproveUpdatesToTargetGroup -Target $TestComputersGroup
    }
    if($day -eq 9) {
        Invoke-ApproveUpdatesToTargetGroup -Target $AllComputersGroup
    }

    Push-Location
    Set-Location HKLM:
    Get-Item -Path .\SOFTWARE\WSUSMaintenance   | Set-ItemProperty -Name LastDailyRun -Value (Get-Date).ToString()
    Pop-Location
}

function Invoke-WeeklyWsusMaintenance {
    Invoke-DatabaseReindex
    Invoke-WsusCleanupTool

    Push-Location
    Set-Location HKLM:
    Get-Item -Path .\SOFTWARE\WSUSMaintenance   | Set-ItemProperty -Name LastWeeklyRun -Value (Get-Date).ToString()
    Pop-Location
}

$sqlConn = 'server=\\.\pipe\MICROSOFT##WID\tsql\query;database=susdb;trusted_connection=true;'
$conn = New-Object System.Data.SQLClient.SQLConnection($sqlConn)
$AllComputersGroup = 'A0A08746-4DBE-4A37-9ADF-9E7652C0B421'
$TestComputersGroup = 'B73CA6ED-5727-47F3-84DE-015E03F6A88A'


function Invoke-AutomaticWsusMaintenance {
    Push-Location
    Set-Location HKLM:
    $NextWeeklyRun = ([Datetime]::Parse((Get-ItemProperty -Path .\SOFTWARE\WSUSMaintenance\).LastWeeklyRun)).AddDays(7)
    $NextDailyRun = ([Datetime]::Parse((Get-ItemProperty -Path .\SOFTWARE\WSUSMaintenance\).LastDailyRun)).AddDays(1)
    $NextHourlyRun = ([Datetime]::Parse((Get-ItemProperty -Path .\SOFTWARE\WSUSMaintenance\).LastHourlyRun)).AddHours(1)
    Pop-Location

    $TimeNow = Get-Date

    if($TimeNow -gt $NextWeeklyRun)
    {
        Invoke-WeeklyWsusMaintenance
    }

    if($TimeNow -gt $NextDailyRun)
    {
        Invoke-DailyWsusMaintenance
    }

    if($TimeNow -gt $NextHourlyRun)
    {
        Invoke-HourlyWsusMaintenance
    }    
}

switch ($action) {
    "Initial" {
        Invoke-InitialWsusMaintenance
        break
    }
    "Hourly" {
        Invoke-HourlyWsusMaintenance
        break
    }
    "Daily" {
        Invoke-DailyWsusMaintenance
        break
    }
    "Weekly" {
        Invoke-WeeklyWsusMaintenance
        break
    }
    "Automatic" {
        Invoke-AutomaticWsusMaintenance
        break
    }
}
