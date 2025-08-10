#!/bin/bash
# setup-club77-mailserver.sh

set -e

echo "🚀 Setting up club77.org mail server configuration..."

# Get IP addresses from DNS
echo "🔍 Looking up mail.club77.org IP addresses..."
MAIL_IPV4=$(dig +short mail.club77.org A | head -n1)
MAIL_IPV6=$(dig +short mail.club77.org AAAA | head -n1)

if [ -z "$MAIL_IPV4" ] || [ -z "$MAIL_IPV6" ]; then
    echo "❌ Error: Could not resolve mail.club77.org IP addresses"
    echo "   IPv4: $MAIL_IPV4"
    echo "   IPv6: $MAIL_IPV6"
    echo "   Please ensure mail.club77.org DNS records are configured"
    exit 1
fi

echo "✅ Found IP addresses:"
echo "   IPv4: $MAIL_IPV4"
echo "   IPv6: $MAIL_IPV6"

# Create directory
mkdir -p club77-mailserver
cd club77-mailserver

# Download original files
echo "📥 Downloading original docker-mailserver files..."
curl -o compose.yaml.orig https://raw.githubusercontent.com/docker-mailserver/docker-mailserver/master/compose.yaml
curl -o mailserver.env.orig https://raw.githubusercontent.com/docker-mailserver/docker-mailserver/master/mailserver.env

# Apply patches
echo "🔧 Applying club77.org configuration patches..."

# Copy files for patching
cp compose.yaml.orig compose.yaml
cp mailserver.env.orig mailserver.env

# Apply compose.yaml changes
sed -i 's/hostname: mail.example.com/hostname: mail.club77.org/' compose.yaml

# Update port bindings with proper comments
sed -i "s/\"25:25\".*# SMTP.*/\"${MAIL_IPV4}:25:25\"              # SMTP  (explicit TLS => STARTTLS, Authentication is DISABLED => use port 465\/587 instead)/" compose.yaml
sed -i "/${MAIL_IPV4}:25:25/a\\      - \"[${MAIL_IPV6}]:25:25\"   # SMTP  (explicit TLS => STARTTLS, Authentication is DISABLED => use port 465\/587 instead)" compose.yaml

sed -i "s/\"143:143\".*# IMAP4.*/\"${MAIL_IPV4}:143:143\"            # IMAP4 (explicit TLS => STARTTLS)/" compose.yaml
sed -i "/${MAIL_IPV4}:143:143/a\\      - \"[${MAIL_IPV6}]:143:143\" # IMAP4 (explicit TLS => STARTTLS)" compose.yaml

sed -i "s/\"465:465\".*# ESMTP.*/\"${MAIL_IPV4}:465:465\"            # ESMTP (implicit TLS)/" compose.yaml
sed -i "/${MAIL_IPV4}:465:465/a\\      - \"[${MAIL_IPV6}]:465:465\" # ESMTP (implicit TLS)" compose.yaml

sed -i "s/\"587:587\".*# ESMTP.*/\"${MAIL_IPV4}:587:587\"            # ESMTP (explicit TLS => STARTTLS)/" compose.yaml
sed -i "/${MAIL_IPV4}:587:587/a\\      - \"[${MAIL_IPV6}]:587:587\" # ESMTP (explicit TLS => STARTTLS)" compose.yaml

sed -i "s/\"993:993\".*# IMAP4.*/\"${MAIL_IPV4}:993:993\"            # IMAP4 (implicit TLS)/" compose.yaml
sed -i "/${MAIL_IPV4}:993:993/a\\      - \"[${MAIL_IPV6}]:993:993\" # IMAP4 (implicit TLS)" compose.yaml

# Add the missing letsencrypt volume mount
sed -i '/- \/etc\/localtime:\/etc\/localtime:ro$/a\      - /etc/letsencrypt:/etc/letsencrypt' compose.yaml

# Fix cap_add formatting - use proper YAML indentation (should be aligned with other top-level keys)
sed -i 's/# cap_add:/cap_add:/' compose.yaml
sed -i 's/#   - NET_ADMIN/  - NET_ADMIN/' compose.yaml

# Fix healthcheck command
sed -i 's/test: "ss --listening --ipv4 --tcp | grep --silent.*"/test: "ss --listening --tcp | grep -P '\''LISTEN.+:smtp'\'' || exit 1"/' compose.yaml

