# sql-server-index-maintenance-helper
A SQL Server utility that analyzes index usage, fragmentation, and maintenance needs. Includes reports for unused indexes, fragmentation thresholds, and auto-generated REBUILD/REORGANIZE statements to support performance tuning and database health monitoring.

# SQL Server Index Maintenance Helper

This repository contains `IndexUsageAndMaintenanceReport.sql`, a SQL Server utility script that provides a complete view of index health, usage, and recommended maintenance actions. It consolidates usage statistics and fragmentation metrics into clear, actionable reports.

## Features

- Identify unused or rarely used indexes
- Measure fragmentation and page counts using `dm_db_index_physical_stats`
- Highlight heavily updated indexes that may not be beneficial
- Recommend REBUILD or REORGANIZE based on configurable thresholds
- Generate ALTER INDEX commands (not executed automatically)
- Designed for DBAs, SQL Developers, and performance optimization workflows

## How It Works

The script combines:

- `sys.dm_db_index_usage_stats` for seeks, scans, lookups, and updates  
- `sys.dm_db_index_physical_stats` for fragmentation and page distribution  
- `sys.indexes` + `sys.objects` metadata  
- Configurable thresholds for:
  - Fragmentation
  - Minimum index size (page count)
  - Minimum update activity

All results are stored in a temp table (`#IndexStats`) and returned in four result sets:

1. **Full Usage + Fragmentation Overview**  
2. **Candidate Unused Indexes**  
3. **Fragmented Indexes Requiring Maintenance**  
4. **Generated REBUILD/REORGANIZE Commands**

## Usage

1. Open the script in SSMS or Azure Data Studio  
2. Update the `USE Database_Name_Here;` line  
3. (Optional) Adjust thresholds at the top of the script  
4. Execute and review the results  
5. Copy generated ALTER INDEX commands into your maintenance plan if appropriate

## Requirements

- SQL Server 2016 or later (compatible with earlier versions if DMVs exist)
- Sufficient permissions to query DMVs

## Why This Script?

Index performance is a major factor in SQL Server optimization. This tool provides instant insights into:

- Whether indexes are helping or hurting performance  
- Whether maintenance is overdue  
- Whether storage or read/write patterns indicate inefficiencies  

It’s ideal for both ad-hoc health checks and scheduled maintenance planning.

## License

MIT License. Free to use and modify.

