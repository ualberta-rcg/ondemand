# frozen_string_literal: true

require 'open-uri'

# The Message of the Day (MOTD) file.
class MotdFile
  attr_reader :motd_path

  # Initialize the Motd Controller object based on the current user and locale.
  #
  # @param [String] path The path to the motd file or directory as a URI
  # @param [Symbol, String] locale Locale used to resolve per-language MOTD siblings
  def initialize(path = self.class.configured_motd_path, locale: I18n.locale)
    @locale = locale
    @motd_path = path.present? ? self.class.resolve_localized_path(path, locale: locale) : path
    @content = @motd_path.present? ? load(@motd_path) : nil
  end

  # Configured MOTD path supporting optional locale hashes in `ondemand.d` (`motd_path:`).
  def self.configured_motd_path(locale: I18n.locale)
    if defined?(::Configuration) && ::Configuration.respond_to?(:config)
      cfg_path = ::Configuration.config[:motd_path]
      return LocalizedValue.resolve(cfg_path, locale: locale) if LocalizedValue.locale_hash?(cfg_path)
    end
    ENV['MOTD_PATH']
  end

  # Canonical BCP 47 tag for MOTD sibling file naming (e.g. :fr_ca -> "fr-CA").
  def self.bcp47_tag(locale)
    parts = locale.to_s.strip.tr('_', '-').split('-').reject(&:empty?)
    return 'en' if parts.empty?

    parts.each_with_index.map do |sub, idx|
      if idx.zero?
        sub.downcase
      elsif sub.length == 4 && sub.match?(/\A[a-zA-Z]{4}\z/)
        sub.capitalize
      elsif (sub.length == 2 && sub.match?(/\A[a-zA-Z]{2}\z/)) || sub.match?(/\A\d{3}\z/)
        sub.upcase
      else
        sub
      end
    end.join('-')
  end

  # Target path where a per-language sibling MOTD file should be written on disk
  # (e.g. `/etc/ood/config/ondemand.d/motd` -> `/etc/ood/config/ondemand.d/motd.fr-CA`,
  # `/etc/ood/motd.md` -> `/etc/ood/motd.fr-CA.md`, or `<dir>/` -> `<dir>/motd.fr-CA`).
  def self.localized_sibling_path(base_path, locale)
    tag = bcp47_tag(locale)
    return File.join(base_path, "motd.#{tag}") if File.directory?(base_path.to_s)

    dir  = File.dirname(base_path.to_s)
    base = File.basename(base_path.to_s)
    ext  = File.extname(base)

    if ext.present? && !LocalizedValue.valid_locale_tag?(ext.delete_prefix('.'))
      stem = base[0...-ext.length]
      File.join(dir, "#{stem}.#{tag}#{ext}")
    else
      File.join(dir, "#{base}.#{tag}")
    end
  end

  # Resolve a per-language MOTD file in the same directory (or MOTD directory)
  # before falling back cleanly to `base_path`.
  def self.resolve_localized_path(base_path, locale: I18n.locale)
    return base_path if base_path.blank?

    uri = URI.parse(base_path.to_s)
    return base_path unless uri.scheme.nil?

    bcp47   = bcp47_tag(locale)
    posix   = bcp47.tr('-', '_')
    lower   = bcp47.downcase
    primary = bcp47.split('-').first.to_s
    tags    = [bcp47, posix, lower, primary].reject(&:empty?).uniq

    if File.directory?(base_path)
      candidates = tags.flat_map do |t|
        [
          File.join(base_path, "motd.#{t}"),
          File.join(base_path, t),
          File.join(base_path, "motd.#{t}.md"),
          File.join(base_path, "#{t}.md")
        ]
      end
      hit = candidates.find { |c| File.file?(c) && File.readable?(c) }
      return hit if hit

      if primary.present?
        regional = Dir.glob(File.join(base_path, "{motd.,}#{primary}[-_]*")).sort.find do |c|
          File.file?(c) && File.readable?(c)
        end
        return regional if regional
      end

      fallback = %w[motd motd.md motd.txt en motd.en].map { |f| File.join(base_path, f) }.find do |c|
        File.file?(c) && File.readable?(c)
      end
      return fallback || base_path
    end

    dir  = File.dirname(base_path)
    base = File.basename(base_path)
    ext  = File.extname(base)
    has_fmt_ext = ext.present? && !LocalizedValue.valid_locale_tag?(ext.delete_prefix('.'))
    stem = has_fmt_ext ? base[0...-ext.length] : base

    candidates = tags.flat_map do |t|
      if has_fmt_ext
        [File.join(dir, "#{stem}.#{t}#{ext}"), File.join(dir, "#{base}.#{t}")]
      else
        [File.join(dir, "#{base}.#{t}")]
      end
    end

    hit = candidates.find { |c| File.file?(c) && File.readable?(c) }
    return hit if hit

    if primary.present?
      pattern = has_fmt_ext ? File.join(dir, "#{stem}.#{primary}[-_]*#{ext}") : File.join(dir, "#{base}.#{primary}[-_]*")
      regional = Dir.glob(pattern).sort.find do |c|
        !c.end_with?('.sha256') && File.file?(c) && File.readable?(c)
      end
      return regional if regional
    end

    base_path
  rescue URI::InvalidURIError
    base_path
  end

  # Checks the path URI to see if it can be opened
  #
  # Uses open-uri to check local or remote path for contents
  # @return [String] the motd raw content as string
  def content
    @content || ''
  end

  # A title for the message of the day.
  #   Set via `motd_title` config (supporting locale hashes) or environment variable 'MOTD_TITLE'
  #   Default: I18n.t('dashboard.motd_title')
  #
  # @return [String] a string used as the MOTD title
  def title
    if defined?(::Configuration) && ::Configuration.respond_to?(:config)
      cfg_title = ::Configuration.config[:motd_title]
      return LocalizedValue.resolve(cfg_title, locale: @locale || I18n.locale) if LocalizedValue.locale_hash?(cfg_title)
      return cfg_title.to_s if cfg_title.present? && ENV['MOTD_TITLE'].blank?
    end

    ENV['MOTD_TITLE'] || I18n.t('dashboard.motd_title', locale: @locale || I18n.locale)
  end

  # A factory method that returns an MotdFormatter object
  #
  # @return [Object, nil] an MotdFormatter object that responds to `:to_partial_path`
  #                       `nil` if a file does not exist at the path.
  def formatter
    return MotdFormatter::Default.new if motd_path.nil?
    return nil if motd_path.blank?
    return nil unless exist?

    @motd = case ENV['MOTD_FORMAT']
            when 'osc'
              MotdFormatter::Osc.new(self)
            when 'markdown'
              MotdFormatter::Markdown.new(self)
            when 'markdown_erb'
              MotdFormatter::MarkdownErb.new(self)
            when 'rss'
              MotdFormatter::Rss.new(self)
            when 'text_erb'
              MotdFormatter::PlaintextErb.new(self)
            else
              MotdFormatter::Plaintext.new(self)
            end
  end

  # Is the content present and not empty?
  #
  # @return [Boolean] true if content present
  def exist?
    !@content.nil?
  end

  private

  def load(motd_uri)
    return nil if motd_uri.blank?

    uri = URI.parse(motd_uri)

    case uri.scheme
    when 'http', 'https'
      uri.read
    when nil
      File.read(uri.to_s)
    else
      Rails.logger.warn("Unknown scheme for #{motd_uri}. No MOTD is loaded")
      nil
    end
  rescue Errno::ENOENT
    Rails.logger.warn "MOTD File is missing; it was expected at #{motd_uri}"
    nil
  rescue OpenURI::HTTPError
    Rails.logger.warn "MOTD File is not available at #{motd_uri}"
    nil
  rescue StandardError => e
    Rails.logger.warn "Error opening MOTD at #{motd_uri}\nException: #{e.message}"
    nil
  end
end
