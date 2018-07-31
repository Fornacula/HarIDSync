#
# Regular cron jobs for the haridsync package
#
*/5 * * * *	haridsync	[ -x /usr/bin/haridsync ] && /usr/bin/haridsync sync >> /var/log/haridsync.log 2>&1
