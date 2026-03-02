#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'rexml/document'
require 'rexml/formatters/pretty'
require 'time'

options = {
  app_name: 'Dicta',
  channel_link: 'https://jahrix.github.io/Dicta/appcast.xml',
  description: 'Latest releases for Dicta',
  language: 'en'
}

OptionParser.new do |parser|
  parser.on('--file PATH') { |value| options[:file] = value }
  parser.on('--version VERSION') { |value| options[:version] = value.sub(/\Av/, '') }
  parser.on('--tag TAG') { |value| options[:tag] = value }
  parser.on('--download-url URL') { |value| options[:download_url] = value }
  parser.on('--release-url URL') { |value| options[:release_url] = value }
  parser.on('--signature VALUE') { |value| options[:signature] = value }
  parser.on('--length BYTES') { |value| options[:length] = value }
  parser.on('--pub-date RFC2822') { |value| options[:pub_date] = value }
  parser.on('--app-name NAME') { |value| options[:app_name] = value }
  parser.on('--channel-link URL') { |value| options[:channel_link] = value }
  parser.on('--description TEXT') { |value| options[:description] = value }
end.parse!

required = %i[file version tag download_url release_url signature length]
missing = required.select { |key| options[key].nil? || options[key].to_s.strip.empty? }
abort("Missing required options: #{missing.join(', ')}") unless missing.empty?

pub_date = options[:pub_date] || Time.now.utc.rfc2822

document =
  if File.exist?(options[:file]) && !File.zero?(options[:file])
    REXML::Document.new(File.read(options[:file]))
  else
    REXML::Document.new
  end

rss = document.root
unless rss
  rss = document.add_element('rss', {
    'version' => '2.0',
    'xmlns:sparkle' => 'http://www.andymatuschak.org/xml-namespaces/sparkle',
    'xmlns:dc' => 'http://purl.org/dc/elements/1.1/',
    'xmlns:atom' => 'http://www.w3.org/2005/Atom'
  })
end

channel = rss.elements['channel'] || rss.add_element('channel')

def upsert_text(parent, name, value)
  element = parent.elements[name] || parent.add_element(name)
  element.text = value
end

upsert_text(channel, 'title', "#{options[:app_name]} Updates")
upsert_text(channel, 'link', options[:channel_link])
upsert_text(channel, 'description', options[:description])
upsert_text(channel, 'language', options[:language])
upsert_text(channel, 'lastBuildDate', pub_date)

atom_link = channel.elements['atom:link'] || channel.add_element('atom:link')
atom_link.add_attributes(
  'href' => options[:channel_link],
  'rel' => 'self',
  'type' => 'application/rss+xml'
)

channel.get_elements('item').each do |item|
  enclosure = item.elements['enclosure']
  next unless enclosure

  short_version = enclosure.attributes['sparkle:shortVersionString']
  item_url = enclosure.attributes['url']
  next unless short_version == options[:version] || item_url == options[:download_url]

  channel.delete_element(item)
end

item = REXML::Element.new('item')
item.add_element('title').text = "#{options[:app_name]} #{options[:tag]}"
item.add_element('pubDate').text = pub_date
item.add_element('link').text = options[:release_url]
item.add_element('guid', { 'isPermaLink' => 'false' }).text = "#{options[:app_name]}-#{options[:tag]}"
item.add_element('description').text = "Release #{options[:version]}"

enclosure = item.add_element('enclosure')
enclosure.add_attributes(
  'url' => options[:download_url],
  'type' => 'application/octet-stream',
  'length' => options[:length],
  'sparkle:version' => options[:version],
  'sparkle:shortVersionString' => options[:version],
  'sparkle:edSignature' => options[:signature]
)

first_existing_item = channel.elements['item']
if first_existing_item
  channel.insert_before(first_existing_item, item)
else
  channel.add_element(item)
end

formatter = REXML::Formatters::Pretty.new(2)
formatter.compact = true
File.open(options[:file], 'w') do |file|
  formatter.write(document, file)
  file.write("\n")
end
