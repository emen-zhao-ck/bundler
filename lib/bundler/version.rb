module Bundler
  # We're doing this because we might write tests that deal
  # with other versions of bundler and we are unsure how to
  # handle this better.
  VERSION = "1.99.0.dev" unless defined?(::Bundler::VERSION)
end
