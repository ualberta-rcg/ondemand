# frozen_string_literal: true

require 'test_helper'

class LocalesHealthTest < ActiveSupport::TestCase
  INTERPOLATION_PATTERN = /%\{([^}]+)\}/
  PLURAL_KEYS = %w[zero one two few many other].freeze

  test 'all locale YAML files have matching root keys, valid types, and safe interpolations' do
    locales_dir = Rails.root.join('config/locales')
    en_yaml = YAML.safe_load_file(locales_dir.join('en.yml'))
    en_leaves = flatten_locale_tree(en_yaml.fetch('en'))

    Dir.glob(locales_dir.join('*.yml')).sort.each do |path|
      filename = File.basename(path)
      stem = File.basename(path, '.yml')
      data = YAML.safe_load_file(path)

      assert_kind_of Hash, data, "#{filename} must parse as a YAML mapping"
      assert_equal 1, data.keys.size, "#{filename} must have a single root locale key"

      root_key = data.keys.first.to_s
      assert_equal stem.tr('_', '-').downcase, root_key.tr('_', '-').downcase,
                   "#{filename} root key '#{root_key}' must match filename"
      next if stem == 'en'

      leaves = flatten_locale_tree(data.fetch(root_key) || {})
      leaves.each do |key_path, (kind, value)|
        next unless en_leaves.key?(key_path)

        en_kind, en_value = en_leaves[key_path]
        assert_equal en_kind, kind,
                     "#{filename} key '#{key_path}' changed type (#{en_kind} in en.yml vs #{kind})"

        en_vars = extract_placeholders(en_kind, en_value)
        loc_vars = extract_placeholders(kind, value)
        unknown_vars = loc_vars - en_vars
        assert_empty unknown_vars,
                     "#{filename} key '#{key_path}' introduces unknown interpolation placeholder(s) " \
                     "#{unknown_vars.inspect} (en.yml has #{en_vars.inspect})"
      end
    end
  end

  test 'i18n-tasks config binds GOOGLE_TRANSLATE_API_KEY to google_translate_api_key' do
    erb_path = Rails.root.join('config/i18n-tasks.yml.erb')
    rendered = with_modified_env(GOOGLE_TRANSLATE_API_KEY: 'test-google-key') do
      YAML.safe_load(ERB.new(erb_path.read).result)
    end

    assert_equal 'google', rendered.dig('translation', 'backend')
    assert_equal 'test-google-key', rendered.dig('translation', 'google_translate_api_key')
  end

  private

  def flatten_locale_tree(node, prefix = '')
    out = {}
    if node.is_a?(Hash)
      str_keys = node.keys.map(&:to_s)
      if str_keys.any? && (str_keys - PLURAL_KEYS).empty? && node.values.none? { |v| v.is_a?(Hash) }
        out[prefix] = [:plural, node]
      else
        node.each do |k, v|
          child = prefix.empty? ? k.to_s : "#{prefix}.#{k}"
          out.merge!(flatten_locale_tree(v, child))
        end
      end
    else
      out[prefix] = [:scalar, node]
    end
    out
  end

  def extract_placeholders(kind, value)
    strings = kind == :plural ? value.values : [value]
    strings.grep(String).flat_map { |s| s.scan(INTERPOLATION_PATTERN).flatten }.uniq.sort
  end
end
