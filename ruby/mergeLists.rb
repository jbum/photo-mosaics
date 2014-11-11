require 'json'

gphotos = []
photoids = {}

ARGV.each { |ifname|
  ifname += ".json" if not ifname =~ /\.\w+$/
	photos = JSON.parse(File.read(ifname))
  photos.each { |photo|
    gphotos.push(photo) if not photoids.has_key?(photo['id'])
    photoids[photo['id']] = 1
  }
}
puts JSON.pretty_generate(gphotos)

