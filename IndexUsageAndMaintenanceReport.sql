/*=======================================================================================
    Name:        IndexUsageAndMaintenanceReport.sql
    Author:      Alex McAnnally
    Last Edited: 2025-11-23

    Purpose:
        Provide a combined view of index usage and fragmentation to help identify:
            - Unused or rarely used indexes
            - Heavily updated indexes
            - Fragmented indexes with recommended maintenance actions
            - Generated ALTER INDEX maintenance statements

    Notes:
        - Uses sys.dm_db_index_usage_stats and sys.dm_db_index_physical_stats.
        - Run in the context of the target database (see USE statement below).
        - This script is read-only. It only generates maintenance commands; it does not
          execute them. Review before use in production.
=======================================================================================*/

--========================================================================
-- 1. Target database
--========================================================================
USE Database_Name_Here;
GO

--========================================================================
-- 2. Configuration thresholds
--========================================================================
DECLARE @LowFragThreshold     float = 5.0;   -- under this: no action
DECLARE @HighFragThreshold    float = 30.0;  -- above this: REBUILD, between = REORGANIZE
DECLARE @MinPageCount         int   = 1000;  -- ignore tiny indexes below this page count

-- Optional filters for candidate unused indexes
DECLARE @MinUpdateCount       bigint = 100;  -- minimum updates to consider for "unused" candidates

--========================================================================
-- 3. Clean up temp table if it exists
--========================================================================
IF OBJECT_ID('tempdb..#IndexStats') IS NOT NULL
    DROP TABLE #IndexStats;

--========================================================================
-- 4. Gather index usage and fragmentation in a temp table
--========================================================================
;WITH IndexUsage AS
(
    SELECT  
        i.object_id,
        i.index_id,
        user_seeks   = ISNULL(us.user_seeks, 0),
        user_scans   = ISNULL(us.user_scans, 0),
        user_lookups = ISNULL(us.user_lookups, 0),
        user_updates = ISNULL(us.user_updates, 0),
        last_user_seek    = us.last_user_seek,
        last_user_scan    = us.last_user_scan,
        last_user_lookup  = us.last_user_lookup,
        last_user_update  = us.last_user_update
    FROM sys.indexes AS i
    LEFT JOIN sys.dm_db_index_usage_stats AS us
        ON  us.object_id  = i.object_id
        AND us.index_id   = i.index_id
        AND us.database_id = DB_ID()
),
IndexFrag AS
(
    SELECT  
        object_id,
        index_id,
        avg_fragmentation_in_percent,
        page_count
    FROM sys.dm_db_index_physical_stats
    (
        DB_ID(),          -- current database
        NULL,             -- all objects
        NULL,             -- all indexes
        NULL,             -- all partitions
        'LIMITED'         -- mode to reduce overhead
    )
)
SELECT
      DatabaseName  = DB_NAME()
    , SchemaName    = OBJECT_SCHEMA_NAME(i.object_id)
    , TableName     = OBJECT_NAME(i.object_id)
    , IndexName     = i.name
    , i.object_id
    , i.index_id
    , i.type_desc
    , iu.user_seeks
    , iu.user_scans
    , iu.user_lookups
    , iu.user_updates
    , TotalReads    = iu.user_seeks + iu.user_scans + iu.user_lookups
    , TotalWrites   = iu.user_updates
    , iu.last_user_seek
    , iu.last_user_scan
    , iu.last_user_lookup
    , iu.last_user_update
    , frag.avg_fragmentation_in_percent
    , frag.page_count
    , RecommendedAction =
        CASE 
            WHEN frag.page_count IS NULL THEN 'N/A'
            WHEN frag.page_count < @MinPageCount 
                 OR frag.avg_fragmentation_in_percent IS NULL 
                 OR frag.avg_fragmentation_in_percent < @LowFragThreshold
                THEN 'NONE'
            WHEN frag.avg_fragmentation_in_percent >= @LowFragThreshold
                 AND frag.avg_fragmentation_in_percent < @HighFragThreshold
                THEN 'REORGANIZE'
            WHEN frag.avg_fragmentation_in_percent >= @HighFragThreshold
                THEN 'REBUILD'
        END
INTO #IndexStats
FROM sys.indexes AS i
INNER JOIN sys.objects AS o
    ON o.object_id = i.object_id
LEFT JOIN IndexUsage AS iu
    ON iu.object_id = i.object_id
   AND iu.index_id  = i.index_id
LEFT JOIN IndexFrag AS frag
    ON frag.object_id = i.object_id
   AND frag.index_id  = i.index_id
WHERE 
    o.type = 'U'             -- user tables only
    AND i.index_id > 0;      -- exclude heaps here (index_id = 0)

--========================================================================
-- 5. Result set 1: Full index usage and fragmentation overview
--========================================================================
PRINT 'Result set 1: Full index usage and fragmentation overview';
SELECT
      DatabaseName
    , SchemaName
    , TableName
    , IndexName
    , type_desc
    , page_count
    , avg_fragmentation_in_percent
    , user_seeks
    , user_scans
    , user_lookups
    , user_updates
    , TotalReads
    , TotalWrites
    , last_user_seek
    , last_user_scan
    , last_user_lookup
    , last_user_update
    , RecommendedAction
FROM #IndexStats
ORDER BY 
      SchemaName
    , TableName
    , IndexName;

--========================================================================
-- 6. Result set 2: Candidate unused or rarely used indexes
--========================================================================
PRINT 'Result set 2: Candidate unused or rarely used indexes (non-trivial writes, zero reads)';
SELECT
      DatabaseName
    , SchemaName
    , TableName
    , IndexName
    , type_desc
    , page_count
    , avg_fragmentation_in_percent
    , user_updates
    , TotalReads
    , last_user_update
FROM #IndexStats
WHERE 
    TotalReads = 0
    AND user_updates >= @MinUpdateCount
    AND page_count >= @MinPageCount
ORDER BY 
      user_updates DESC
    , page_count DESC;

--========================================================================
-- 7. Result set 3: Fragmented indexes that need attention
--========================================================================
PRINT 'Result set 3: Fragmented indexes with recommended REBUILD or REORGANIZE';
SELECT
      DatabaseName
    , SchemaName
    , TableName
    , IndexName
    , type_desc
    , page_count
    , avg_fragmentation_in_percent
    , RecommendedAction
    , TotalReads
    , TotalWrites
FROM #IndexStats
WHERE 
    RecommendedAction IN ('REBUILD', 'REORGANIZE')
ORDER BY 
      RecommendedAction DESC,
      avg_fragmentation_in_percent DESC;

--========================================================================
-- 8. Result set 4: Generated ALTER INDEX maintenance commands
--========================================================================
PRINT 'Result set 4: Generated ALTER INDEX statements (review before executing)';
SELECT
    MaintenanceCommand =
        'ALTER INDEX [' + IndexName + '] ON [' + SchemaName + '].[' + TableName + '] ' +
        CASE RecommendedAction
            WHEN 'REBUILD'    THEN 'REBUILD;'    -- Consider adding WITH options as needed
            WHEN 'REORGANIZE' THEN 'REORGANIZE;'
            ELSE '/* NO ACTION RECOMMENDED */'
        END
    , RecommendedAction
    , DatabaseName
    , SchemaName
    , TableName
    , IndexName
    , avg_fragmentation_in_percent
    , page_count
FROM #IndexStats
WHERE 
    RecommendedAction IN ('REBUILD', 'REORGANIZE')
ORDER BY 
      RecommendedAction DESC
    , avg_fragmentation_in_percent DESC;

-- End of script
