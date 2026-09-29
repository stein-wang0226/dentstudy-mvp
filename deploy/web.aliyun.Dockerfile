FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /src
COPY mobile/pubspec.yaml mobile/pubspec.lock ./mobile/
RUN cd mobile && flutter pub get
COPY mobile ./mobile
RUN cd mobile && flutter build web --release \
    --dart-define=API_URL=/api \
    --dart-define=QUESTION_BANK_ASSET=assets/all_questions.json

FROM nginx:1.27-alpine
COPY deploy/nginx.aliyun.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/mobile/build/web /usr/share/nginx/html
EXPOSE 80
