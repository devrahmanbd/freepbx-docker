#!/usr/bin/env bash
set -e

echo "=================================================="
echo "Starting FreePBX Container"
echo "=================================================="

# Wait for database to be ready
echo "Waiting for database connection..."
DB_HOST="${DB_HOST:-db}"
DB_USER="${DB_USER:-freepbxuser}"
DB_PASS="${DB_PASS:-FreePBXPass123}"
DB_NAME="${DB_NAME:-asterisk}"

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

# Check if FreePBX is already installed
if [ ! -f /var/www/html/admin/index.php ]; then
    echo "=================================================="
    echo "Installing FreePBX (first time - takes 5-10 min)"
    echo "=================================================="
    
    cd /usr/local/src/freepbx
    
    # Install FreePBX
    ./install -n \
        --dbhost="$DB_HOST" \
        --dbname="$DB_NAME" \
        --dbuser="$DB_USER" \
        --dbpass="$DB_PASS" \
        --webroot=/var/www/html \
        --astetcdir=/etc/asterisk \
        --astmoddir=/usr/lib64/asterisk/modules \
        --astvarlibdir=/var/lib/asterisk \
        --astagidir=/usr/share/asterisk/agi-bin \
        --astspooldir=/var/spool/asterisk \
        --astrundir=/var/run/asterisk \
        --astlogdir=/var/log/asterisk \
        --ampbin=/var/lib/asterisk/bin \
        --ampsbin=/usr/local/sbin \
        --ampcgi=/var/www/cgi-bin \
        --ampwebroot=/var/www/html \
        --skip-checks
    
    # Fix permissions
    chown -R asterisk:asterisk /var/www/html
    chown -R asterisk:asterisk /etc/asterisk
    chown -R asterisk:asterisk /var/lib/asterisk
    chown -R asterisk:asterisk /var/log/asterisk
    chown -R asterisk:asterisk /var/spool/asterisk
    
    # Install all modules
    echo "Installing FreePBX modules..."
    /var/lib/asterisk/bin/fwconsole ma installall || true
    /var/lib/asterisk/bin/fwconsole reload
    
    echo "=================================================="
    echo "✓ FreePBX installation complete"
    echo "=================================================="
else
    echo "✓ FreePBX already installed, skipping installation"
fi

# Start cron
echo "Starting cron..."
/usr/sbin/cron &

# Start postfix email service
echo "Starting postfix..."
service postfix start

# Start Asterisk service
echo "Starting Asterisk..."
/usr/local/src/freepbx/start_asterisk start &

# Give Asterisk time to start
sleep 5

# Start Fail2ban
echo "Starting Fail2ban..."
rm -f /var/run/fail2ban/fail2ban.pid /var/run/fail2ban/fail2ban.sock
fail2ban-client start &

# Start Apache
echo "Starting Apache..."
echo "=================================================="
echo "✓ FreePBX container ready"
echo "Access: https://pbx.cloudman.one"
echo "=================================================="

exec apache2ctl -D FOREGROUND
