# 範例 Dockerfile：以 nginx 提供靜態頁面
# 推送到 VM 本機 registry 後，K3s 以 localhost:5000/my-app:<sha> 部署

FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80
