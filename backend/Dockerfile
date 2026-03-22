FROM ruby:3.3-slim

RUN apt-get update && apt-get install -y build-essential && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 4567

CMD ["rerun", "--force-polling", "--no-notify", "--", "ruby", "app.rb"]
