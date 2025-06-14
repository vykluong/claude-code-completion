# Install Claude Code shell completion

Please set up tab completion safely:

1. Check what shell I'm using and if Claude completion already exists
2. Show me exactly what files you'll create/modify and where backups will be stored
3. Ask for my permission before making any changes
4. Install the completion script from `src/_claude` (backup any modified files first)
5. Test that `claude mcp <TAB>` works in a new shell
6. Give me the exact commands to rollback if needed

**Safety rules:**
- Backup before modifying (format: `.backup-YYYYMMDD-HHMMSS`)
- Get my "yes" before touching system files
- Auto-restore backups if anything fails