#!/bin/bash

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run with administrative privileges. Please run with sudo."
   exit 1
fi

echo "Creating docker-compose.yml for Riven..."

# Prompt for environment variables that require user input
read -p "Enter your RIVEN_PLEX_TOKEN: " RIVEN_PLEX_TOKEN
if [ -z "$RIVEN_PLEX_TOKEN" ]; then
    echo "Error: RIVEN_PLEX_TOKEN cannot be empty."
    exit 1
fi

# If RIVEN_PLEX_URL is not set (Plex was not installed by script), prompt for it
if [ -f RIVEN_PLEX_URL.txt ]; then
    RIVEN_PLEX_URL=$(cat RIVEN_PLEX_URL.txt)
else
    read -p "Enter your RIVEN_PLEX_URL: " RIVEN_PLEX_URL
    if [ -z "$RIVEN_PLEX_URL" ]; then
        echo "Error: RIVEN_PLEX_URL cannot be empty."
        exit 1
    fi
fi

# Get PUID and PGID from the user who invoked sudo
PUID=$(id -u "$SUDO_USER")
PGID=$(id -g "$SUDO_USER")

# Export PUID, PGID, and TZ to be used in docker-compose.yml
export PUID PGID
export TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")

ORIGIN="http://$(hostname -I | awk '{print $1}'):3000"

# ZURG_ALL_PATH is /mnt/zurg/__all__
read -p "Enter the zurg __all__ folder directory path (default is /mnt/zurg/__all__): " ZURG_ALL_PATH
ZURG_ALL_PATH=${ZURG_ALL_PATH:-/mnt/zurg/__all__}

# Read RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY from a file (if stored)
if [ -f RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY.txt ]; then
    RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY=$(cat RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY.txt)
else
    read -p "Enter your RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY: " RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY
    if [ -z "$RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY" ]; then
        echo "Error: RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY cannot be empty."
        exit 1
    fi
fi

# Create the .env file for environment variables
cat <<EOF > .env
PUID=$PUID
PGID=$PGID
TZ=$TZ
EOF

echo ".env file created with PUID, PGID, and TZ."

# Create the docker-compose.yml file
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  riven-frontend:
    container_name: riven-frontend
    image: spoked/riven-frontend:latest
    restart: unless-stopped
    ports:
      - "3000:3000"
    tty: true
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
      - ORIGIN=$ORIGIN
      - BACKEND_URL=http://riven:8080
      - DIALECT=postgres
      - DATABASE_URL=postgres://postgres:postgres@riven-db/riven
    depends_on:
      riven:
        condition: service_healthy
    networks:
      - riven_network

  riven:
    container_name: riven
    image: spoked/riven:latest
    restart: unless-stopped
    ports:
      - "8080:8080"
    tty: true
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
      - RIVEN_FORCE_ENV=true
      - RIVEN_DATABASE_HOST=postgresql+psycopg2://postgres:postgres@riven-db/riven
      - RIVEN_PLEX_URL=$RIVEN_PLEX_URL
      - RIVEN_PLEX_TOKEN=$RIVEN_PLEX_TOKEN
      - RIVEN_PLEX_RCLONE_PATH=/mnt/zurg/__all__
      - RIVEN_PLEX_LIBRARY_PATH=/mnt/library
      - RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED=true
      - RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY=$RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY
      - RIVEN_ORIGIN=$ORIGIN
      - REPAIR_SYMLINKS=false
      - HARD_RESET=false
    healthcheck:
      test: ["CMD-SHELL", "curl -s http://localhost:8080 >/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 10
    volumes:
      - ./riven:/riven/data
      - $ZURG_ALL_PATH:/zur
      - /mnt/library:/mnt/library
      - $ZURG_ALL_PATH:/mnt/zurg/__all__
    depends_on:
      riven_postgres:
        condition: service_healthy
    networks:
      - riven_network

  riven_postgres:
    container_name: riven-db
    image: postgres:16.3-alpine3.20
    environment:
      PGDATA: /var/lib/postgresql/data/pgdata
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: riven
    volumes:
      - ./riven-db:/var/lib/postgresql/data/pgdata
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - riven_network

networks:
  riven_network:
    driver: bridge
EOF

if [ $? -ne 0 ]; then
    echo "Error: Failed to create docker-compose.yml."
    exit 1
fi

echo "docker-compose.yml created."