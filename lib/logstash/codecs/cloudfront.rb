# encoding: utf-8
require "logstash/codecs/base"
require "logstash/codecs/plain"
require "logstash/json"

# This codec will read cloudfront encoded content
class LogStash::Codecs::Cloudfront < LogStash::Codecs::Base
  config_name "cloudfront"


  # The character encoding used in this codec. Examples include "UTF-8" and
  # "CP1252"
  #
  # JSON requires valid UTF-8 strings, but in some cases, software that
  # emits JSON does so in another encoding (nxlog, for example). In
  # weird cases like this, you can set the charset setting to the
  # actual encoding of the text and logstash will convert it for you.
  #
  # For nxlog users, you'll want to set this to "CP1252"
  config :charset, :validate => ::Encoding.name_list, :default => "UTF-8"

  public
  def initialize(params={})
    super(params)
    @converter = LogStash::Util::Charset.new(@charset)
    @converter.logger = @logger
  end

  public
  def decode(data)
    begin
      data = StringIO.new(data) if data.is_a?(String)
      @stream = Zlib::GzipReader.new(data)
    rescue Zlib::GzipFile::Error => e
      # Just try and parse the plain string
      @stream = data
      @stream.rewind
    rescue Zlib::Error => e
      file = data.is_a?(String) ? data : data.class

      @logger.error("Cloudfront codec: We cannot uncompress the gzip file", :filename => file)
      raise e
    end

    metadata = extract_metadata(@stream)

    @logger.debug("Cloudfront: Extracting metadata", :metadata => metadata)

    @stream.each_line do |line|
      yield create_event(line, metadata)
    end
  end # def decode

  public
  def create_event(line, metadata)
    event = LogStash::Event.new("message" => @converter.convert(line))
    event.set("cloudfront_version", metadata["cloudfront_version"])
    event.set("cloudfront_fields", metadata["cloudfront_fields"])
    event
  end


  def extract_metadata(io)
    version = extract_version(io.gets)
    fields = extract_fields(io.gets)

    return {
      "cloudfront_version" => version,
      "cloudfront_fields" => fields,
    }
  end


  def extract_version(line)
    if /^#Version: .+/.match(line)
      junk, version = line.strip().split(/#Version: (.+)/)
      version unless version.nil?
    end
  end


  def extract_fields(line)
    if /^#Fields: .+/.match(line)
      junk, format = line.strip().split(/#Fields: (.+)/)
      format unless format.nil?
    end
  end
end # class LogStash::Codecs::Cloudfront
