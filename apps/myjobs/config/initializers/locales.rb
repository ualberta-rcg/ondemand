# frozen_string_literal: true

# load the fallbacks backend module
require 'i18n/backend/fallbacks'
require_relative '../../lib/ood_locale'

# clear the Railtie config to allow our config_root to have higher precedence
Rails.application.config.i18n = {}

# replace the backend to allow missing translations to default to OOD-supplied ones
I18n::Backend::Simple.include(I18n::Backend::Fallbacks)

# load the local translations and any translations from config_root
I18n.load_path += Dir[Rails.application.config.root.join('config', 'locales', '*.{yml,rb}'),
                      ::Configuration.locales_root.join('*.{yml,rb}')]
I18n.default_locale = ::Configuration.locale
I18n.fallbacks = I18n::Locale::Fallbacks.new([:en])

Rails.application.config.after_initialize do
  I18n.backend.load_translations if I18n.backend.respond_to?(:load_translations)

  I18n.available_locales.dup.each do |loc|
    I18n.fallbacks.map(loc => [:en]) if loc != :en
    next unless loc.to_s.include?('_')

    bcp_sym = OodLocale.to_bcp47(loc).to_sym
    I18n.backend.store_translations(bcp_sym, { ood_locale_alias: loc.to_s }) unless I18n.available_locales.include?(bcp_sym)
    I18n.fallbacks.map(bcp_sym => [loc, :en], loc => [bcp_sym, :en])
  end

  normalized_default = OodLocale.normalize(::Configuration.locale)
  I18n.default_locale = normalized_default if normalized_default
end
