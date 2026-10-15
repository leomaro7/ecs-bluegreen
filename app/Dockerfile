# 非 root (UID 101) で 8080 を listen する公式イメージ
FROM public.ecr.aws/nginx/nginx-unprivileged:stable-alpine
ARG APP_VERSION=dev
USER root
RUN echo "<h1>ecs-bluegreen (green release)</h1><p>version: ${APP_VERSION}</p>" > /usr/share/nginx/html/index.html
USER 101
# readonlyRootFilesystem でも書き込めるよう、/tmp をタスクのボリュームにする。
# VOLUME を宣言すると、ECS がイメージ内の /tmp の権限(1777)をボリュームに引き継ぐ
VOLUME ["/tmp"]
