# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'yaml'

# Extracts, auto-generates, and synchronizes static multi-language files on disk for:
# 1. Dashboard YAML catalogs (`<locales_root>/<locale>.yml` when a configured locale is absent)
# 2. Open OnDemand apps (`<app_dir>/locales/<locale>.yml` from `manifest.yml`, `form.yml[.erb]`, and `view:`)
# 3. MOTD files (`motd.<locale>` alongside `MOTD_PATH` across all 6 OOD MOTD formats)
#
# Preserves existing human-edited translations and writes static files once to disk.
class AppLocaleSync
  NON_PROSE_OPTION_REGEX = /\A[\d.\-+:\s\/x×]+\z/i
  DESKTOP_PROPER_NAME_REGEX = /\A(?:GNOME|MATE|XFCE|KDE|LXDE|LXQt|Cinnamon|i3|IceWM|Fluxbox)\z/i
  SOFTWARE_VERSION_OPTION_REGEX = /\A[A-Za-z0-9_.+-]+\s+v?\d+(?:\.\d+){1,3}[A-Za-z0-9_.+-]*\z/
  PLURAL_KEYS = %w[zero one two few many other].freeze

  def initialize(converter: OodLocaleConverter.new)
    @converter = converter
  end

  # Ensure every locale in `locales` has a Dashboard YAML catalog, app locale files,
  # and localized MOTD on disk without overwriting existing files.
  def ensure_supported_locales!(
    locales: nil,
    apps_dirs: nil,
    motd_path: ENV['MOTD_PATH'],
    output_dir: nil
  )
    target_locales = resolve_target_locales(locales)
    summary = { dashboard: [], apps: [], motd: [] }
    return summary if target_locales.empty?

    summary[:dashboard] = ensure_dashboard_locales!(locales: target_locales, output_dir: output_dir)

    Array(apps_dirs || ['/var/www/ood/apps/sys']).each do |dir|
      root = Pathname.new(dir.to_s)
      next unless root.directory? && root.writable?

      app_dirs_under(root).each do |app_dir|
        missing = target_locales.select do |loc|
          tag = MotdFile.bcp47_tag(loc)
          !app_dir.join('locales', "#{tag}.yml").file?
        end
        next if missing.empty?

        summary[:apps].concat(sync_app(app_dir, locales: missing, overwrite: false))
      end
    end

    if motd_path.to_s.strip != '' && File.file?(motd_path.to_s) && File.writable?(File.dirname(motd_path.to_s))
      summary[:motd] = sync_motd(motd_path, locales: target_locales, force: false)
    end

    summary
  end

  # Auto-generate missing Dashboard `<locale>.yml` catalog files for configured locales
  # that do not yet exist in `OodLocale.dashboard_locales`.
  def ensure_dashboard_locales!(locales: nil, output_dir: nil, source_file: nil)
    target_locales = resolve_target_locales(locales)
    out_root = Pathname.new((output_dir || default_locales_output_dir).to_s)
    src_path = Pathname.new((source_file || default_dashboard_en_file).to_s)
    return [] unless src_path.file?

    existing_tags = if defined?(OodLocale)
                      OodLocale.dashboard_locales.map { |l| OodLocale.to_bcp47(l).downcase }
                    else
                      []
                    end

    written = []
    target_locales.each do |loc|
      tag = MotdFile.bcp47_tag(loc)
      next if tag.casecmp('en').zero?
      next if existing_tags.include?(tag.downcase)
      next if out_root.join("#{tag}.yml").file?

      generated = sync_dashboard_locale(tag, source_file: src_path, output_dir: out_root, overwrite: false)
      written << generated if generated
    end

    if written.any? && defined?(I18n)
      written.each { |f| I18n.load_path |= [f] }
      I18n.backend.reload!
    end
    written
  end

  # Generate or update a full Dashboard `<tag>.yml` catalog from `en.yml`.
  def sync_dashboard_locale(locale, source_file: nil, output_dir: nil, overwrite: false)
    tag = MotdFile.bcp47_tag(locale)
    return nil if tag.empty? || tag.casecmp('en').zero?

    src_path = Pathname.new((source_file || default_dashboard_en_file).to_s)
    out_root = Pathname.new((output_dir || default_locales_output_dir).to_s)
    return nil unless src_path.file?

    FileUtils.mkdir_p(out_root)
    out_file = out_root.join("#{tag}.yml")
    return out_file.to_s if out_file.file? && !overwrite
    return nil unless writable_target?(out_root)

    en_yaml = YAML.safe_load(src_path.read) || {}
    en_tree = en_yaml['en']
    return nil unless en_tree.is_a?(Hash)

    translated_tree = translate_yaml_tree(en_tree, target_locale: tag)
    if translated_tree['dashboard'].is_a?(Hash)
      translated_tree['dashboard']['locale_name'] = default_locale_display_name(tag, translated_tree['dashboard']['locale_name'])
    end

    atomic_write(out_file, YAML.dump(tag => deep_stringify(translated_tree)))
    out_file.to_s
  rescue StandardError => e
    Rails.logger.warn("AppLocaleSync#sync_dashboard_locale(#{locale}) skipped: #{e.class}: #{e.message}") if defined?(Rails) && Rails.logger
    nil
  end

  # Synchronize `<app_dir>/locales/<locale>.yml` for every app directory under `apps_root`.
  def sync_apps(apps_root, locales:, overwrite: false)
    app_dirs_under(Pathname.new(apps_root.to_s)).map do |app_dir|
      sync_app(app_dir, locales: locales, overwrite: overwrite)
    end
  end

  # Extract translatable strings from a single app's `manifest.yml`, `form.yml[.erb]`,
  # and `locales/en.yml` (`view:` keys) and write/merge `<app_dir>/locales/<locale>.yml`.
  def sync_app(app_dir, locales:, overwrite: false)
    dir = Pathname.new(app_dir.to_s)
    source = extract_app_source(dir)
    return [] if source.empty?

    locales_dir = dir.join('locales')
    FileUtils.mkdir_p(locales_dir)

    Array(locales).map do |loc|
      tag = MotdFile.bcp47_tag(loc)
      out_file = locales_dir.join("#{tag}.yml")
      existing = load_existing_catalog(out_file, tag)
      built = build_locale_catalog(source, locale: tag, existing: existing, overwrite: overwrite)

      atomic_write(out_file, YAML.dump(tag => deep_stringify(built)))
      out_file.to_s
    end
  end

  # Generate/update per-language `motd.<locale>` files alongside `motd_path`.
  def sync_motd(motd_path, locales:, format: ENV['MOTD_FORMAT'], force: false)
    return [] if motd_path.to_s.strip.empty?

    uri = URI.parse(motd_path.to_s)
    return [] unless uri.scheme.nil? && File.file?(motd_path.to_s)

    src_content = File.read(motd_path.to_s)
    src_sha = Digest::SHA256.hexdigest(src_content)

    Array(locales).filter_map do |loc|
      tag = MotdFile.bcp47_tag(loc)
      next if plain_english_locale?(tag)

      out_path = MotdFile.localized_sibling_path(motd_path.to_s, tag)
      sha_path = File.join(File.dirname(out_path), ".#{File.basename(out_path)}.sha256")

      if File.exist?(out_path) && !force
        next unless File.exist?(sha_path) && File.read(sha_path).strip != src_sha
      end

      next unless @converter&.respond_to?(:available_for?) ? @converter.available_for?(tag) : @converter&.available?

      converted = @converter.convert_motd(src_content, target_locale: tag, source_locale: 'en', format: format)
      next if converted.nil? || converted.empty?

      File.write(out_path, converted)
      File.write(sha_path, "#{src_sha}\n")
      out_path
    end
  end

  def skip_option_translation?(val_key, label)
    s = label.to_s.strip
    return true if s.empty? || s.match?(NON_PROSE_OPTION_REGEX)
    return true if s.match?(DESKTOP_PROPER_NAME_REGEX)
    return true if val_key.to_s.include?('/') && s.match?(/\d/)
    return true if s.match?(SOFTWARE_VERSION_OPTION_REGEX)

    false
  end

  def extract_app_source(app_dir)
    dir = Pathname.new(app_dir.to_s)
    data = extract_existing_en_source(dir)

    manifest_path = dir.join('manifest.yml')
    if manifest_path.file?
      raw_manifest = YAML.safe_load(manifest_path.read) || {}
      if raw_manifest.is_a?(Hash)
        manifest_out = {}
        %w[name description caption].each do |field|
          val = raw_manifest[field] || raw_manifest[field.to_sym]
          manifest_out[field] = val.to_s if val.is_a?(String) && !val.strip.empty?
        end
        data['manifest'] = (data['manifest'] || {}).merge(manifest_out) unless manifest_out.empty?
      end
    end

    raw_form = load_raw_form_config(dir)
    if raw_form.is_a?(Hash)
      form_out = (data['form'] || {}).dup
      %w[title description].each do |field|
        val = raw_form[field] || raw_form[field.to_sym]
        form_out[field] = val.to_s if val.is_a?(String) && !val.strip.empty?
      end

      attrs_raw = raw_form['attributes'] || raw_form[:attributes]
      if attrs_raw.is_a?(Hash)
        attrs_out = (form_out['attributes'] || {}).dup
        attrs_raw.each do |attr_id, attr_cfg|
          next unless attr_cfg.is_a?(Hash)

          widget = (attr_cfg['widget'] || attr_cfg[:widget]).to_s
          if widget == 'hidden_field'
            attrs_out.delete(attr_id.to_s)
            next
          end

          entry = (attrs_out[attr_id.to_s] || {}).dup
          %w[label help header].each do |f|
            val = attr_cfg[f] || attr_cfg[f.to_sym]
            entry[f] = val.to_s if val.is_a?(String) && !val.strip.empty?
          end

          opts = attr_cfg['options'] || attr_cfg[:options]
          if opts.is_a?(Array)
            opts_map = extract_translatable_options(opts)
            if opts_map.empty?
              entry.delete('options')
            else
              entry['options'] = (entry['options'] || {}).merge(opts_map)
            end
          end

          attrs_out[attr_id.to_s] = entry unless entry.empty?
        end
        form_out['attributes'] = attrs_out unless attrs_out.empty?
      end

      data['form'] = form_out unless form_out.empty?
    end

    data
  end

  private

  def app_dirs_under(root)
    return [] unless root.exist?
    return [root] if root.join('manifest.yml').file?

    root.children.select do |child|
      child.directory? && child.basename.to_s != 'dashboard' && child.join('manifest.yml').file?
    end.sort
  end

  def resolve_target_locales(locales)
    raw = if locales.present?
            Array(locales)
          elsif defined?(::Configuration) && ::Configuration.respond_to?(:supported_locales)
            Array(::Configuration.supported_locales)
          else
            []
          end
    raw.map { |l| l.to_s.strip }.reject { |s| s.empty? || %w[regional all_regional].include?(s.downcase) }.uniq
  end

  def default_dashboard_en_file
    defined?(Rails) ? Rails.root.join('config', 'locales', 'en.yml') : Pathname.new('config/locales/en.yml')
  end

  def default_locales_output_dir
    if defined?(::Configuration) && ::Configuration.respond_to?(:locales_root)
      Pathname.new(::Configuration.locales_root.to_s)
    else
      default_dashboard_en_file.dirname
    end
  end

  def writable_target?(dir)
    dir.exist? ? dir.writable? : dir.dirname.writable?
  rescue StandardError
    false
  end

  def atomic_write(path, content)
    tmp = Pathname.new("#{path}.tmp.#{Process.pid}")
    File.write(tmp, content)
    File.chmod(0o644, tmp)
    File.rename(tmp, path)
  ensure
    FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
  end

  def plain_english_locale?(tag)
    norm = tag.to_s.tr('_', '-').downcase
    norm.split('-').first == 'en' && !OodLocaleConverter::OFFLINE_STYLED_LOCALES.include?(norm)
  end

  def default_locale_display_name(tag, current)
    case tag.downcase
    when 'en-gb' then 'English (UK)'
    when 'en-ca' then 'English (Canada)'
    when 'en-hg' then "Hitchhiker's Guide (Don't Panic)"
    when 'en-cp' then 'Cyberpunk (Netrunner)'
    else
      current.to_s.strip.empty? || current == 'English' ? tag.upcase : current
    end
  end

  def translate_yaml_tree(tree, target_locale:)
    return deep_stringify(tree) if plain_english_locale?(target_locale)
    return deep_stringify(tree) unless @converter&.respond_to?(:available_for?) ? @converter.available_for?(target_locale) : @converter&.available?

    entries = []
    collect_string_paths(tree, [], entries)
    texts = entries.map(&:last)
    translated = if @converter.respond_to?(:convert_texts)
                   @converter.convert_texts(texts, target_locale: target_locale, source_locale: 'en')
                 else
                   texts.map { |s| @converter.convert_text(s, target_locale: target_locale, source_locale: 'en') || s }
                 end

    result = deep_stringify(tree)
    entries.each_with_index do |(path, orig), idx|
      put_in_tree(result, path, translated[idx] || orig)
    end
    result
  end

  def collect_string_paths(node, prefix, acc)
    case node
    when Hash
      node.each do |k, v|
        collect_string_paths(v, prefix + [k.to_s], acc)
      end
    when String
      acc << [prefix, node]
    end
  end

  def put_in_tree(root, path, val)
    cursor = root
    path[0...-1].each { |seg| cursor = cursor[seg] }
    cursor[path.last] = val
  end

  def extract_existing_en_source(dir)
    en_file = [dir.join('locales', 'en.yml'), dir.join('locales', 'en-CA.yml')].find(&:file?)
    return {} unless en_file

    stem = en_file.basename('.yml').to_s
    en_data = deep_stringify(load_existing_catalog(en_file, stem))
    return {} unless en_data.is_a?(Hash)

    out = {}
    if en_data['manifest'].is_a?(Hash)
      manifest_out = en_data['manifest'].slice('name', 'description', 'caption').select do |_k, v|
        v.is_a?(String) && !v.strip.empty?
      end
      out['manifest'] = manifest_out unless manifest_out.empty?
    end

    if en_data['form'].is_a?(Hash)
      form_out = en_data['form'].slice('title', 'description').select do |_k, v|
        v.is_a?(String) && !v.strip.empty?
      end

      if en_data['form']['attributes'].is_a?(Hash)
        attrs_out = {}
        en_data['form']['attributes'].each do |attr_id, attr_cfg|
          next unless attr_cfg.is_a?(Hash)

          entry = attr_cfg.slice('label', 'help', 'header').select do |_k, v|
            v.is_a?(String) && !v.strip.empty?
          end
          if attr_cfg['options'].is_a?(Hash)
            opts_map = attr_cfg['options'].each_with_object({}) do |(ok, ov), acc|
              s = ov.to_s
              next if skip_option_translation?(ok, s)

              acc[ok.to_s] = s
            end
            entry['options'] = opts_map unless opts_map.empty?
          end
          attrs_out[attr_id.to_s] = entry unless entry.empty?
        end
        form_out['attributes'] = attrs_out unless attrs_out.empty?
      end

      out['form'] = form_out unless form_out.empty?
    end

    if en_data['view'].is_a?(Hash)
      view_out = en_data['view'].select { |_k, v| v.is_a?(String) && !v.strip.empty? }
      out['view'] = view_out unless view_out.empty?
    end

    out
  rescue StandardError
    {}
  end

  def load_raw_form_config(dir)
    if defined?(BatchConnect::App) && defined?(PathRouter) &&
       (dir.join('form.yml').file? || dir.join('form.yml.erb').file?)
      bc_app = BatchConnect::App.new(router: PathRouter.new(dir))
      cfg = bc_app.send(:form_config)
      return cfg if cfg.is_a?(Hash) && !cfg.empty?
    end

    form_yml = dir.join('form.yml')
    form_yml.file? ? (YAML.safe_load(form_yml.read) || {}) : {}
  rescue StandardError
    form_yml = dir.join('form.yml')
    form_yml.file? ? (YAML.safe_load(form_yml.read) || {}) : {}
  end

  def extract_translatable_options(opts_array)
    opts_array.each_with_object({}) do |item, acc|
      case item
      when Array
        next if item.empty?

        label = item[0].to_s
        has_val = item.size > 1 && !item[1].is_a?(Hash)
        val_key = (has_val ? item[1] : item[0]).to_s
        next if skip_option_translation?(val_key, label)

        acc[val_key] = label
      when String, Symbol
        str = item.to_s
        next if skip_option_translation?(str, str)

        acc[str] = str
      end
    end
  end

  def load_existing_catalog(file, tag)
    return {} unless file.file?

    LocalizedValue.load_locale_yaml(file, LocalizedValue.canonical_tag(tag))
  end

  def build_locale_catalog(source, locale:, existing:, overwrite:)
    is_plain_en = plain_english_locale?(locale)
    converter_ready = @converter&.respond_to?(:available_for?) ? @converter.available_for?(locale) : @converter&.available?
    out = deep_stringify(existing)

    if source['manifest']
      out['manifest'] ||= {}
      source['manifest'].each do |field, src_val|
        next if !overwrite && out['manifest'][field].present?

        out['manifest'][field] = if is_plain_en || (field == 'name' && !converter_ready)
                                   src_val
                                 else
                                   translate_field(src_val, locale: locale) || src_val
                                 end
      end
    end

    if source['form']
      out['form'] ||= {}
      %w[title description].each do |field|
        next unless source['form'][field]
        next if !overwrite && out['form'][field].present?

        src_val = source['form'][field]
        out['form'][field] = is_plain_en ? src_val : (translate_field(src_val, locale: locale) || src_val)
      end

      if source['form']['attributes']
        out['form']['attributes'] ||= {}
        source['form']['attributes'].each do |attr_id, attr_fields|
          out['form']['attributes'][attr_id] ||= {}
          target_attr = out['form']['attributes'][attr_id]

          %w[label help header].each do |f|
            next unless attr_fields[f]
            next if !overwrite && target_attr[f].present?

            src_val = attr_fields[f]
            target_attr[f] = if is_plain_en
                               src_val
                             else
                               local_dict_lookup(attr_id, f, src_val, locale: locale) ||
                                 translate_field(src_val, locale: locale) ||
                                 src_val
                             end
          end

          next unless attr_fields['options']

          target_attr['options'] ||= {}
          attr_fields['options'].each do |opt_key, src_label|
            if skip_option_translation?(opt_key, src_label)
              target_attr['options'].delete(opt_key) if overwrite
              next
            end
            next if !overwrite && target_attr['options'][opt_key].present?

            target_attr['options'][opt_key] = if is_plain_en
                                                src_label
                                              else
                                                translate_field(src_label, locale: locale) || src_label
                                              end
          end
          target_attr.delete('options') if target_attr['options'].empty?
        end
      end
    end

    if source['view']
      out['view'] ||= {}
      source['view'].each do |vkey, src_val|
        next if !overwrite && out['view'][vkey].present?

        out['view'][vkey] = is_plain_en ? src_val : (translate_field(src_val, locale: locale) || src_val)
      end
    end

    out
  end

  # Offline lookup against OOD's built-in `dashboard.smart_attributes` catalog
  # when the app's English string matches standard OOD terminology.
  def local_dict_lookup(_attr_id, field, src_val, locale:)
    return nil unless %w[label help].include?(field)

    sym_loc = I18n.available_locales.find { |l| LocalizedValue.canonical_tag(l) == LocalizedValue.canonical_tag(locale) }
    return nil unless sym_loc

    en_map = I18n.t('dashboard.smart_attributes', locale: :en, default: {})
    return nil unless en_map.is_a?(Hash)

    cleaned = src_val.strip
    matched_key, = en_map.find { |_k, v| v.is_a?(String) && !v.include?('%{') && v.casecmp?(cleaned) }
    return nil unless matched_key

    loc_val = I18n.t("dashboard.smart_attributes.#{matched_key}", locale: sym_loc, fallback: false, default: nil)
    loc_val.presence
  end

  def translate_field(text, locale:)
    ready = @converter&.respond_to?(:available_for?) ? @converter.available_for?(locale) : @converter&.available?
    return nil unless ready

    @converter.convert_text(text, target_locale: locale, source_locale: 'en')
  end

  def deep_stringify(obj)
    case obj
    when Hash
      obj.each_with_object({}) { |(k, v), acc| acc[k.to_s] = deep_stringify(v) }
    when Array
      obj.map { |v| deep_stringify(v) }
    else
      obj
    end
  end
end
