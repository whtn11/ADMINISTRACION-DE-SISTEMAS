su -c "grep juan /etc/vsftpd/vsftpd.conf"
su -c "cat /etc/vsftpd/user_list" 2>/dev/null || su -c "cat /etc/vsftpd/ftpusers"