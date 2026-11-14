# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'yaml'

# Extracts and synchronizes standardized multi-language files on disk for:
# 1. Open OnDemand apps (`<app_dir>/locales/<locale>.yml` from `manifest.yml` & `form.yml[.erb]`)
# 2. MOTD files (`motd.<locale>` alongside `MOTD_PATH` across all 6 OOD MOTD formats)
#
# Preserves existing human-edited translations and writes static files once to disk.
class AppLocaleSync
  NON_PROSE_OPTION_REGEX = /\A[\d.\-+:\s\/x×]+\z/i

  def initialize(converter: OodLocaleConverter.new)
    @converter = converter
  end

  # Synchronize `<app_dir>/locales/<locale>.yml` for every app directory under `apps_root`.
  def sync_apps(apps_root, locales:, overwrite: false)
    root = Pathname.new(apps_root.to_s)
    return [] unless root.exist?

    app_dirs = if root.join('manifest.yml').file?
                 [root]
               else
                 root.children.select do |child|
                   child.directory? && child.basename.to_s != 'dashboard' && child.join('manifest.yml').file?
                 end.sort
               end

    app_dirs.map do |app_dir|
      sync_app(app_dir, locales: locales, overwrite: overwrite)
    end
  end

  # Extract translatable strings from a single app's `manifest.yml` & `form.yml[.erb]`
  # and write/merge `<app_dir>/locales/<locale>.yml` for each target locale.
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

      File.write(out_file, YAML.dump(tag => deep_stringify(built)))
      out_file.to_s
    end
  end

  # Generate/update per-language `motd.<locale>` files alongside `motd_path`.
  # Tracks SHA-256 of the source MOTD in a hidden `.motd.<locale>.sha256` marker
  # so unchanged source files are never re-converted and manual files aren't clobbered.
  def sync_motd(motd_path, locales:, format: ENV['MOTD_FORMAT'], force: false)
    return [] if motd_path.to_s.strip.empty?

    uri = URI.parse(motd_path.to_s)
    return [] unless uri.scheme.nil? && File.file?(motd_path.to_s)

    src_content = File.read(motd_path.to_s)
    src_sha = Digest::SHA256.hexdigest(src_content)

    Array(locales).filter_map do |loc|
      tag = MotdFile.bcp47_tag(loc)
      next if tag.split('-').first == 'en'

      out_path = MotdFile.localized_sibling_path(motd_path.to_s, tag)
      sha_path = File.join(File.dirname(out_path), ".#{File.basename(out_path)}.sha256")

      if File.exist?(out_path) && !force
        # Skip if manually maintained (no sha marker) or already up-to-date with current source sha
        next unless File.exist?(sha_path) && File.read(sha_path).strip != src_sha
      end

      next unless @converter&.available?

      converted = @converter.convert_motd(src_content, target_locale: tag, source_locale: 'en', format: format)
      next if converted.nil? || converted.empty?

      File.write(out_path, converted)
      File.write(sha_path, "#{src_sha}\n")
      out_path
    end
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
            entry['options'] = (entry['options'] || {}).merge(opts_map) unless opts_map.empty?
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

  def extract_existing_en_source(dir)
    en_file = dir.join('locales', 'en.yml')
    return {} unless en_file.file?

    en_data = deep_stringify(load_existing_catalog(en_file, 'en'))
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
              next if s.strip.empty? || s.match?(NON_PROSE_OPTION_REGEX)

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
        next if label.strip.empty? || label.match?(NON_PROSE_OPTION_REGEX)

        acc[val_key] = label
      when String, Symbol
        str = item.to_s
        next if str.strip.empty? || str.match?(NON_PROSE_OPTION_REGEX)

        acc[str] = str
      end
    end
  end

  def load_existing_catalog(file, tag)
    return {} unless file.file?

    LocalizedValue.load_locale_yaml(file, LocalizedValue.canonical_tag(tag))
  end

  def build_locale_catalog(source, locale:, existing:, overwrite:)
    is_english = locale.split('-').first.downcase == 'en'
    out = deep_stringify(existing)

    if source['manifest']
      out['manifest'] ||= {}
      source['manifest'].each do |field, src_val|
        next if !overwrite && out['manifest'][field].present?

        out['manifest'][field] = if is_english || field == 'name' && !@converter&.available?
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
        out['form'][field] = is_english ? src_val : (translate_field(src_val, locale: locale) || src_val)
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
            target_attr[f] = if is_english
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
            next if !overwrite && target_attr['options'][opt_key].present?

            target_attr['options'][opt_key] = if is_english
                                                src_label
                                              else
                                                translate_field(src_label, locale: locale) || src_label
                                              end
          end
        end
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
    return nil unless @converter&.available?

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
