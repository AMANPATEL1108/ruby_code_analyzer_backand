port ENV.fetch("PORT") { 4567 }
environment ENV.fetch("RACK_ENV") { "development" }
workers 1
threads 1, 6
preload_app!
