# frozen_string_literal: true

require 'set'
require 'yaml'

# Resolves localized values from scalar strings, inline locale hashes
# (e.g. `{ en: 'Desktop', 'fr-CA': 'Bureau' }`), per-app `locales/<locale>.yml`
# catalogs, and standard Open OnDemand category slugs (`dashboard.categories.*`).
module LocalizedValue
  # Valid ISO 639-1 (2-letter) and common ISO 639-2/3 (3-letter) primary language subtags.
  # Restricting primary subtags prevents false positives on config hashes like `{ min: 1, max: 2 }`.
  VALID_PRIMARY_LANGS = Set.new(%w[
    aa ab af ak am an ar as av ay az ba be bg bh bi bm bn bo br bs ca ce ch co cr cs cu cv cy
    da de dv dz ee el en eo es et eu fa ff fi fj fo fr fy ga gd gl gn gu gv ha he hi ho hr ht
    hu hy hz ia id ie ig ii ik io is it iu ja jv ka kg ki kj kk kl km kn ko kr ks ku kv kw ky
    la lb lg li ln lo lt lu lv mg mh mi mk ml mn mr ms mt my na nb nd ne ng nl nn no nr nv ny
    oc oj om or os pa pi pl ps pt qu rm rn ro ru rw sa sc sd se sg si sk sl sm sn so sq sr ss
    st su sv sw ta te tg th ti tk tl tn to tr ts tt tw ty ug uk ur uz ve vi vo wa wo xh yi yo
    za zh zu
    ast chr cre dsb fil fur gsw haw hsb iku kab kok mic moh nds nso oji sah sco smn tzm yue zgh
  ]).freeze

  SUBTAG_REGEX = /\A(?:[a-zA-Z]{4}|[a-zA-Z]{2}|[0-9]{3}|[a-zA-Z0-9]{5,8})\z/

  # Explicit i18n-tasks usage hints for dynamic `dashboard.categories.<slug>` lookups:
  # i18n-tasks-use t('dashboard.categories.apps')
  # i18n-tasks-use t('dashboard.categories.clusters')
  # i18n-tasks-use t('dashboard.categories.desktops')
  # i18n-tasks-use t('dashboard.categories.external_apps')
  # i18n-tasks-use t('dashboard.categories.files')
  # i18n-tasks-use t('dashboard.categories.gateway_apps')
  # i18n-tasks-use t('dashboard.categories.guis')
  # i18n-tasks-use t('dashboard.categories.interactive_apps')
  # i18n-tasks-use t('dashboard.categories.jobs')
  # i18n-tasks-use t('dashboard.categories.servers')
  # i18n-tasks-use t('dashboard.categories.virtual_desktop_interface')

  module_function

  # True if `tag` is a syntactically valid BCP 47 / POSIX locale tag with a known primary language.
  def valid_locale_tag?(tag)
    raw = tag.to_s.strip
    return false if raw.empty?

    parts = raw.split(/[-_]/)
    return false unless VALID_PRIMARY_LANGS.include?(parts.first.downcase)

    parts[1..].all? { |sub| sub.match?(SUBTAG_REGEX) }
  end

  # True when `value` is a non-empty Hash whose keys are valid locale tags
  # and whose values are scalar (String, Symbol, Numeric, nil).
  def locale_hash?(value)
    return false unless value.is_a?(Hash) && !value.empty?

    value.all? do |k, v|
      valid_locale_tag?(k) && (v.nil? || v.is_a?(String) || v.is_a?(Symbol) || v.is_a?(Numeric))
    end
  end

  # Normalize a locale tag to lowercase BCP 47 (`fr_CA` -> `fr-ca`) for matching.
  def canonical_tag(tag)
    tag.to_s.strip.tr('_', '-').downcase
  end

  # Resolve a value that may be nil, a scalar, or a locale Hash.
  # Returns nil if value is nil (or an all-nil locale Hash); otherwise returns a String.
  def resolve_optional(value, locale: I18n.locale)
    return nil if value.nil?

    if locale_hash?(value)
      by_canonical = {}
      value.each do |k, v|
        next if v.nil?

        by_canonical[canonical_tag(k)] ||= v.to_s
      end
      return nil if by_canonical.empty?

      loc = canonical_tag(locale)
      loc_primary = loc.split('-').first.to_s
      def_loc = canonical_tag(I18n.default_locale)
      def_primary = def_loc.split('-').first.to_s

      [loc, loc_primary].reject(&:empty?).uniq.each do |cand|
        return by_canonical[cand] if by_canonical.key?(cand)
      end

      if !loc_primary.empty?
        regional_match = by_canonical.find { |k, _| k.start_with?("#{loc_primary}-") }
        return regional_match.last if regional_match
      end

      [def_loc, def_primary, 'en'].reject(&:empty?).uniq.each do |cand|
        return by_canonical[cand] if by_canonical.key?(cand)
      end

      by_canonical.values.first
    else
      value.to_s
    end
  end

  # Like `resolve_optional`, returning `default` (default `''`) when unresolved/nil.
  def resolve(value, locale: I18n.locale, default: '')
    resolved = resolve_optional(value, locale: locale)
    resolved.nil? ? default : resolved
  end

  # Resolve localized fields (`:title`, `:sub_caption`, etc.) inside a `tile` Hash.
  def resolve_tile_hash(tile_hash, locale: I18n.locale)
    return {} unless tile_hash.respond_to?(:to_h)

    resolved = tile_hash.to_h.deep_symbolize_keys.transform_values do |v|
      locale_hash?(v) ? resolve(v, locale: locale) : v
    end
    resolved.respond_to?(:with_indifferent_access) ? resolved.with_indifferent_access : resolved
  end

  # Load and fallback-merge per-app translations from `<app_root>/locales/*.{yml,yaml}`.
  # Supports both Rails-style root locale keys (`fr-CA: { manifest: ..., form: ... }`)
  # and flat per-file hashes (`manifest: ..., form: ...`).
  # Returns `{}` immediately when `<app_root>/locales` does not exist.
  def app_translations(app_root, locale: I18n.locale)
    return {} if app_root.nil?

    locales_dir = Pathname.new(app_root).join('locales')
    return {} unless locales_dir.directory? && locales_dir.readable? && locales_dir.executable?

    files_by_tag = {}
    Pathname.glob(locales_dir.join('*.{yml,yaml}')).sort.each do |file|
      next unless file.file? && file.readable?

      stem = file.basename(file.extname).to_s
      next unless valid_locale_tag?(stem)

      files_by_tag[canonical_tag(stem)] ||= file
    end
    return {} if files_by_tag.empty?

    loc = canonical_tag(locale)
    loc_primary = loc.split('-').first.to_s
    def_loc = canonical_tag(I18n.default_locale)
    def_primary = def_loc.split('-').first.to_s

    chain = ['en', def_primary, def_loc, loc_primary]
    if !loc_primary.empty? && !files_by_tag.key?(loc) && !files_by_tag.key?(loc_primary)
      regional_tag = files_by_tag.keys.find { |k| k.start_with?("#{loc_primary}-") }
      chain << regional_tag if regional_tag
    end
    chain << loc

    merged = {}
    chain.compact.reject(&:empty?).uniq.each do |tag|
      file = files_by_tag[tag]
      next unless file

      parsed = load_locale_yaml(file, tag)
      merged = merged.deep_merge(parsed) unless parsed.empty?
    end
    merged
  end

  def load_locale_yaml(file, expected_canonical_tag)
    raw = YAML.safe_load(file.read)
    return {} unless raw.is_a?(Hash) && !raw.empty?

    if raw.size == 1
      only_key, only_val = raw.first
      if valid_locale_tag?(only_key) && canonical_tag(only_key) == expected_canonical_tag && only_val.is_a?(Hash)
        return only_val.deep_symbolize_keys
      end
    end

    raw.deep_symbolize_keys
  rescue StandardError => e
    Rails.logger.warn("Cannot load app locale file #{file}: #{e.class}: #{e.message}") if defined?(Rails) && Rails.logger
    {}
  end

  # Translate standard OOD category/subcategory names via `dashboard.categories.<slug>`,
  # falling back cleanly to the resolved category string for custom site categories.
  def translate_category(raw_title, locale: I18n.locale)
    return nil if raw_title.nil?

    resolved = resolve(raw_title, locale: locale)
    return resolved if resolved.empty?

    slug = resolved.strip.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_|_\z/, '')
    return resolved if slug.empty?

    translated = I18n.t("dashboard.categories.#{slug}", locale: locale, default: nil)
    translated.is_a?(String) && !translated.empty? ? translated : resolved
  end
end