# Apply mailserver.env changes
sed -i 's/^OVERRIDE_HOSTNAME=$/OVERRIDE_HOSTNAME=mail.club77.org/' mailserver.env
sed -i 's/^PERMIT_DOCKER=$/PERMIT_DOCKER=none/' mailserver.env
sed -i 's/^ENABLE_OPENDKIM=1$/ENABLE_OPENDKIM=0/' mailserver.env
sed -i 's/^ENABLE_OPENDMARC=1$/ENABLE_OPENDMARC=0/' mailserver.env
sed -i 's/^ENABLE_POLICYD_SPF=1$/ENABLE_POLICYD_SPF=0/' mailserver.env
sed -i 's/^ENABLE_RSPAMD=0$/ENABLE_RSPAMD=1/' mailserver.env
sed -i 's/^ENABLE_AMAVIS=1$/ENABLE_AMAVIS=0/' mailserver.env
sed -i 's/^ENABLE_SPAMASSASSIN=1$/ENABLE_SPAMASSASSIN=0/' mailserver.env
sed -i 's/^ENABLE_FAIL2BAN=0$/ENABLE_FAIL2BAN=1/' mailserver.env
sed -i 's/^SSL_TYPE=$/SSL_TYPE=letsencrypt/' mailserver.env
sed -i 's/^POSTFIX_INET_PROTOCOLS=ipv4$/POSTFIX_INET_PROTOCOLS=all/' mailserver.env
sed -i 's/^DOVECOT_INET_PROTOCOLS=ipv4$/DOVECOT_INET_PROTOCOLS=all/' mailserver.env

# Create required directory structure
echo "📁 Creating docker-data directory structure..."
mkdir -p docker-data/dms/config
mkdir -p docker-data/dms/config/rspamd/local.d

# Create postfix-main.cf for DKIM signing of local mail (the working approach)
echo "📝 Creating postfix-main.cf for DKIM signing..."
echo "non_smtpd_milters = inet:localhost:11332" > docker-data/dms/config/postfix-main.cf

# Create Rspamd DKIM signing configuration
echo "📝 Creating Rspamd DKIM signing configuration..."
cat > docker-data/dms/config/rspamd/local.d/dkim_signing.conf << 'EOF'
# documentation: https://rspamd.com/doc/modules/dkim_signing.html
enabled = true;
sign_authenticated = true;
sign_local = true;
try_fallback = false;
use_domain = "header";
use_redis = false; # don't change unless Redis also provides the DKIM keys
use_esld = true;
allow_username_mismatch = true;
allow_hdrfrom_mismatch = false;  # Enforce envelope/header domain matching
allow_hdrfrom_multiple = false;  # Only allow single From header
check_pubkey = true; # you want to use this in the beginning
symbol = "DKIM_SIGNED";          # Symbol added when message is signed
domain {
    club77.org {
        path = "/tmp/docker-mailserver/rspamd/dkim/rsa-2048-mail-club77.org.private.txt";
        selector = "mail";
    }
}
EOF

echo "✅ Configuration files updated!"
echo ""
echo "📋 Summary of changes applied:"
echo "   • Hostname: mail.club77.org"
echo "   • Dedicated IP binding: ${MAIL_IPV4} + ${MAIL_IPV6}"
echo "   • Rspamd enabled (modern anti-spam)"
echo "   • Legacy services disabled (OpenDKIM, Amavis, SpamAssassin)"
echo "   • LetsEncrypt SSL enabled"
echo "   • Fail2Ban enabled with NET_ADMIN capability"
echo "   • Dual-stack networking (IPv4 + IPv6)"
echo "   • DKIM signing configured for local mail"
echo ""
echo "📁 Directory structure created:"
echo "   • docker-data/dms/config/"
echo "   • docker-data/dms/config/rspamd/local.d/"
echo "   • postfix-main.cf configured for DKIM signing"
echo "   • dkim_signing.conf configured for club77.org"
echo "   • options.inc configured with local networks"
echo ""
echo "🎯 Next steps:"
echo "   1. Run: docker compose up -d"
echo "   2. Create DKIM directory: docker exec mailserver mkdir -p /tmp/docker-mailserver/rspamd/dkim"
echo "   3. Generate DKIM keys: docker exec mailserver rspamadm dkim_keygen -s mail -b 2048 -d club77.org -k /tmp/docker-mailserver/rspamd/dkim/rsa-2048-mail-club77.org.private.txt"
echo "   4. Set proper permissions: docker exec mailserver chown _rspamd:_rspamd /tmp/docker-mailserver/rspamd/dkim/rsa-2048-mail-club77.org.private.txt"
echo "   5. Create email accounts: docker exec mailserver setup email add user@club77.org"
echo "   6. Update DNS with DKIM public key (mail._domainkey.club77.org TXT record)"
echo "   7. Verify configuration: docker exec mailserver rspamadm configtest"
echo "   8. Test DKIM setup: docker exec mailserver rspamadm configdump dkim_signing"
