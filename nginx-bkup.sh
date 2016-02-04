#!/bin/bash
# Webdirectory backup script by DecentM
# This script creates a compressed tarball from your webroot and your databases
# To be able to backup databases, you need a mysql user with these global privileges: SELECT, SHOW DATABASES, LOCK TABLES, RELOAD
####################################################################################################

is_root() {
    if [ "$(id -u)" != "0" ]; then
        return $(false)
    else
        return $(true)
    fi
}

optionsc="0"
add_option() {
        #printf "Adding option "$1" = "$2"\n" # This is debug only
        eval "$1='$2'"
#       eval "$1="$2""
        let optionsc++
}
add_option "optionsc" "1";

# Save the current UNIX timestamp to be able to measure approximate run time
add_option "bkupstart" "$(date +""%s"")"

is_online() {
    wget -q --spider http://google.com
    if [ $? -eq 0 ]; then
        return $(true)
    else
        return $(false)
    fi
}

if [ ! -f settings ]; then
	if is_online; then
        printf "Missing settings file, downloading..."
        wget -q "https://raw.githubusercontent.com/DecentM/nginx-bkup/master/settings"
        printf "\nPlease edit the settings file in the same directory as this script, and try again!\n"
        exit
    else
        printf "Missing settings file and can't download one, exiting..."
    fi
fi

source settings

## CONFIG DELIMETER ##
# Debug level can go from 0 to 5, and is set from the first argument
if [ -f $1 ]; then
        add_option "debuglv" "0";
else
        add_option "debuglv" "$1";
fi

# Create a variable from bash's $RANDOM, which will be used in the filename, so tha
# the chance of overwriting files is minimal at best
add_option "bkupid" '#'"$RANDOM"

# Define debugging functions
# If the debug level is more than 2, we pause at dbgps calls
dbgps() {
        if [ "$debuglv" -gt 2 ]; then
                read -n1 -r -p "Press any key to continue..."
                printf "\n"
        fi
}
# Return true if the debug level is more than 0
is_debug() {
        if [ "$debuglv" -gt 0 ]; then
                return $(true);
        else
                return $(false);
        fi
}
# Print all arguements if is_debug is true (used for verbose logging)
debuglog() {
        if is_debug; then
                printf "$@\n"
        fi
}

debuglog "Functions done"
dbgps

# Get the last part (delimeted by "/") of the webroot string to be used in filenames
bkupdir="$(echo $webroot | rev | cut -d "/" -f1 | rev)"

# Print all set variables by the script if the debig level is 5 or more
if is_debug; then
    printf "Options count is $optionsc\n"
fi

if is_debug; then
        ( set -o posix ; set ) | less | tail -$optionsc
        if [ $debuglv -gt 4 ]; then
                printf "Exiting, because debug level is $debuglv\n"
                exit
        fi
fi
debuglog "Passed all debug steps"
dbgps

printf "Backup ID is $bkupid\n"
dbgps

# Switch to the backup root directory, so we don't have to use absolute paths every time
printf "Switching directory to "
cd $bkuproot
pwd
printf "\n"
dbgps

#printf "Stopping execution to prevent accidental file creation\n"
#exit

# Create a tarball with the previously defined ID and the webroot directory name

# Finalize the backup name by evaluating $namestruc,
# thus replacing the variable names with their content in $bkupfname
add_option "ftitle" "$bkupdir"
eval "bkupfname=$namestruc"

printf "Creating $bkupfname.tar...\n"

printf "Recursively backing up the following folders and files in $webroot:\n"
ls -1 $webroot
tar -cf "$bkupfname.tar" -C $webroot .
dbgps

# Use gzip to compress the created tarball using the strength set in the config
printf "\nCompressing $bkupfname.tar with level $gziplv..."
gzip -$gziplv $bkupfname.tar
debuglog "Gzip complete"
printf "\n"
debuglog "$webroot done"
dbgps

# Check if we have the mysql command, if yes, start backing up the databases
if hash mysql 2>/dev/null; then

# Back up databases
# Note: Planned feature: if no database username is specified, skip this step
printf "\nBacking up database(s)...\n"

# Get all database names from the mysql server, and run the loop for every not skipped database
for I in $(mysql -u$dbus -p$dbpw -e 'show databases' -s --skip-column-names | grep -Ev "($ignoredbs)"); do
        dbgps

        add_option "ftitle" "${I}"
        eval "bkupfname=$namestruc"

        # Dump the current database...
        printf "Dumping ${I}...\n"
        mysqldump -u$dbus -p$dbpw $I > "$bkupfname.sql";

        # ...and use gzip with the appropriate compression level
        printf "Compressing it with $gziplv...\n"
        gzip -$gziplv "$bkupfname.sql";
done
debuglog "Databases done"
else
    printf "\n"
    printf "You don't seem to have the mysql command available, skipping database backups...\n"
fi
dbgps

# Set permissions and ownership defined in the variable, recursively. (using full path & restricted to .gz files, as a precaution)
printf "\n"
printf "Setting permissions:\n"
printf "User: $bkupuser\nGroup: $bkupgroup\nMode: $bkupmode\n"
chmod -R $bkupmode $bkuproot/*.gz
if is_root; then
    chown -R $bkupuser:$bkupgroup $bkuproot/*.gz
else
    printf "The script isn't running as root, but $(whoami). Ownership changing skipped.\n"
fi
dbgps

# Remove files that are older then the config allows. (using full path & restricted to .gz files, as a precaution)
printf "\n"
printf "Deleting these files from $bkuproot, that are older than a week...\n"
find $bkuproot/*.gz -mtime +$filemage -type f
find $bkuproot/*.gz -mtime +$filemage -type f -delete
dbgps

# List the backup driectory, so that if the output is sent by mail, the recipient will have a good understanding on how many files there are
printf "\nPost-backup directory listing of $bkuproot:\n"
ls -lt --block-size=MB $bkuproot
printf "\n"
dbgps

# Use "cd -" to switch back to the directory the user was at before running the script
printf "Switching back\n"
cd -
dbgps

# Finally, subtract the saved UNIX timestamp from the current one, and print it
printf "\n"
printf "Script took $(($(date +""%s"")-$bkupstart)) seconds to run\n"
dbgps
## END OF SCRIPT ##
