#!/usr/bin/env bash
set -e

echo "Starting FreePBX Container"

# Database connection settings
DB_HOST="${DB_HOST:-db}"
DB_USER="${DB_USER:-freepbxuser}"
DB_NAME="${DB_NAME:-asterisk}"

# Read password from secret file if it exists
if [ -f /run/secrets/freepbxuser_password ]; then
    DB_PASS=$(cat /run/secrets/freepbxuser_password)
else
    DB_PASS="${DB_PASS:-FreePBXPass123}"
fi

echo "Connecting to database at $DB_HOST as $DB_USER"

# Wait for database
counter=0
until mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" -e "SELECT 1" > /dev/null 2>&1; do
    counter=$((counter+1))
    if [ $counter -gt 30 ]; then
        echo "ERROR: Database connection timeout"
        exit 1
    fi
    echo "Waiting for database... attempt $counter"
    sleep 2
done
echo "✓ Database connected"

# Check if FreePBX is installed
if [ ! -f /var/www/html/admin/index.php ]; then
    echo "Installing FreePBX (takes 5-10 min)"
    cd /usr/local/src/freepbx
    ./install -n --dbhost="$DB_HOST" --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --webroot=/var/www/html --skip-checks
    chown -R asterisk:asterisk /var/www/html /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk
    echo "✓ FreePBX installation complete"
fi

# Start services
/usr/sbin/cron &
service postfix start
/usr/local/src/freepbx/start_asterisk start &
sleep 5
rm -f /var/run/fail2ban/fail2ban.pid /var/run/fail2ban/fail2ban.sock
fail2ban-client start &
echo "✓ FreePBX container ready"
exec apache2ctl -D FOREGROUND

