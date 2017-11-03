#!/usr/bin/env ruby
require 'rubygems'
require 'liquid'
require "base64"
require 'zip'
require 'nokogiri'

WIDTH = 150
UNKNOWN_ICON = "/9j/4AAQSkZJRgABAQEAYABgAAD//gA+Q1JFQVRPUjogZ2QtanBlZyB2MS4wICh1c2luZyBJSkcgSlBFRyB2ODApLCBkZWZhdWx0IHF1YWxpdHkK/9sAQwAIBgYHBgUIBwcHCQkICgwUDQwLCwwZEhMPFB0aHx4dGhwcICQuJyAiLCMcHCg3KSwwMTQ0NB8nOT04MjwuMzQy/9sAQwEJCQkMCwwYDQ0YMiEcITIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy/8AAEQgAlgCWAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/aAAwDAQACEQMRAD8A9/ooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA//9k="

def epub_extract_cover(path)
  zip = Zip::File.open(path)
  root = Nokogiri::XML(zip.read('META-INF/container.xml'))
  root.remove_namespaces!
  metadata_path = root.css('container rootfiles rootfile:first-child').attribute('full-path').content
  metadata = Nokogiri::XML(zip.read(metadata_path))

  cover_id = (metadata.css('meta[name=cover]').attr('content').value rescue nil)
  manifest = metadata.css('manifest')

  cover_item = (manifest.css("item[id = \"#{cover_id}\"]").first rescue nil) ||
                   (manifest.css("item[properties = \"#{cover_id}\"]").first rescue nil) ||
                   (manifest.css("item[property = \"#{cover_id}\"]").first rescue nil) ||
                   (manifest.css("item[id = img-bookcover-jpeg]").first rescue nil) ||
                   (manifest.css("item[media-type=\"image/jpeg\"]").first rescue nil) ||
                   (manifest.css("item[media-type=\"image/png\"]").first rescue nil)
  
  cover_path = cover_item.attr('href')
  dir = File.dirname(metadata_path)
  path = dir == '.' ? cover_path : File.join(dir, cover_path)
  zip.read(path)
end

def epub_extract_resized_cover(path)
  begin
    cover = epub_extract_cover(path)
    IO.popen("gm convert - -resize #{WIDTH}x jpeg:- 2>/dev/null", "r+") do |convert|
      convert.write(cover)
      convert.close_write
      convert.read
    end
  rescue
    nil
  end
end

dir = ARGV[0] || '.'

files = Dir.entries(dir).select { |file|
  file !~ /^\./ && file != "index.html"
}.map { |file|
  full_path = File.expand_path(file, dir)
  puts full_path
  
  if file =~ /.pdf$/i then
    cover = IO.popen(["gm", "convert", full_path + "[0]", "-resize", "#{WIDTH}x", "-quality", "50", "jpeg:-"]).read
  elsif file =~ /.epub$/i then
    cover = epub_extract_resized_cover(full_path)
  end
  
  cover &&= Base64.strict_encode64(cover)
  
  {
   'name' => file,
   'cover' => cover && cover.start_with?("/9j/") ? cover : UNKNOWN_ICON
  }
}

template = Liquid::Template.parse(File.read('template.html'))
index_path = File.expand_path('index.html', dir)
index_html = template.render('files' => files, 'directory' => File.basename(dir))
File.write(index_path, index_html)

