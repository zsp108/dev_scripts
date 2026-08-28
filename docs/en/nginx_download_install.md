# nginx_download_install.sh Usage Guide

## Introduction
This is a highly practical script for quickly setting up an Nginx-based file download site (static file server). It automatically enables Nginx's directory indexing feature (autoindex), allowing users to visually browse and download files in a directory via their browser.

## Usage Examples

### 1. Default Installation
Uses default configurations (typically exposing `/data/downloads` on port 80):
```bash
sudo ./scripts/nginx_download_install.sh
```

### 2. Custom Root Directory
If you want to expose files in a different directory:
```bash
sudo ./scripts/nginx_download_install.sh /var/www/html/share
```

### 3. Custom Port and Directory using Long Flags
```bash
sudo ./scripts/nginx_download_install.sh --root /home/share --port 8080
```

