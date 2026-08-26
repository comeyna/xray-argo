# Argo 固定隧道设置要点说明

进入 cloudflare 首页 点击 Zero Trust 再次点击 网络 连接器

创建隧道  - cloudflare - Ciallo - cloudflared.exe service install eyJhIjoiZTZiOGQwZmQ2ZGNiMGEyMGM0MjFkZmQzMDA1MTYwZWEiLCJ0IjoiMWZkYTZmMmUtMjA4NS00MWIwLWJjMzUtZDRmZGQ4MWJiYTJjIiwicyI6Ik9UVmpaRGd3TVRVdE5HUTVZUzAwWXpFNUxXSTNOVE10WWpoaVkyUmpNVFZtTUdNeSJ2（注意保存） - 下一步 - ciallo.orange.top http://localhost:2026 


```bash
docker build -t novre/xray-argo:v1.1-26826 .
docker push novre/xray-argo:v1.1-26826
```
