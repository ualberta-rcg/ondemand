# frozen_string_literal: true

# Setup locales by adding to the locale path, setting the default and setting fallbacks

extra_locales = Pathname.new(::Configuration.locales_root.to_s).join('*.{yml,rb}')
base_locales = Rails.application.config.root.join('config', 'locales', '*.{yml,rb}')

Rails.application.config.i18n.load_path += Dir[base_locales, extra_locales]
Rails.application.config.i18n.default_locale = ::Configuration.locale
Rails.application.config.i18n.fallbacks = [:en]

Rails.application.config.after_initialize do
  I18n.backend.load_translations if I18n.backend.respond_to?(:load_translations)

  I18n.available_locales.dup.each do |loc|
    next unless loc.to_s.include?('_')

    bcp_sym = OodLocale.to_bcp47(loc).to_sym
    I18n.backend.store_translations(bcp_sym, { ood_locale_alias: loc.to_s }) unless I18n.available_locales.include?(bcp_sym)
    I18n.fallbacks.map(bcp_sym => [loc, :en], loc => [bcp_sym, :en]) if I18n.respond_to?(:fallbacks)
  end

  normalized_default = OodLocale.normalize(::Configuration.locale)
  I18n.default_locale = normalized_default if normalized_default
end
