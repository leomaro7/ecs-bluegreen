FROM public.ecr.aws/nginx/nginx:stable-alpine
ARG APP_VERSION=dev
RUN echo "<h1>ecs-bluegreen</h1><p>version: ${APP_VERSION}</p>" > /usr/share/nginx/html/index.html
