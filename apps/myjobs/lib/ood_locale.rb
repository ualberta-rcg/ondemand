# frozen_string_literal: true

# Locale normalization, fallback discovery, and shared OOD per-request locale
# resolution for Job Composer (apps/myjobs).
module OodLocale
  COOKIE_KEY = :ood_locale

  module_function

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

  def normalize(raw, allowed: I18n.available_locales)
    return nil if raw.nil?

    cleaned = raw.to_s.strip
    return nil if cleaned.empty?

    stem = File.basename(cleaned, '.*')
    return nil if stem.empty?

    target = stem.tr('_', '-').downcase
    Array(allowed).find { |loc| loc.to_s.tr('_', '-').downcase == target }&.to_sym
  end

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

  def jobcomposer_locales
    locales = I18n.available_locales.select do |loc|
      I18n.t('jobcomposer', locale: loc, fallback: false, raise: true).is_a?(Hash)
    rescue I18n::MissingTranslationData, I18n::InvalidLocale
      false
    end
    locales.empty? ? [:en] : locales
  end

  def default_locale(allowed: jobcomposer_locales)
    normalize(::Configuration.locale, allowed: allowed) ||
      normalize(I18n.default_locale, allowed: allowed) ||
      :en
  end

  def supported_locales
    allowed = jobcomposer_locales
    configured = Array(::Configuration.supported_locales).filter_map do |entry|
      normalize(entry, allowed: allowed)
    end.uniq

    configured.empty? ? allowed : configured
  end

  def resolve(user_locale: nil, cookie_locale: nil, accept_language: nil)
    supported = supported_locales

    candidate = normalize(user_locale, allowed: supported)
    candidate ||= normalize(cookie_locale, allowed: supported)
    candidate ||= negotiate_accept_language(accept_language, supported: supported) if supported.size > 1
    candidate || default_locale(allowed: jobcomposer_locales)
  end

  def cookie_options(locale, ssl: false, persistent: false)
    opts = {
      value:     to_bcp47(locale),
      path:      '/',
      same_site: :lax,
      secure:    ssl
    }
    opts[:expires] = 1.year.from_now if persistent
    opts
  end
end
