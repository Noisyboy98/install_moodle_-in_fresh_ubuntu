#!/bin/bash

echo "Enter the version of Moodle you want to install: "
read moodleVersion

# Download Moodle archive 
wget https://download.moodle.org/download.php/direct/stable${moodleVersion}/moodle-latest-${moodleVersion}.tgz

# Extract and move Moodle files to Apache directory
tar -xvzf moodle-latest-${moodleVersion}.tgz
sudo mv 8gagtest /var/www/html/
sudo chown -R www-data:www-data /var/www/html/8gagtest
sudo chmod -R 755 /var/www/html/8gagtest 
sudo systemctl restart nginx

echo "Installation of Moodle ${moodleVersion} complete!"