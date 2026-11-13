# frozen_string_literal: true

# Helper for retrieving nested I18n Hash subtrees (such as `dashboard.uppy`
# or `dashboard.js`) deep-merged over the `:en` base catalog so partially
# translated regional locales never drop untranslated nested keys.
module I18nSubtreeHelper
  def i18n_deep_subtree(scope, locale: I18n.locale)
    chain = if I18n.respond_to?(:fallbacks) && I18n.fallbacks
              (Array(I18n.fallbacks[locale]) + [:en]).uniq.reverse
            else
              [:en, locale.to_sym].uniq
            end

    chain.each_with_object({}) do |loc, merged|
      subtree = fetch_locale_hash(scope, loc)
      merged.deep_merge!(deep_stringify_hash(subtree)) unless subtree.empty?
    end
  end

  private

  def fetch_locale_hash(scope, loc)
    val = I18n.t(scope, locale: loc, fallback: false, raise: true)
    val.is_a?(Hash) ? val : {}
  rescue I18n::MissingTranslationData, I18n::InvalidLocale
    {}
  end

  def deep_stringify_hash(hash)
    hash.each_with_object({}) do |(key, value), out|
      out[key.to_s] = value.is_a?(Hash) ? deep_stringify_hash(value) : value
    end
  end
end
