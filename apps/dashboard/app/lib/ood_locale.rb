# frozen_string_literal: true

# Utilities for normalizing Open OnDemand locale identifiers between Rails I18n
# symbols (which may use POSIX underscores, e.g. :ja_JP) and RFC 5646 / BCP 47
# language tags (e.g. "ja-JP", "fr-CA") required by HTML `lang`, HTTP headers,
# cookies, and browser `Intl` APIs.
module OodLocale
  module_function

  # Convert a locale symbol or string into canonical BCP 47 subtag casing
  # (e.g. :ja_JP -> "ja-JP", "fr_ca" -> "fr-CA", "zh_hans_cn" -> "zh-Hans-CN").
  def to_bcp47(locale = I18n.locale)
    raw = locale.to_s.strip
    return 'en' if raw.empty?

    parts = raw.tr('_', '-').split('-').reject(&:empty?)
    return 'en' if parts.empty?

    parts.each_with_index.map do |subtag, idx|
      if idx.zero?
        subtag.downcase
      elsif subtag.length == 4 && subtag.match?(/\A[a-zA-Z]{4}\z/)
        subtag.capitalize
      elsif (subtag.length == 2 && subtag.match?(/\A[a-zA-Z]{2}\z/)) || subtag.match?(/\A\d{3}\z/)
        subtag.upcase
      else
        subtag
      end
    end.join('-')
  end

  # Match an arbitrary locale code or locale file path (e.g. "ja_JP", "ja-JP",
  # "fr_ca", "/etc/ood/config/locales/fr-CA.yml") against an allowed list of
  # locale symbols and return the canonical symbol from `allowed` (or nil).
  def normalize(raw, allowed: I18n.available_locales)
    return nil if raw.nil?

    cleaned = raw.to_s.strip
    return nil if cleaned.empty?

    stem = File.basename(cleaned, '.*')
    return nil if stem.empty?

    target = stem.tr('_', '-').downcase
    Array(allowed).find { |loc| loc.to_s.tr('_', '-').downcase == target }&.to_sym
  end

  # Negotiate an HTTP Accept-Language header (e.g. "fr-CA,fr;q=0.9,en;q=0.8")
  # against `supported` locale symbols using quality-ordered exact match first
  # and primary-language prefix match second within each quality tier.
  def negotiate_accept_language(header, supported:)
    allowed = Array(supported).map(&:to_sym)
    return nil if header.nil? || header.to_s.strip.empty? || allowed.empty?

    ranges = header.to_s.split(',').each_with_index.filter_map do |entry, idx|
      tag, *params = entry.strip.split(';')
      tag = tag.to_s.strip
      next if tag.empty? || tag == '*'

      q = 1.0
      params.each do |param|
        key, val = param.strip.split('=', 2)
        if key == 'q' && val
          parsed = Float(val, exception: false)
          q = parsed if parsed
        end
      end
      next unless q.positive? && q <= 1.0

      [tag.tr('_', '-').downcase, q, idx]
    end

    ranges.sort_by! { |_, q, idx| [-q, idx] }

    ranges.each do |tag, _, _|
      exact = allowed.find { |loc| loc.to_s.tr('_', '-').downcase == tag }
      return exact if exact

      primary = tag.split('-').first
      prefix = allowed.find { |loc| loc.to_s.tr('_', '-').downcase.split('-').first == primary }
      return prefix if prefix
    end

    nil
  end
end
