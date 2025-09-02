#!/bin/bash

DB_USER="root"
DB_PASS="password"
AUTH_DB="admin"

DB_NAMES=("proposals" "quotes")

if ! command -v brew &> /dev/null
then
    echo "Homebrew is not installed. Please install it to proceed."
    exit 1
fi

echo "Tapping the MongoDB Homebrew repository..."
brew tap mongodb/brew

echo "Installing MongoDB database tools..."
brew install mongodb-database-tools

for DB_NAME in "${DB_NAMES[@]}"
do
    echo "---------------------------------------------------------"
    echo "Starting the dump for database: '$DB_NAME'"
    echo "---------------------------------------------------------"

    mongodump --db "$DB_NAME" --username "$DB_USER" --password "$DB_PASS" --authenticationDatabase "$AUTH_DB" --out "."

    if [ $? -eq 0 ]; then
        echo "Database dump for '$DB_NAME' successful!"
        echo "The dump files are located in the './$DB_NAME' directory."
    else
        echo "Error: The mongodump command failed for '$DB_NAME'."
        echo "Please check the database name, credentials, and connection."
    fi
done

echo "---------------------------------------------------------"
echo "All specified database dumps have been completed."
echo "---------------------------------------------------------"