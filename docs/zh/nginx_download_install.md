# nginx_download_install.sh 使用说明

## 脚本简介
这是一个非常实用的脚本，用于快速搭建基于 Nginx 的文件下载站点（静态文件服务器）。它会自动开启 Nginx 的目录索引功能（autoindex），以便用户在浏览器中能够直观地浏览和下载目录中的文件。

## 使用示例

### 1. 默认安装
使用默认配置（通常将 `/data/downloads` 暴露在 80 端口）：
```bash
sudo ./scripts/nginx_download_install.sh
```

### 2. 自定义根目录
如果您希望公开另外一个目录下的文件：
```bash
sudo ./scripts/nginx_download_install.sh /var/www/html/share
```

### 3. 使用长参数自定义端口和目录
```bash
sudo ./scripts/nginx_download_install.sh --root /home/share --port 8080
```

