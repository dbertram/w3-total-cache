URL="${W3D_HTTP_SERVER_SCHEME}://${W3D_WP_HOST}${W3D_WP_MAYBE_COLON_PORT}${W3D_WP_SITE_URI}"
LIMITED="sudo -u www-data"

echo "Installing WordPress ${W3D_WP_VERSION} at ${W3D_WP_PATH} for ${W3D_HTTP_SERVER_SCHEME}://${W3D_WP_HOST}${W3D_WP_MAYBE_COLON_PORT}${W3D_WP_SITE_URI} ..."

mkdir -pv $W3D_WP_PATH

cd $W3D_WP_PATH

$LIMITED wp core download --version=$W3D_WP_VERSION

echo -n "Installed.  Checking WordPress version... "
$LIMITED wp core version

echo "Creating database and user..."

mysql -uroot <<SQL
CREATE DATABASE wordpress;
CREATE USER wordpress@localhost IDENTIFIED BY 'wordpress';
GRANT USAGE ON *.* TO wordpress@localhost;
GRANT ALL PRIVILEGES ON wordpress.* TO wordpress@localhost;
FLUSH PRIVILEGES;
SQL

echo "Configuring WordPress..."

$LIMITED wp core config --dbname=wordpress --dbuser=wordpress --dbpass=wordpress --extra-php <<PHP
define( 'WP_DEBUG', true );
define( 'WP_DEBUG_LOG', true );
PHP

# Remove default WP_DEBUG false definition
sed -i "/'WP_DEBUG', false/d" wp-config.php

echo "Completing WordPress setup..."

$LIMITED wp core install --url=$URL --title=sandbox --admin_user=admin --admin_password=1 --admin_email=a@b.com --skip-email
# set predefined time format (expected by QA changing post's time)
$LIMITED wp option set time_format "H:i"

# disable any automatic updates
sed -i '2idefine( \"AUTOMATIC_UPDATER_DISABLED\", true );' wp-config.php

# add header mark showing PHP was executed
sed -i '2iheader( \"w3tc_php: executed\" );' wp-config.php

# disable all api calls to check for updates
cp /share/scripts/init-box/templates/disable-wp-updates.php ./disable-wp-updates.php
chown www-data:www-data ./disable-wp-updates.php

sed -i '/require_wp_db();/a require( ABSPATH . \"/disable-wp-updates.php\" );   //w3tc test' wp-settings.php

echo "Change permalink structure..."

# change url structure
$LIMITED wp rewrite structure '/%year%/%monthnum%/%day%/%postname%/'
$LIMITED wp rewrite flush --hard

# extras
if [ "$W3D_WP_NETWORK" = "subdomain" ] || [ "$W3D_WP_NETWORK" = "subdir" ]; then
    echo "Configuring WordPress network for ${W3D_WP_NETWORK}..."
    /share/scripts/init-box/720-wordpress-network.sh
fi

if [ "$W3D_HTTP_SERVER" = "apache" ]; then
    echo "Configuring WordPress for use with Apache..."
    /share/scripts/init-box/750-wordpress-apache-htaccess.sh
fi

if [ "$W3D_WP_CONTENT_PATH" != "${W3D_WP_PATH}wp-content/" ]; then
    echo "Configuring WordPress with an alternate content path: ${W3D_WP_CONTENT_PATH}"
    /share/scripts/init-box/760-wordpress-pathmoved.sh
fi

echo "WordPress setup complete."
