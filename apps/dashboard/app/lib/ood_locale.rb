# frozen_string_literal: true

# Utilities for normalizing Open OnDemand locale identifiers between Rails I18n
# symbols (which may use POSIX underscores, e.g. :ja_JP) and RFC 5646 / BCP 47
# language tags (e.g. "ja-JP", "fr-CA") required by HTML `lang`, HTTP headers,
# cookies, and browser `Intl` APIs, as well as resolving the per-request locale.
module OodLocale
  COOKIE_KEY = :ood_locale

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

  # Locales in `I18n.available_locales` that provide `dashboard` translations
  # (excluding gem-only locales such as `dotiw`'s `:de`).
  def dashboard_locales
    I18n.available_locales.select do |loc|
      I18n.t('dashboard', locale: loc, fallback: false, raise: true).is_a?(Hash)
    rescue I18n::MissingTranslationData, I18n::InvalidLocale
      false
    end
  end

  # Site default locale normalized against available dashboard locales.
  def default_locale(allowed: dashboard_locales)
    normalize(::Configuration.locale, allowed: allowed) ||
      normalize(I18n.default_locale, allowed: allowed) ||
      :en
  end

  # Admin-enabled locales filtered to those with dashboard translations.
  def supported_locales
    allowed = dashboard_locales
    configured = Array(::Configuration.supported_locales).filter_map do |entry|
      normalize(entry, allowed: allowed)
    end.uniq

    configured.empty? ? [default_locale(allowed: allowed)] : configured
  end

  # Resolve the active locale for a request using the shared OOD contract:
  # 1. Saved user preference (~/.config/ondemand/settings.yml)
  # 2. Same-origin ood_locale cookie
  # 3. Browser Accept-Language negotiation (when >1 locale is enabled)
  # 4. Site default (Configuration.locale / I18n.default_locale)
  def resolve(user_locale: nil, cookie_locale: nil, accept_language: nil)
    supported = supported_locales

    candidate = normalize(user_locale, allowed: supported)
    candidate ||= normalize(cookie_locale, allowed: supported)
    candidate ||= negotiate_accept_language(accept_language, supported: supported) if supported.size > 1
    candidate || default_locale(allowed: dashboard_locales)
  end

  # Cookie hash publishing the active BCP 47 locale tag across same-origin OOD apps.
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

  # Native display name for `locale` without falling back to English.
  def locale_name(locale)
    I18n.t('dashboard.locale_name', locale: locale, fallback: false, raise: true)
  rescue I18n::MissingTranslationData, I18n::InvalidLocale
    to_bcp47(locale)
  end

  # Compact uppercase abbreviation for navbar / compact UI selectors
  # (e.g. :en -> "EN", :'en-CA' -> "EN-CA", :'fr-CA' -> "FR-CA", :ja_JP -> "JA-JP").
  def short_label(locale = I18n.locale)
    to_bcp47(locale).upcase
  end

  # Selectable locale tuples `[native_name, locale_code, bcp47_tag]`.
  def options_for_select
    supported_locales.map do |loc|
      [locale_name(loc), loc.to_s, to_bcp47(loc)]
    end
  end

  # Compact selectable locale tuples `[short_label, native_name, locale_code, bcp47_tag]`.
  def short_options_for_select
    supported_locales.map do |loc|
      [short_label(loc), locale_name(loc), loc.to_s, to_bcp47(loc)]
    end
  end
end
