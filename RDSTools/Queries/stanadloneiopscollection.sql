  Use msdb--DB where the tables will b created.
  Declare @samples INT
    declare @sa varchar(30)
	declare @admindb varchar(30)
	  set @sa=''--Need the Sa login hre 
	  set @samples=20 --collectiontime
	  set @admindb ='msdb' -- make sure you enter the DB where the Tables wil lbe created 

 If (EXISTS(SELECT * FROM msdb.dbo.sysjobs WHERE (name = N'SQL_IOCollection')))
                      BEGIN
                                 EXEC msdb.dbo.sp_delete_job @job_name=N'SQL_IOCollection'
                     END
       
  IF (EXISTS(SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' and TABLE_NAME='SQL_DBIOTotal'))
                      BEGIN
                                 DROP TABLE [dbo].[SQL_DBIOTotal];
                      END
               IF (EXISTS(SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' and TABLE_NAME='SQL_DBIO'))
                      BEGIN
                                 DROP TABLE [dbo].[SQL_DBIO];
                      END
                      IF (EXISTS(SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' and TABLE_NAME='SQL_CollectionStatus'))
                      BEGIN
                                 DROP TABLE [dbo].[SQL_CollectionStatus];
                      END
  CREATE TABLE [dbo].[SQL_CollectionStatus](
                                [JobStatus] [nvarchar](10) NOT NULL,
                                 [SPID] [int] NOT NULL,
                                 [CollectionStartTime] [datetime] NOT NULL,
                                 [CollectionEndTime] [datetime] NULL,
                                 [Max_Sample_ID] [bigint] NOT NULL,
                                 [Current_Sample_ID] [bigint] NOT NULL
                      ) ON [PRIMARY]
                      /****** Insert Data -- INCLUDES VARIABLE FROM PARENT SCRIPT -- ******/
                      Declare @Total_Samples bigint
                      Select @Total_Samples = @Samples
                      INSERT dbo.SQL_CollectionStatus (JobStatus, SPID, CollectionStartTime, Max_Sample_ID, Current_Sample_ID)
                      SELECT 'Running',@@SPID,GETDATE(),@Total_Samples,0;
                      /****** Create SQL_DBIOTotal Table  ******/
                      CREATE TABLE [dbo].[SQL_DBIOTotal](
                                 [Sample_ID] [bigint] NOT NULL,
                                 [Database_ID] [int] NULL,
                                 [DBName] [nvarchar](400) NOT NULL,
                                 [Read] [bigint] NOT NULL,
                                 [Written] [bigint] NOT NULL,
                                 [BRead] [bigint] NOT NULL,
                                 [BWritten] [bigint] NOT NULL,
                                 [Throughput] [bigint] NOT NULL,
                                 [TotalIOPs] [bigint] NOT NULL,
                                 [NetPackets] bigint,
                                 [CollectionTime] [datetime] NOT NULL
                                 ) ON [PRIMARY]
                      /****** Create SQL_DBIO Table  ******/
                      CREATE TABLE [dbo].[SQL_DBIO](
                                 [Sample_ID] [bigint] NOT NULL,
                                 [Database_ID] [bigint] NOT NULL,
                                 [DBName] [nvarchar](400) NOT NULL,
                                -- [MBRead] [real] NOT NULL,
                                 --[MBWritten] [real] NOT NULL,
                                 [Read] [bigint] NOT NULL,
                                 [Written] [bigint] NOT NULL,
                                 [BRead] [bigint] NOT NULL,
                                 [BWritten] [bigint] NOT NULL,
                                 [TotalB] [bigint] NOT NULL,
                                 [TotalIOPs] [bigint] NOT NULL,
                                 [Throuput] [bigint] Not Null,
                                 [Netpackets] bigint ,
                                 [CollectionTime] [datetime] NOT NULL
                                  ) ON [PRIMARY]
                      /****** Create SQL_IOCollection Agent  ******/
                      BEGIN TRANSACTION
                      DECLARE @ReturnCode INT
                      SELECT @ReturnCode = 0
                      /****** Object:  JobCategory [[Uncategorized (Local)]]]                     ******/
                      IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
                      BEGIN
                      EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
                      IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
                      END
                      DECLARE @jobId BINARY(16)
                      EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'SQL_IOCollection',
                                            @enabled=1,
                                            @notify_level_eventlog=0,
                                            @notify_level_email=0,
                                            @notify_level_netsend=0,
                                           @notify_level_page=0,
                                            @delete_level=0,
                                           @category_name=N'[Uncategorized (Local)]',
                                            @owner_login_name=@sa, @job_id = @jobId OUTPUT
                   IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
                      /****** Object:  Step [Check_Status]                                                                  ******/
                      EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Check_Status',
                                           @step_id=1,
                                            @cmdexec_success_code=0,
                                            @on_success_action=1,
                                         @on_success_step_id=0,
                                           @on_fail_action=2,
                                            @on_fail_step_id=0,
                                            @retry_attempts=0,
                                           @retry_interval=0,
                                           @os_run_priority=0, @subsystem=N'TSQL',
                                            @command=N'SET QUOTED_IDENTIFIER ON
GO
                     Declare @Current_Sample_ID Bigint
                      If (Select Max_Sample_ID - Current_Sample_ID  from SQL_CollectionStatus) >  0
                                 BEGIN
                                 update dbo.SQL_CollectionStatus
                                 set Current_Sample_ID  = Current_Sample_ID  + 1
                                 Set @Current_Sample_ID = (Select Current_Sample_ID from SQL_CollectionStatus);
                                 INSERT dbo.SQL_DBIOTotal
                                            SELECT
                                           @Current_Sample_ID,
                                            d.Database_ID,
                                          d.name,
                                            SUM(fs.num_of_reads ),
                                            SUM(fs.num_of_writes),
                                            SUM(fs.num_of_bytes_read ),
                                            SUM(fs.num_of_bytes_written),
                                            SUM((fs.num_of_bytes_read)+(fs.num_of_bytes_written)) ,
                                            SUM(fs.num_of_reads + fs.num_of_writes) ,
                                            (select Sum(net_packet_size) as Total_net_packets_used from sys.dm_exec_connections),
                                            GETDATE()
                                 FROM sys.dm_io_virtual_file_stats(default, default) AS fs
                                            INNER JOIN sys.databases d (NOLOCK) ON d.Database_ID = fs.Database_ID
                                 WHERE d.name NOT IN (''master'',''model'',''msdb'', ''distribution'', ''ReportServer'',''ReportServerTempDB'')
                                 and d.state = 0
                                 GROUP BY d.name, d.Database_ID;
                                 Insert into SQL_DBIO
                                 Select @Current_Sample_ID,
                                DR1.Database_ID,
                                 DR1.DBName,
                                 DR2.[Read] - DR1.[Read],
                                 DR2.[Written] - DR1.[Written],
                                 DR2.[BRead] - DR1.[BRead],
                                 DR2.[BWritten] - DR1.[BWritten],
                                 DR2.Throughput - DR1.Throughput,
                                 DR2.TotalIOPs - DR1.TotalIOPs,
                                 0,
                                 DR2.NetPackets - DR1.NetPackets,
                                 DR2.CollectionTime
                                 from dbo.SQL_DBIOTotal as DR1
                                 Inner Join dbo.SQL_DBIOTotal as DR2 ON DR1.Database_ID = DR2.Database_ID
                                 where DR1.Sample_ID = @Current_Sample_ID -1
                                 and DR2.Sample_ID = @Current_Sample_ID;
                                 END
                      Else
                                 BEGIN
                                 update dbo.SQL_CollectionStatus
                                 set [JobStatus] = ''Finished'',
                                 [CollectionEndTime] = GETDATE()
                                 EXEC msdb.dbo.sp_update_job @job_name=N''SQL_IOCollection'',
                                 @enabled=0
                     END
                            go
',
                                            @database_name=@admindb,
                                            @flags=0
                     IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
                                 EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
                      IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
                                 EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'EveryMinute',
                                 @enabled=1,
                                @freq_type=4,
                                 @freq_interval=1,
                                 @freq_subday_type=4,
                                 @freq_subday_interval=1,
                                 @freq_relative_interval=0,
                                 @freq_recurrence_factor=0,
                                @active_start_date=20160426,
                                 @active_end_date=99991231,
                                 @active_start_time=0,
                                @active_end_time=235959
                      IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
                                 EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
                      IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
                                 COMMIT TRANSACTION
                                 GOTO EndSave
                                 QuitWithRollback:
                      IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
                      EndSave:
                      /********* End ************/


