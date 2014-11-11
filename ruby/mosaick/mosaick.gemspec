Gem::Specification.new do |s|
  s.name = %q{mosaick}
  s.author = "Jim Bumgardner"
  s.email = "dad@krazydad.com"
  s.description = "Builds photomosaics. Relies on RMagick"
  s.homepage = "http://krazydad.com/blog/"
  s.version = "0.0.1"
  s.date = %q{2012-02-22}
  s.summary = %q{mosaick can construct photomosaics, and is based on code originally written for the book Flickr Hacks by Jim Bumgardner}
  s.files = [
    "lib/mosaick.rb"
  ]
  s.require_paths = ["lib"]
  s.add_runtime_dependency "rmagick", [">= 2.0.0"]
end